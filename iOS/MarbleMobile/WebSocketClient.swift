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

    var hasActiveConnection: Bool { task != nil }

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
        guard let socket = task else {
            onDisconnected?("서버 연결이 종료되었습니다.")
            return
        }
        let currentGeneration = generation
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            let text = String(decoding: data, as: UTF8.self)
            socket.send(.string(text)) { [weak self, weak socket] error in
                guard let error else { return }
                Task { @MainActor in
                    guard let self, let socket else { return }
                    self.failCurrentConnection(
                        socket,
                        generation: currentGeneration,
                        message: error.localizedDescription
                    )
                }
            }
        } catch {
            onDisconnected?("요청을 서버에 보내지 못했습니다.")
        }
    }

    /// Foreground 복귀 시 URLSession이 background 중 끊긴 소켓을 아직
    /// receive 오류로 보고하지 않은 경우까지 확인한다. WebSocket ping은
    /// 서버 게임 프로토콜 메시지를 만들지 않는다.
    func probeConnection() {
        guard let socket = task else {
            onDisconnected?("서버 연결이 종료되었습니다.")
            return
        }
        let currentGeneration = generation
        socket.sendPing { [weak self, weak socket] error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, let socket else { return }
                self.failCurrentConnection(
                    socket,
                    generation: currentGeneration,
                    message: error.localizedDescription
                )
            }
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
                failCurrentConnection(
                    socket,
                    generation: expectedGeneration,
                    message: "서버 연결이 종료되었습니다."
                )
                return
            }
        }
    }

    private func failCurrentConnection(
        _ socket: URLSessionWebSocketTask,
        generation expectedGeneration: Int,
        message: String
    ) {
        guard generation == expectedGeneration, task === socket else { return }
        generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        socket.cancel(with: .goingAway, reason: nil)
        task = nil
        onDisconnected?(message.isEmpty ? "서버 연결이 종료되었습니다." : message)
    }
}
