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

public struct FriendPresenceSnapshot: Equatable, Sendable {
    public let userID: Int
    public let nickname: String
    public let isPresent: Bool

    public init(userID: Int, nickname: String, isPresent: Bool) {
        self.userID = userID
        self.nickname = nickname
        self.isPresent = isPresent
    }
}

public struct FriendPresenceTransition: Equatable, Sendable {
    public let userID: Int
    public let nickname: String
    public let isPresent: Bool

    public init(userID: Int, nickname: String, isPresent: Bool) {
        self.userID = userID
        self.nickname = nickname
        self.isPresent = isPresent
    }
}

public enum FriendPresenceComparator {
    public static func snapshot(_ friends: [SocialUser]) -> [Int: FriendPresenceSnapshot] {
        var result: [Int: FriendPresenceSnapshot] = [:]
        for friend in friends {
            let present = friend.connectionStatus == .connected || friend.connectionStatus == .recovering
            result[friend.userID] = FriendPresenceSnapshot(
                userID: friend.userID,
                nickname: friend.nickname,
                isPresent: present
            )
        }
        return result
    }

    public static func transitions(
        previous: [Int: FriendPresenceSnapshot],
        current: [Int: FriendPresenceSnapshot]
    ) -> [FriendPresenceTransition] {
        current.values.compactMap { now in
            guard let before = previous[now.userID], before.isPresent != now.isPresent else { return nil }
            return FriendPresenceTransition(userID: now.userID, nickname: now.nickname, isPresent: now.isPresent)
        }
        .sorted {
            if $0.nickname != $1.nickname { return $0.nickname < $1.nickname }
            return $0.userID < $1.userID
        }
    }
}

public enum SocialPresentationFormatter {
    public static func friendLabel(_ user: SocialUser) -> String {
        guard user.connectionStatus == .connected else { return "\(user.nickname), 오프라인" }
        return user.isGameInProgress ? "\(user.nickname), 게임 중" : "\(user.nickname), 접속 중"
    }
}

public enum NotePresentationFormatter {
    public static func dateTimeText(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "시간 정보 없음" }

        // timezone 정보가 없는 값은 PC와 동일하게 문자열의 벽시각을 사용한다.
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})"#
        let hasTimezone = value.hasSuffix("Z") || value.range(
            of: #"[+-]\d{2}:?\d{2}$"#,
            options: .regularExpression
        ) != nil

        if hasTimezone, let date = parseISO8601(value) {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            if let year = components.year, let month = components.month, let day = components.day,
               let hour = components.hour, let minute = components.minute {
                return formatted(year: year, month: month, day: day, hour: hour, minute: minute)
            }
        }

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges == 6 else { return value }
        func group(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return Int(value[range])
        }
        guard let year = group(1), let month = group(2), let day = group(3),
              let hour = group(4), let minute = group(5) else { return value }
        return formatted(year: year, month: month, day: day, hour: hour, minute: minute)
    }

    public static func noteRowText(_ note: NoteSnapshot, selfNickname: String) -> String {
        let sender = note.direction == .sent ? selfNickname : note.counterpart.nickname
        return "\(sender): \(note.body), \(dateTimeText(note.createdAt))"
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static func formatted(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> String {
        let period = hour < 12 ? "오전" : "오후"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(year)년 \(month)월 \(day)일 \(period) \(hour12)시 \(String(format: "%02d", minute))분"
    }
}
