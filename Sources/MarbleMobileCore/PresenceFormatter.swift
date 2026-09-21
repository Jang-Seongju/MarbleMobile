import Foundation

public enum PresenceFormatter {
    public static func label(
        nickname: String,
        status: ConnectionStatus?,
        isSelf: Bool,
        isGameInProgress: Bool
    ) -> String {
        var parts: [String] = []
        if isSelf { parts.append("나") }
        if isGameInProgress { parts.append("게임 중") }
        if let status, status != .connected {
            switch status {
            case .recovering: parts.append("복구 중")
            case .disconnected: parts.append("접속 끊김")
            case .connected: break
            }
        }
        guard !parts.isEmpty else { return nickname }
        return "\(nickname) (\(parts.joined(separator: ", ")))"
    }

    public static func roomLabel(_ room: GameRoomSummary) -> String {
        var result = "\(room.id): \(room.title)"
        if room.status == "playing" { result += " (게임 중)" }
        return result
    }
}
