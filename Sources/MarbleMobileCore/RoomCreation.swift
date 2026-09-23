import Foundation

public enum RoomCreationValidationError: Error, Equatable, LocalizedError, Sendable {
    case missingTitle
    case invalidMaxPlayers
    case missingPrivatePassword

    public var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "방 제목을 입력해 주세요."
        case .invalidMaxPlayers:
            return "참여 인원은 2~4명이어야 합니다."
        case .missingPrivatePassword:
            return "비공개 방은 비밀번호가 필요합니다."
        }
    }
}

public struct RoomCreationRequest: Equatable, Sendable {
    public let title: String
    public let maxPlayers: Int
    public let isPrivate: Bool
    public let password: String?

    public init(title: String, maxPlayers: Int, isPrivate: Bool, password: String?) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw RoomCreationValidationError.missingTitle }
        guard (2...4).contains(maxPlayers) else { throw RoomCreationValidationError.invalidMaxPlayers }

        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isPrivate && trimmedPassword.isEmpty {
            throw RoomCreationValidationError.missingPrivatePassword
        }

        self.title = trimmedTitle
        self.maxPlayers = maxPlayers
        self.isPrivate = isPrivate
        self.password = isPrivate ? trimmedPassword : nil
    }
}

public struct RoomEntrySnapshot: Equatable, Sendable {
    public let roomID: Int
    public let title: String
    public let maxPlayers: Int
    public let isPrivate: Bool
    public let hostUserID: Int
    public let gameStartAuthorityUserID: Int

    public init(
        roomID: Int,
        title: String,
        maxPlayers: Int,
        isPrivate: Bool,
        hostUserID: Int,
        gameStartAuthorityUserID: Int
    ) {
        self.roomID = roomID
        self.title = title
        self.maxPlayers = maxPlayers
        self.isPrivate = isPrivate
        self.hostUserID = hostUserID
        self.gameStartAuthorityUserID = gameStartAuthorityUserID
    }
}

public enum RoomEntryParserError: Error, Equatable, LocalizedError, Sendable {
    case invalidMessage

    public var errorDescription: String? {
        "방 권한 정보를 확인할 수 없어 게임방을 열지 못했습니다."
    }
}

public enum RoomEntryParser {
    public static func parseCreated(_ data: [String: Any]) throws -> RoomEntrySnapshot {
        guard data["type"] as? String == "room_created",
              let roomID = exactPositiveInt(data["room_id"]),
              let rawTitle = data["title"] as? String,
              rawTitle == rawTitle.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTitle.isEmpty,
              let maxPlayers = exactInt(data["max_players"]),
              (2...4).contains(maxPlayers),
              let isPrivate = data["is_private"] as? Bool,
              let hostUserID = exactPositiveInt(data["host_user_id"]),
              let authorityUserID = exactPositiveInt(data["game_start_authority_user_id"])
        else {
            throw RoomEntryParserError.invalidMessage
        }

        return RoomEntrySnapshot(
            roomID: roomID,
            title: rawTitle,
            maxPlayers: maxPlayers,
            isPrivate: isPrivate,
            hostUserID: hostUserID,
            gameStartAuthorityUserID: authorityUserID
        )
    }

    private static func exactPositiveInt(_ value: Any?) -> Int? {
        guard let result = exactInt(value), result >= 1 else { return nil }
        return result
    }

    private static func exactInt(_ value: Any?) -> Int? {
        guard let value, !(value is Bool), let result = value as? Int else { return nil }
        return result
    }
}
