import Foundation

struct AppConfiguration {
    let baseURL: URL
    let webSocketURL: URL

    static func load() -> AppConfiguration {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "MARBLE_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let input = URL(string: raw),
              let scheme = input.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              input.host != nil,
              input.path.isEmpty || input.path == "/",
              input.query == nil,
              input.fragment == nil else {
            fatalError("Info.plist의 MARBLE_BASE_URL을 API 경로/query/fragment가 없는 http(s)://host[:port] 형식으로 설정해야 합니다.")
        }

        var baseComponents = URLComponents(url: input, resolvingAgainstBaseURL: false)!
        baseComponents.path = ""
        baseComponents.query = nil
        baseComponents.fragment = nil
        guard let base = baseComponents.url else { fatalError("BASE URL을 정규화할 수 없습니다.") }

        var wsComponents = baseComponents
        wsComponents.scheme = scheme == "https" ? "wss" : "ws"
        wsComponents.path = "/ws"
        guard let ws = wsComponents.url else { fatalError("WebSocket URL을 만들 수 없습니다.") }
        return AppConfiguration(baseURL: base, webSocketURL: ws)
    }
}
