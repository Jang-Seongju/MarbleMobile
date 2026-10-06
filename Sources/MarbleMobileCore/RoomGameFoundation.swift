import Foundation

public struct RoomTeamMember: Equatable, Sendable {
    public let userID: Int
    public let nickname: String
    public let connectionStatus: ConnectionStatus?

    public init(userID: Int, nickname: String, connectionStatus: ConnectionStatus?) {
        self.userID = userID
        self.nickname = nickname
        self.connectionStatus = connectionStatus
    }
}

public struct RoomTeam: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let members: [RoomTeamMember]

    public init(id: Int, name: String, members: [RoomTeamMember]) {
        self.id = id
        self.name = name
        self.members = members
    }
}

public struct RoomUpdateSnapshot: Equatable, Sendable {
    public let roomID: Int
    public let title: String
    public let maxPlayers: Int
    public let isPrivate: Bool
    public let hostUserID: Int
    public let gameStartAuthorityUserID: Int
    public let teams: [RoomTeam]
    /// Server-authoritative room membership in join order; nil for older payloads.
    public let participants: [RoomTeamMember]?

    public init(
        roomID: Int,
        title: String,
        maxPlayers: Int,
        isPrivate: Bool,
        hostUserID: Int,
        gameStartAuthorityUserID: Int,
        teams: [RoomTeam],
        participants: [RoomTeamMember]? = nil
    ) {
        self.roomID = roomID
        self.title = title
        self.maxPlayers = maxPlayers
        self.isPrivate = isPrivate
        self.hostUserID = hostUserID
        self.gameStartAuthorityUserID = gameStartAuthorityUserID
        self.teams = teams
        self.participants = participants
    }

    public func team(containing userID: Int) -> RoomTeam? {
        teams.first { team in team.members.contains { $0.userID == userID } }
    }

    public func containsUserInTeam(_ userID: Int) -> Bool {
        team(containing: userID) != nil
    }
}

public enum RoomUpdateParserError: Error, Equatable, LocalizedError, Sendable {
    case invalidMessage

    public var errorDescription: String? { "방 상태 정보가 올바르지 않습니다." }
}

public enum RoomUpdateParser {
    public static func parse(_ data: [String: Any]) throws -> RoomUpdateSnapshot {
        guard data["type"] as? String == "room_update",
              let roomID = exactPositiveInt(data["room_id"]),
              let rawTitle = data["title"] as? String,
              rawTitle == rawTitle.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTitle.isEmpty,
              let maxPlayers = exactInt(data["max_players"]),
              (2...4).contains(maxPlayers),
              let isPrivate = data["is_private"] as? Bool,
              let hostUserID = exactPositiveInt(data["host_user_id"]),
              let authorityUserID = exactPositiveInt(data["game_start_authority_user_id"]),
              let rawTeams = data["teams"] as? [[String: Any]]
        else {
            throw RoomUpdateParserError.invalidMessage
        }

        var teamIDs = Set<Int>()
        var memberIDs = Set<Int>()
        var teams: [RoomTeam] = []
        teams.reserveCapacity(rawTeams.count)

        for rawTeam in rawTeams {
            guard let teamID = exactPositiveInt(rawTeam["id"]),
                  teamIDs.insert(teamID).inserted,
                  let teamName = rawTeam["name"] as? String,
                  teamName == teamName.trimmingCharacters(in: .whitespacesAndNewlines),
                  !teamName.isEmpty,
                  let rawMembers = rawTeam["members"] as? [[String: Any]]
            else {
                throw RoomUpdateParserError.invalidMessage
            }

            var members: [RoomTeamMember] = []
            members.reserveCapacity(rawMembers.count)
            for rawMember in rawMembers {
                guard let userID = exactPositiveInt(rawMember["user_id"]),
                      memberIDs.insert(userID).inserted,
                      let nickname = rawMember["nickname"] as? String,
                      nickname == nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                      !nickname.isEmpty
                else {
                    throw RoomUpdateParserError.invalidMessage
                }

                let connectionStatus: ConnectionStatus?
                if let rawStatus = rawMember["connection_status"] {
                    guard let statusText = rawStatus as? String,
                          let status = ConnectionStatus(rawValue: statusText)
                    else {
                        throw RoomUpdateParserError.invalidMessage
                    }
                    connectionStatus = status
                } else {
                    connectionStatus = nil
                }

                members.append(.init(
                    userID: userID,
                    nickname: nickname,
                    connectionStatus: connectionStatus
                ))
            }
            teams.append(.init(id: teamID, name: teamName, members: members))
        }

        let participants: [RoomTeamMember]?
        if let rawParticipants = data["participants"] {
            guard let entries = rawParticipants as? [[String: Any]] else {
                throw RoomUpdateParserError.invalidMessage
            }
            var seen = Set<Int>()
            var parsed: [RoomTeamMember] = []
            for entry in entries {
                guard let userID = exactPositiveInt(entry["user_id"]), seen.insert(userID).inserted,
                      let nickname = entry["nickname"] as? String,
                      nickname == nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                      !nickname.isEmpty,
                      let rawStatus = entry["connection_status"] as? String,
                      let status = ConnectionStatus(rawValue: rawStatus)
                else { throw RoomUpdateParserError.invalidMessage }
                parsed.append(.init(userID: userID, nickname: nickname, connectionStatus: status))
            }
            participants = parsed
        } else {
            participants = nil
        }

        return RoomUpdateSnapshot(
            roomID: roomID,
            title: rawTitle,
            maxPlayers: maxPlayers,
            isPrivate: isPrivate,
            hostUserID: hostUserID,
            gameStartAuthorityUserID: authorityUserID,
            teams: teams,
            participants: participants
        )
    }

