import Foundation

public enum SpectatorProtocolError: Error, Equatable, LocalizedError, Sendable {
    case invalidMessage

    public var errorDescription: String? { "관중석 정보가 올바르지 않습니다." }
}

public struct SpectatorTarget: Identifiable, Equatable, Sendable {
    public let observedUserID: Int
    public let nickname: String
    public var id: Int { observedUserID }

    public init(observedUserID: Int, nickname: String) {
        self.observedUserID = observedUserID
        self.nickname = nickname
    }
}

public struct SpectatorTargetList: Identifiable, Equatable, Sendable {
    public let roomID: Int
    public let targets: [SpectatorTarget]
    public var id: Int { roomID }

    public init(roomID: Int, targets: [SpectatorTarget]) {
        self.roomID = roomID
        self.targets = targets
    }
}

public struct SpectatorRegistrationSnapshot: Equatable, Sendable {
    public let roomID: Int
    public let observedUserID: Int
    public let observedUserNickname: String

    public init(roomID: Int, observedUserID: Int, observedUserNickname: String) {
        self.roomID = roomID
        self.observedUserID = observedUserID
        self.observedUserNickname = observedUserNickname
    }
}

public struct SpectatorLeftSnapshot: Equatable, Sendable {
    public let roomID: Int
    public let observedUserID: Int

    public init(roomID: Int, observedUserID: Int) {
        self.roomID = roomID
        self.observedUserID = observedUserID
    }
}

public struct SpectatorEntryRequest: Equatable, Sendable {
    public let roomID: Int
    public let isPrivate: Bool

    public init(roomID: Int, isPrivate: Bool) {
        self.roomID = roomID
        self.isPrivate = isPrivate
    }
}

public struct SpectatorJoinExpectation: Equatable, Sendable {
    public let request: SpectatorEntryRequest
    public let target: SpectatorTarget

    public init(request: SpectatorEntryRequest, target: SpectatorTarget) {
        self.request = request
        self.target = target
    }
}

public enum SpectatorClientPhase: String, Equatable, Sendable {
    case idle
    case targetListPending
    case targetSelection
    case passwordEntry
    case joinPending
    case bootstrapping
    case active
    case participationPending
    case participationLeftReceived
    case leavePending
    case aborting
}

public enum SpectatorParticipationValidator {
    public static func acceptsLeft(_ data: [String: Any], expected: SpectatorRegistrationSnapshot) -> Bool {
        guard let left = try? SpectatorParser.left(data) else { return false }
        return left.roomID == expected.roomID && left.observedUserID == expected.observedUserID
    }

    public static func joined(_ data: [String: Any], expected: SpectatorRegistrationSnapshot) throws -> RoomEntrySnapshot {
        let joined = try RoomEntryParser.parseJoined(data)
        guard joined.roomID == expected.roomID else { throw RoomEntryParserError.invalidMessage }
        return joined
    }
}

public enum SpectatorParser {
    public static func targetList(_ data: [String: Any]) throws -> SpectatorTargetList {
        guard data["type"] as? String == "spectator_target_list",
              let roomID = positiveInt(data["room_id"]),
              let rawPlayers = data["players"] as? [[String: Any]]
        else { throw SpectatorProtocolError.invalidMessage }

        var seen = Set<Int>()
        var targets: [SpectatorTarget] = []
        targets.reserveCapacity(rawPlayers.count)
        for raw in rawPlayers {
            guard let userID = positiveInt(raw["observed_user_id"]),
                  seen.insert(userID).inserted,
                  let nickname = strictNonBlank(raw["nickname"])
            else { throw SpectatorProtocolError.invalidMessage }
            targets.append(.init(observedUserID: userID, nickname: nickname))
        }
        return .init(roomID: roomID, targets: targets)
    }

    public static func joined(_ data: [String: Any]) throws -> SpectatorRegistrationSnapshot {
        guard data["type"] as? String == "spectator_joined",
              let roomID = positiveInt(data["room_id"]),
              let userID = positiveInt(data["observed_user_id"]),
              let nickname = strictNonBlank(data["observed_user_nickname"])
        else { throw SpectatorProtocolError.invalidMessage }
        return .init(roomID: roomID, observedUserID: userID, observedUserNickname: nickname)
    }

    public static func left(_ data: [String: Any]) throws -> SpectatorLeftSnapshot {
        guard data["type"] as? String == "spectator_left",
              let roomID = positiveInt(data["room_id"]),
              let userID = positiveInt(data["observed_user_id"])
        else { throw SpectatorProtocolError.invalidMessage }
        return .init(roomID: roomID, observedUserID: userID)
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
