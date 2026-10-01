import Foundation

public enum ConnectionStatus: String, Codable, Sendable {
    case connected
    case recovering
    case disconnected
}

public struct LobbyUser: Identifiable, Equatable, Sendable {
    public let id: Int
    public let nickname: String
    public let connectionStatus: ConnectionStatus?
    public let isGameInProgress: Bool

    public init(id: Int, nickname: String, connectionStatus: ConnectionStatus?, isGameInProgress: Bool) {
        self.id = id
        self.nickname = nickname
        self.connectionStatus = connectionStatus
        self.isGameInProgress = isGameInProgress
    }
}

public struct GameRoomSummary: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let current: Int?
    public let maxPlayers: Int?
    public let isPrivate: Bool?
    public let status: String?

    public init(id: Int, title: String, current: Int?, maxPlayers: Int?, isPrivate: Bool?, status: String?) {
        self.id = id
        self.title = title
        self.current = current
        self.maxPlayers = maxPlayers
        self.isPrivate = isPrivate
        self.status = status
    }
}

public struct SocialUser: Equatable, Sendable {
    public let userID: Int
    public let nickname: String
    public init(userID: Int, nickname: String) {
        self.userID = userID
        self.nickname = nickname
    }
}

public struct FriendRequest: Equatable, Sendable {
    public let requestID: Int
    public let user: SocialUser
    public var isRead: Bool
    public init(requestID: Int, user: SocialUser, isRead: Bool = true) {
        self.requestID = requestID
        self.user = user
        self.isRead = isRead
    }
}

public struct SocialState: Equatable, Sendable {
    public var friends: [SocialUser]
    public var incomingRequests: [FriendRequest]
    public var outgoingRequests: [FriendRequest]
    public var blockedUsers: [SocialUser]

    public init(
        friends: [SocialUser] = [], incomingRequests: [FriendRequest] = [],
        outgoingRequests: [FriendRequest] = [], blockedUsers: [SocialUser] = []
    ) {
        self.friends = friends
        self.incomingRequests = incomingRequests
        self.outgoingRequests = outgoingRequests
        self.blockedUsers = blockedUsers
    }

    public func isFriend(_ userID: Int) -> Bool { friends.contains { $0.userID == userID } }
    public func isBlocked(_ userID: Int) -> Bool { blockedUsers.contains { $0.userID == userID } }
    public func incomingRequest(for userID: Int) -> FriendRequest? { incomingRequests.first { $0.user.userID == userID } }
    public func outgoingRequest(for userID: Int) -> FriendRequest? { outgoingRequests.first { $0.user.userID == userID } }
}