    private static func exactPositiveInt(_ value: Any?) -> Int? {
        guard let result = exactInt(value), result >= 1 else { return nil }
        return result
    }

    private static func exactInt(_ value: Any?) -> Int? {
        WireScalarParser.exactInt(value)
    }
}

public struct RoomChatMessage: Equatable, Sendable {
    public let fromUserID: Int
    public let fromNickname: String
    public let message: String

    public init(fromUserID: Int, fromNickname: String, message: String) {
        self.fromUserID = fromUserID
        self.fromNickname = fromNickname
        self.message = message
    }
}

public enum RoomChatParserError: Error, Equatable, Sendable {
    case invalidMessage
}

public enum RoomChatParser {
    public static func parse(_ data: [String: Any]) throws -> RoomChatMessage {
        guard data["type"] as? String == "room_chat",
              let fromUserID = exactPositiveInt(data["from_id"]),
              let fromNickname = data["from_nickname"] as? String,
              fromNickname == fromNickname.trimmingCharacters(in: .whitespacesAndNewlines),
              !fromNickname.isEmpty,
              let message = data["message"] as? String,
              message == message.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else {
            throw RoomChatParserError.invalidMessage
        }
        return .init(fromUserID: fromUserID, fromNickname: fromNickname, message: message)
    }

    private static func exactPositiveInt(_ value: Any?) -> Int? {
        guard let result = WireScalarParser.exactInt(value), result >= 1 else { return nil }
        return result
    }
}

public enum RoomEventFormatter {
    public static func message(from data: [String: Any], eventKey: String = "event") -> String? {
        guard let type = data["type"] as? String else { return nil }
        if eventKey == "event" {
            guard type == "room_event" else { return nil }
        } else if eventKey == "lifecycle_event" {
            guard type == "spectator_left" else { return nil }
        } else {
            return nil
        }
        guard let event = data[eventKey] as? String, !event.isEmpty else { return nil }

        let nickname = displayIdentity(
            nickname: data["actor_nickname"],
            userID: data["actor_user_id"]
        )

        switch event {
        case "participant_joined":
            return nickname.map { "\(subject($0)) 입장했습니다." }
        case "participant_left":
            return nickname.map { "\(subject($0)) 퇴장했습니다." }
        case "participant_kicked":
            return nickname.map { "\(subject($0)) 방장에 의해 퇴장 처리되었습니다." }
        case "spectator_entered":
            guard let nickname,
                  let observed = displayIdentity(
                    nickname: data["observed_nickname"],
                    userID: data["observed_user_id"]
                  )
            else { return nil }
            return "\(subject(nickname)) \(observed)의 관중석으로 입장했습니다."
        case "spectator_left":
            return nickname.map { "\(subject($0)) 퇴장했습니다." }
        case "host_changed":
            return nickname.map { "\(subject($0)) 방장이 되었습니다." }
        case "game_start_authority_changed":
            return nickname.map { "\(subject($0)) 시작할 수 있습니다." }
        case "team_created":
            guard let nickname,
                  let rawTeamName = data["team_name"] as? String
            else { return nil }
            let teamName = rawTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !teamName.isEmpty else { return nil }
            return "\(subject(nickname)) '\(teamName)' 팀을 만들었습니다."
        case "player_connection_status_changed":
            guard let nickname, let status = data["connection_status"] as? String else { return nil }
            switch status {
            case "disconnected": return "\(nickname)의 접속이 끊겼습니다."
            case "recovering": return "\(subject(nickname)) 게임을 복구하고 있습니다."
            case "connected": return "\(subject(nickname)) 게임에 다시 접속했습니다."
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func displayIdentity(nickname: Any?, userID: Any?) -> String? {
        if let value = nickname as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let id = userID as? Int, id >= 1 { return "사용자 \(id)" }
        return nil
    }

    private static func subject(_ text: String) -> String {
        if text == "나" || text == "내" || text == "당신" { return "당신이" }
        return text + (hasBatchim(text) ? "이" : "가")
    }

    private static func hasBatchim(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.last else { return false }
        let value = Int(scalar.value)
        let start = 0xAC00
        let end = 0xD7A3
        guard value >= start && value <= end else { return false }
        return (value - start) % 28 != 0
    }
}
