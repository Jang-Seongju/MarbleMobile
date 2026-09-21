import Foundation

public enum WireParsingError: Error, Equatable {
    case invalidPayload
}

public enum WireParser {
    public static func lobbyUsers(from payload: [String: Any]) throws -> [LobbyUser] {
        guard let rawUsers = payload["users"] as? [[String: Any]] else { throw WireParsingError.invalidPayload }
        return rawUsers.compactMap { raw in
            guard let id = raw["user_id"] as? Int else { return nil }
            let nickname = (raw["nickname"] as? String) ?? "사용자 \(id)"
            let status = (raw["connection_status"] as? String).flatMap(ConnectionStatus.init(rawValue:))
            return LobbyUser(
                id: id,
                nickname: nickname,
                connectionStatus: status,
                isGameInProgress: raw["is_game_in_progress"] as? Bool == true
            )
        }
    }

    public static func rooms(from payload: [String: Any]) throws -> [GameRoomSummary] {
        guard let rawRooms = payload["rooms"] as? [[String: Any]] else { throw WireParsingError.invalidPayload }
        return rawRooms.compactMap { raw in
            guard let id = raw["id"] as? Int else { return nil }
            return GameRoomSummary(
                id: id,
                title: (raw["title"] as? String) ?? "이름 없는 방",
                current: raw["current"] as? Int,
                maxPlayers: raw["max_players"] as? Int,
                isPrivate: raw["is_private"] as? Bool,
                status: raw["status"] as? String
            )
        }
    }

    public static func socialState(from payload: [String: Any]) -> SocialState {
        func user(_ raw: [String: Any]) -> SocialUser? {
            guard let id = raw["user_id"] as? Int else { return nil }
            return SocialUser(userID: id, nickname: (raw["nickname"] as? String) ?? "사용자 \(id)")
        }
        func users(_ value: Any?) -> [SocialUser] {
            (value as? [[String: Any]] ?? []).compactMap(user)
        }
        func requests(_ value: Any?) -> [FriendRequest] {
            (value as? [[String: Any]] ?? []).compactMap { raw in
                guard let requestID = raw["request_id"] as? Int,
                      let rawUser = raw["user"] as? [String: Any],
                      let u = user(rawUser) else { return nil }
                return FriendRequest(requestID: requestID, user: u)
            }
        }
        return SocialState(
            friends: users(payload["friends"]),
            incomingRequests: requests(payload["incoming_friend_requests"]),
            outgoingRequests: requests(payload["outgoing_friend_requests"]),
            blockedUsers: users(payload["blocked_users"])
        )
    }
}
