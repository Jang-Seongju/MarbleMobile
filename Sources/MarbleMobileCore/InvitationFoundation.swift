import Foundation

public enum GameInvitationType: String, Equatable, Sendable {
    case room
    case spectator

    public var koreanKind: String {
        switch self {
        case .room: return "게임방"
        case .spectator: return "관중석"
        }
    }
}

public enum InvitationProtocolError: Error, Equatable, LocalizedError, Sendable {
    case invalidMessage

    public var errorDescription: String? { "초대 정보가 올바르지 않습니다." }
}

public struct InvitationUserSnapshot: Equatable, Sendable {
    public let userID: Int
    public let nickname: String

    public init(userID: Int, nickname: String) {
        self.userID = userID
        self.nickname = nickname
    }
}

public struct InvitationRoomSnapshot: Equatable, Sendable {
    public let roomID: Int
    public let title: String
    public let isPrivate: Bool

    public init(roomID: Int, title: String, isPrivate: Bool) {
        self.roomID = roomID
        self.title = title
        self.isPrivate = isPrivate
    }
}

public struct GameInvitation: Identifiable, Equatable, Sendable {
    public let inviteID: Int
    public let inviteType: GameInvitationType
    public let inviter: InvitationUserSnapshot
    public let room: InvitationRoomSnapshot
    public let spectatorTarget: SpectatorTarget?

    public var id: Int { inviteID }

    public init(
        inviteID: Int,
        inviteType: GameInvitationType,
        inviter: InvitationUserSnapshot,
        room: InvitationRoomSnapshot,
        spectatorTarget: SpectatorTarget? = nil
    ) {
        self.inviteID = inviteID
        self.inviteType = inviteType
        self.inviter = inviter
        self.room = room
        self.spectatorTarget = spectatorTarget
    }

    /// client(393)은 같은 발신자/방/유형의 재초대를 새 capability로 교체한다.
    public func replaces(_ other: GameInvitation) -> Bool {
        inviter.userID == other.inviter.userID
            && room.roomID == other.room.roomID
            && inviteType == other.inviteType
    }

    public var listLabel: String {
        switch inviteType {
        case .room:
            return "\(inviter.nickname) - \(room.roomID)번 \(room.title) 방으로 초대"
        case .spectator:
            return "\(inviter.nickname) - \(room.roomID)번 \(room.title) 방 관중석으로 초대"
        }
    }
}

public struct InvitationSentSnapshot: Equatable, Sendable {
    public let inviteID: Int
    public let inviteType: GameInvitationType
    public let targetUserID: Int
    public let targetNickname: String
    public let roomID: Int
    public let roomTitle: String
}

public struct InvitationConsumedSnapshot: Equatable, Sendable {
    public let inviteID: Int
    public let inviteType: GameInvitationType
    public let roomID: Int
}

public enum InvitationParser {
    public static func received(_ data: [String: Any]) throws -> GameInvitation {
        guard data["type"] as? String == "invitation_received",
              let inviteID = positiveInt(data["invite_id"]),
              let inviteType = invitationType(data["invite_type"]),
              let rawInviter = data["inviter"] as? [String: Any],
              let inviterUserID = positiveInt(rawInviter["user_id"]),
              let inviterNickname = strictNonBlank(rawInviter["nickname"]),
              let rawRoom = data["room"] as? [String: Any],
              let roomID = positiveInt(rawRoom["room_id"]),
              let title = strictNonBlank(rawRoom["title"]),
              let isPrivate = WireScalarParser.exactBool(rawRoom["is_private"])
        else { throw InvitationProtocolError.invalidMessage }

        let target: SpectatorTarget?
        switch inviteType {
        case .room:
            guard data["spectator_target"] == nil || data["spectator_target"] is NSNull else {
                throw InvitationProtocolError.invalidMessage
            }
            target = nil
        case .spectator:
            guard let rawTarget = data["spectator_target"] as? [String: Any],
                  let observedUserID = positiveInt(rawTarget["observed_user_id"]),
                  let nickname = strictNonBlank(rawTarget["nickname"])
            else { throw InvitationProtocolError.invalidMessage }
            target = .init(observedUserID: observedUserID, nickname: nickname)
        }

        return GameInvitation(
            inviteID: inviteID,
            inviteType: inviteType,
            inviter: .init(userID: inviterUserID, nickname: inviterNickname),
            room: .init(roomID: roomID, title: title, isPrivate: isPrivate),
            spectatorTarget: target
        )
    }

    public static func sent(_ data: [String: Any]) throws -> InvitationSentSnapshot {
        guard data["type"] as? String == "invitation_sent",
              let inviteID = positiveInt(data["invite_id"]),
              let inviteType = invitationType(data["invite_type"]),
              let targetUserID = positiveInt(data["target_user_id"]),
              let targetNickname = strictNonBlank(data["target_nickname"]),
              let roomID = positiveInt(data["room_id"]),
              let roomTitle = strictNonBlank(data["room_title"])
        else { throw InvitationProtocolError.invalidMessage }
        return .init(
            inviteID: inviteID,
            inviteType: inviteType,
            targetUserID: targetUserID,
            targetNickname: targetNickname,
            roomID: roomID,
            roomTitle: roomTitle
        )
    }

    public static func consumed(_ data: [String: Any]) throws -> InvitationConsumedSnapshot {
        guard data["type"] as? String == "invitation_consumed",
              let inviteID = positiveInt(data["invite_id"]),
              let inviteType = invitationType(data["invite_type"]),
              let roomID = positiveInt(data["room_id"])
        else { throw InvitationProtocolError.invalidMessage }
        return .init(inviteID: inviteID, inviteType: inviteType, roomID: roomID)
    }

    private static func invitationType(_ value: Any?) -> GameInvitationType? {
        guard let raw = value as? String else { return nil }
        return GameInvitationType(rawValue: raw)
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = WireScalarParser.exactInt(value), value > 0 else { return nil }
        return value
    }

    private static func strictNonBlank(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return value
    }
}
