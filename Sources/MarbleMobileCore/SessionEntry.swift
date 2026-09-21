import Foundation

public enum SessionEntryMode: String, Equatable, Sendable {
    case normalLobby = "normal_lobby"
    case activeGameRecovery = "active_game_recovery"
}

public struct SessionEntry: Equatable, Sendable {
    public let mode: SessionEntryMode
    public let recoveryID: String?
    public let roomID: Int?
    public let gameSessionID: String?
    public let yourPlayerID: Int?

    public init(
        mode: SessionEntryMode,
        recoveryID: String? = nil,
        roomID: Int? = nil,
        gameSessionID: String? = nil,
        yourPlayerID: Int? = nil
    ) {
        self.mode = mode
        self.recoveryID = recoveryID
        self.roomID = roomID
        self.gameSessionID = gameSessionID
        self.yourPlayerID = yourPlayerID
    }
}

public enum SessionEntryParseError: Error, Equatable {
    case invalidPayload
}

public enum SessionEntryParser {
    public static func parse(_ payload: [String: Any]) throws -> SessionEntry {
        guard payload["type"] as? String == "session_entry",
              let rawMode = payload["entry_mode"] as? String,
              let mode = SessionEntryMode(rawValue: rawMode) else {
            throw SessionEntryParseError.invalidPayload
        }

        let recoveryFields = ["recovery_id", "room_id", "game_session_id", "your_player_id"]

        switch mode {
        case .normalLobby:
            guard recoveryFields.allSatisfy({ payload[$0] == nil }) else {
                throw SessionEntryParseError.invalidPayload
            }
            return SessionEntry(mode: .normalLobby)

        case .activeGameRecovery:
            guard let recoveryID = nonblankString(payload["recovery_id"]),
                  let roomID = positiveInt(payload["room_id"]),
                  let gameSessionID = nonblankString(payload["game_session_id"]),
                  let yourPlayerID = positiveInt(payload["your_player_id"]) else {
                throw SessionEntryParseError.invalidPayload
            }
            return SessionEntry(
                mode: .activeGameRecovery,
                recoveryID: recoveryID,
                roomID: roomID,
                gameSessionID: gameSessionID,
                yourPlayerID: yourPlayerID
            )
        }
    }

    private static func nonblankString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard !(value is Bool), let value = value as? Int, value > 0 else { return nil }
        return value
    }
}
