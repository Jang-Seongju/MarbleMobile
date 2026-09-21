import Foundation

@MainActor
final class WebSocketClient: ObservableObject {
    var onMessage: (([String: Any]) -> Void)?
    var onDisconnected: ((String) -> Void)?

    private let config: AppConfiguration
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var generation = 0

    init(config: AppConfiguration) { self.config = config }

    func connect(accessToken: String) {
        disconnect(notify: false)
        generation += 1
        let currentGeneration = generation

        var components = URLComponents(url: config.webSocketURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: accessToken)]
        guard let url = components.url else { return }
        let socket = URLSession.shared.webSocketTask(with: url)
        task = socket
        socket.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(socket, generation: currentGeneration)
        }
    }

    func send(_ object: [String: Any]) {
        guard let socket = task else { return }
        let currentGeneration = generation
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            let text = String(decoding: data, as: UTF8.self)
            socket.send(.string(text)) { [weak self, weak socket] error in
                guard let error else { return }
                Task { @MainActor in
                    guard let self, let socket,
                          self.generation == currentGeneration,
                          self.task === socket else { return }
                    self.onDisconnected?(error.localizedDescription)
                }
            }
        } catch {
            onDisconnected?("요청을 서버에 보내지 못했습니다.")
        }
    }

    func disconnect(notify: Bool = false) {
        generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if notify { onDisconnected?("서버 연결이 종료되었습니다.") }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask, generation expectedGeneration: Int) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                guard generation == expectedGeneration, task === socket else { return }
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let received): data = received
                @unknown default: continue
                }
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                onMessage?(object)
            } catch {
                guard !Task.isCancelled,
                      generation == expectedGeneration,
                      task === socket else { return }
                onDisconnected?("서버 연결이 종료되었습니다.")
                return
            }
        }
    }
}
