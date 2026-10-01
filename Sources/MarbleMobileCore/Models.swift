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
    public let connectionStatus: ConnectionStatus?
    public let isGameInProgress: Bool

    public init(
        userID: Int, nickname: String,
        connectionStatus: ConnectionStatus? = nil,
        isGameInProgress: Bool = false
    ) {
        self.userID = userID
        self.nickname = nickname
        self.connectionStatus = connectionStatus
        self.isGameInProgress = isGameInProgress
    }

    public func mergingPresence(_ presence: LobbyUser?) -> SocialUser {
        guard let presence else {
            return .init(
                userID: userID, nickname: nickname,
                connectionStatus: .disconnected, isGameInProgress: false
            )
        }
        return .init(
            userID: userID, nickname: presence.nickname,
            connectionStatus: presence.connectionStatus ?? .disconnected,
            isGameInProgress: presence.isGameInProgress
        )
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
    public var searchResults: [SocialUser]
    public var searchQuery: String

    public init(
        friends: [SocialUser] = [], incomingRequests: [FriendRequest] = [],
        outgoingRequests: [FriendRequest] = [], blockedUsers: [SocialUser] = [],
        searchResults: [SocialUser] = [], searchQuery: String = ""
    ) {
        self.friends = friends
        self.incomingRequests = incomingRequests
        self.outgoingRequests = outgoingRequests
        self.blockedUsers = blockedUsers
        self.searchResults = searchResults
        self.searchQuery = searchQuery
    }

    public func isFriend(_ userID: Int) -> Bool { friends.contains { $0.userID == userID } }
    public func isBlocked(_ userID: Int) -> Bool { blockedUsers.contains { $0.userID == userID } }
    public func incomingRequest(for userID: Int) -> FriendRequest? { incomingRequests.first { $0.user.userID == userID } }
    public func outgoingRequest(for userID: Int) -> FriendRequest? { outgoingRequests.first { $0.user.userID == userID } }

    public mutating func mergePresence(_ lobbyUsers: [LobbyUser]) {
        var byID: [Int: LobbyUser] = [:]
        for user in lobbyUsers { byID[user.id] = user }
        friends = friends.map { $0.mergingPresence(byID[$0.userID]) }
        incomingRequests = incomingRequests.map { request in
            FriendRequest(
                requestID: request.requestID,
                user: request.user.mergingPresence(byID[request.user.userID]),
                isRead: request.isRead
            )
        }
        outgoingRequests = outgoingRequests.map { request in
            FriendRequest(
                requestID: request.requestID,
                user: request.user.mergingPresence(byID[request.user.userID]),
                isRead: request.isRead
            )
        }
        blockedUsers = blockedUsers.map { $0.mergingPresence(byID[$0.userID]) }
        searchResults = searchResults.map { $0.mergingPresence(byID[$0.userID]) }
        friends.sort { lhs, rhs in
            let lOffline = lhs.connectionStatus != .connected
            let rOffline = rhs.connectionStatus != .connected
            if lOffline != rOffline { return !lOffline }
            if lhs.nickname != rhs.nickname { return lhs.nickname < rhs.nickname }
            return lhs.userID < rhs.userID
        }
    }
}
