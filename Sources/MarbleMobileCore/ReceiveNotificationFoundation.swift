import Foundation

public enum ReceiveNotificationKind: String, CaseIterable, Identifiable, Sendable {
    case messages
    case notes
    case invitations
    case friendRequests

    public var id: String { rawValue }

    public func title(count: Int) -> String {
        switch self {
        case .messages: return "새 메시지 \(count)"
        case .notes: return "새 쪽지 \(count)"
        case .invitations: return "초대 \(count)"
        case .friendRequests: return "친구 요청 \(count)"
        }
    }
}

public struct PrivateChatEvent: Equatable, Sendable {
    public let userID: Int
    public let nickname: String
    public let message: String

    public init(userID: Int, nickname: String, message: String) {
        self.userID = userID
        self.nickname = nickname
        self.message = message
    }
}

public enum NoteDirection: String, Equatable, Sendable {
    case received
    case sent
}

public struct NoteSnapshot: Identifiable, Equatable, Sendable {
    public let noteID: Int
    public let counterpart: SocialUser
    public let body: String
    public let createdAt: String?
    public var isRead: Bool
    public let direction: NoteDirection

    public var id: Int { noteID }

    public init(
        noteID: Int,
        counterpart: SocialUser,
        body: String,
        createdAt: String?,
        isRead: Bool,
        direction: NoteDirection
    ) {
        self.noteID = noteID
        self.counterpart = counterpart
        self.body = body
        self.createdAt = createdAt
        self.isRead = isRead
        self.direction = direction
    }
}

public enum ReceivePayloadParser {
    public static func privateChat(_ payload: [String: Any]) -> PrivateChatEvent? {
        guard payload["type"] as? String == "chat",
              let userID = positiveInt(payload["from_id"]),
              let message = payload["message"] as? String,
              !message.isEmpty else { return nil }
        let nickname = nonBlank(payload["from_nickname"]) ?? "사용자 \(userID)"
        return .init(userID: userID, nickname: nickname, message: message)
    }

    public static func privateChatSent(_ payload: [String: Any]) -> PrivateChatEvent? {
        guard payload["type"] as? String == "chat_sent",
              let userID = positiveInt(payload["target_id"]),
              let message = payload["message"] as? String,
              !message.isEmpty else { return nil }
        let nickname = nonBlank(payload["target_nickname"]) ?? "사용자 \(userID)"
        return .init(userID: userID, nickname: nickname, message: message)
    }

    public static func notes(from payload: [String: Any]) -> [NoteSnapshot]? {
        guard payload["type"] as? String == "note_mailbox",
              let received = payload["received_notes"] as? [[String: Any]],
              let sent = payload["sent_notes"] as? [[String: Any]] else { return nil }
        let receivedNotes = received.compactMap { note($0, direction: .received) }
        let sentNotes = sent.compactMap { note($0, direction: .sent) }
        return (receivedNotes + sentNotes).sorted(by: noteSort)
    }

    public static func noteEvent(_ payload: [String: Any], direction: NoteDirection) -> NoteSnapshot? {
        guard let raw = payload["note"] as? [String: Any] else { return nil }
        return note(raw, direction: direction)
    }

    public static func friendRequestEvent(_ payload: [String: Any]) -> FriendRequest? {
        guard payload["type"] as? String == "friend_request_received",
              let requestID = positiveInt(payload["request_id"]),
              let rawUser = payload["user"] as? [String: Any],
              let userID = positiveInt(rawUser["user_id"]) else { return nil }
        let nickname = nonBlank(rawUser["nickname"]) ?? "사용자 \(userID)"
        let isRead = WireScalarParser.exactBool(payload["is_read"]) ?? false
        return FriendRequest(requestID: requestID, user: .init(userID: userID, nickname: nickname), isRead: isRead)
    }

    private static func note(_ raw: [String: Any], direction: NoteDirection) -> NoteSnapshot? {
        guard let noteID = positiveInt(raw["note_id"]),
              let rawUser = raw["user"] as? [String: Any],
              let userID = positiveInt(rawUser["user_id"]),
              let body = raw["body"] as? String else { return nil }
        let nickname = nonBlank(rawUser["nickname"]) ?? "사용자 \(userID)"
        return NoteSnapshot(
            noteID: noteID,
            counterpart: .init(userID: userID, nickname: nickname),
            body: body,
            createdAt: raw["created_at"] as? String,
            isRead: WireScalarParser.exactBool(raw["is_read"]) ?? false,
            direction: direction
        )
    }

    private static func noteSort(_ lhs: NoteSnapshot, _ rhs: NoteSnapshot) -> Bool {
        let l = lhs.createdAt ?? ""
        let r = rhs.createdAt ?? ""
        if l != r { return l > r }
        return lhs.noteID > rhs.noteID
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = WireScalarParser.exactInt(value), value > 0 else { return nil }
        return value
    }

    private static func nonBlank(_ value: Any?) -> String? {
        guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
