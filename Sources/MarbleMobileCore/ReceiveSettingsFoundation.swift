import Foundation

public enum ReceiveAudience: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case friendsOnly = "friends_only"
    case none

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "모두 수신"
        case .friendsOnly: return "친구만 수신"
        case .none: return "수신 안 함"
        }
    }
}

public enum FriendRequestAudience: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case none

    public var id: String { rawValue }
    public var title: String { self == .all ? "수신" : "수신 안 함" }
}

public struct ReceiveSettings: Equatable, Sendable {
    public var message: ReceiveAudience
    public var note: ReceiveAudience
    public var invitation: ReceiveAudience
    public var friendRequest: FriendRequestAudience

    public init(
        message: ReceiveAudience = .all,
        note: ReceiveAudience = .all,
        invitation: ReceiveAudience = .all,
        friendRequest: FriendRequestAudience = .all
    ) {
        self.message = message
        self.note = note
        self.invitation = invitation
        self.friendRequest = friendRequest
    }

    /// PC SocialClientState와 같이 유효한 서버 필드만 현재 값에 반영한다.
    public func merging(_ payload: [String: Any]) -> ReceiveSettings {
        var copy = self
        if let value = payload["message_policy"] as? String, let policy = ReceiveAudience(rawValue: value) {
            copy.message = policy
        }
        if let value = payload["note_policy"] as? String, let policy = ReceiveAudience(rawValue: value) {
            copy.note = policy
        }
        if let value = payload["invitation_policy"] as? String, let policy = ReceiveAudience(rawValue: value) {
            copy.invitation = policy
        }
        if let value = payload["friend_request_policy"] as? String,
           let policy = FriendRequestAudience(rawValue: value) {
            copy.friendRequest = policy
        }
        return copy
    }
}
