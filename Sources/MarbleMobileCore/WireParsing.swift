import Foundation
import CoreFoundation


public enum WireScalarParser {
    public static func nonBooleanNumber(_ value: Any?) -> NSNumber? {
        guard let value, !(value is NSNull), let number = value as? NSNumber else { return nil }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number
    }

    public static func exactBool(_ value: Any?) -> Bool? {
        guard let value, !(value is NSNull), let number = value as? NSNumber else { return nil }
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    public static func exactInt(_ value: Any?) -> Int? {
        guard let value, let number = nonBooleanNumber(value) else { return nil }

        // JSONSerialization represents JSON integers as NSNumber. Values 0 and 1
        // also bridge to Swift Bool via `is Bool`, so `value is Bool` cannot be
        // used to distinguish JSON booleans from JSON integers. Core Foundation
        // type identity distinguishes true JSON booleans; the NSNumber encoding
        // then keeps floating-point JSON numbers outside the exact-int contract.
        let encoding = String(cString: number.objCType)
        guard encoding != "f", encoding != "d" else { return nil }
        return value as? Int
    }
}

public enum WireParsingError: Error, Equatable {
    case invalidPayload
}

public enum WireParser {
    public static func lobbyUsers(from payload: [String: Any]) throws -> [LobbyUser] {
        guard let rawUsers = payload["users"] as? [[String: Any]] else { throw WireParsingError.invalidPayload }
        return rawUsers.compactMap { raw in
            guard let id = WireScalarParser.exactInt(raw["user_id"]) else { return nil }
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
            guard let id = WireScalarParser.exactInt(raw["id"]) else { return nil }
            return GameRoomSummary(
                id: id,
                title: (raw["title"] as? String) ?? "이름 없는 방",
                current: WireScalarParser.exactInt(raw["current"]),
                maxPlayers: WireScalarParser.exactInt(raw["max_players"]),
                isPrivate: raw["is_private"] as? Bool,
                status: raw["status"] as? String
            )
        }
    }

    public static func socialState(from payload: [String: Any]) -> SocialState {
        func user(_ raw: [String: Any]) -> SocialUser? {
            guard let id = WireScalarParser.exactInt(raw["user_id"]) else { return nil }
            return SocialUser(userID: id, nickname: (raw["nickname"] as? String) ?? "사용자 \(id)")
        }
        func users(_ value: Any?) -> [SocialUser] {
            (value as? [[String: Any]] ?? []).compactMap(user)
        }
        func requests(_ value: Any?, incoming: Bool) -> [FriendRequest] {
            (value as? [[String: Any]] ?? []).compactMap { raw in
                guard let requestID = WireScalarParser.exactInt(raw["request_id"]),
                      let rawUser = raw["user"] as? [String: Any],
                      let u = user(rawUser) else { return nil }
                let isRead = incoming ? (WireScalarParser.exactBool(raw["is_read"]) ?? false) : true
                return FriendRequest(requestID: requestID, user: u, isRead: isRead)
            }
        }
        return SocialState(
            friends: users(payload["friends"]),
            incomingRequests: requests(payload["incoming_friend_requests"], incoming: true),
            outgoingRequests: requests(payload["outgoing_friend_requests"], incoming: false),
            blockedUsers: users(payload["blocked_users"])
        )
    }
}
