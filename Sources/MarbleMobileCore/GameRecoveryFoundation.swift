import Foundation

public struct RecoveryTurnSnapshot: Equatable, Sendable {
    public let currentPlayerID: Int?
    public let turnGeneration: Int?
    public let hasStarted: Bool
    public let nextTurnCommand: String?
    public let turnDeadlineAt: String?
    public let turnRemainingSeconds: Double?

    public init(
        currentPlayerID: Int?,
        turnGeneration: Int?,
        hasStarted: Bool,
        nextTurnCommand: String?,
        turnDeadlineAt: String?,
        turnRemainingSeconds: Double?
    ) {
        self.currentPlayerID = currentPlayerID
        self.turnGeneration = turnGeneration
        self.hasStarted = hasStarted
        self.nextTurnCommand = nextTurnCommand
        self.turnDeadlineAt = turnDeadlineAt
        self.turnRemainingSeconds = turnRemainingSeconds
    }
}

public struct RecoveryHeldCardSnapshot: Equatable, Sendable {
    public let cardID: String
    public let name: String
    public let description: String

    public init(cardID: String, name: String, description: String) {
        self.cardID = cardID
        self.name = name
        self.description = description
    }
}

public enum IslandEscapeReservationType: String, Equatable, Sendable {
    case bailPayment = "bail_payment"
    case islandEscapeCard = "island_escape_card"
}

public struct GameRecoverySnapshot: Equatable, Sendable {
    public let recoveryID: String
    public let roomID: Int
    public let roomTitle: String
    public let maxPlayers: Int
    public let isPrivate: Bool
    public let gameSessionID: String
    public let gameStatus: String
    public let yourPlayerID: Int
    public let gameState: GameStateSnapshot
    public let boardCatalog: BoardCatalogSnapshot
    public let staticInformation: StaticInformationCatalogSnapshot
    public let turn: RecoveryTurnSnapshot
    public let heldCard: RecoveryHeldCardSnapshot?
    public let salaryBoosterCardID: String?
    public let selectedActiveCardID: String?
    public let islandEscapeReservationType: IslandEscapeReservationType?
    public let pendingInteraction: InteractionRequestSnapshot?

    public init(
        recoveryID: String,
        roomID: Int,
        roomTitle: String,
        maxPlayers: Int,
        isPrivate: Bool,
        gameSessionID: String,
        gameStatus: String,
        yourPlayerID: Int,
        gameState: GameStateSnapshot,
        boardCatalog: BoardCatalogSnapshot,
        staticInformation: StaticInformationCatalogSnapshot,
        turn: RecoveryTurnSnapshot,
        heldCard: RecoveryHeldCardSnapshot?,
        salaryBoosterCardID: String?,
        selectedActiveCardID: String?,
        islandEscapeReservationType: IslandEscapeReservationType?,
        pendingInteraction: InteractionRequestSnapshot?
    ) {
        self.recoveryID = recoveryID
        self.roomID = roomID
        self.roomTitle = roomTitle
        self.maxPlayers = maxPlayers
        self.isPrivate = isPrivate
        self.gameSessionID = gameSessionID
        self.gameStatus = gameStatus
        self.yourPlayerID = yourPlayerID
        self.gameState = gameState
        self.boardCatalog = boardCatalog
        self.staticInformation = staticInformation
        self.turn = turn
        self.heldCard = heldCard
        self.salaryBoosterCardID = salaryBoosterCardID
        self.selectedActiveCardID = selectedActiveCardID
        self.islandEscapeReservationType = islandEscapeReservationType
        self.pendingInteraction = pendingInteraction
    }
}

public enum GameRecoveryParserError: Error, Equatable, LocalizedError, Sendable {
    case invalidMessage
    public var errorDescription: String? { "게임 복구 정보가 올바르지 않습니다." }
}

public enum GameRecoveryParser {
    public static func parse(_ data: [String: Any]) throws -> GameRecoverySnapshot {
        guard data["type"] as? String == "game_recovery_snapshot",
              let recoveryID = requiredString(data["recovery_id"]),
              let room = data["room"] as? [String: Any],
              let roomID = positiveInt(room["room_id"]),
              let roomTitle = exactString(room["title"], allowEmpty: true),
              let maxPlayers = WireScalarParser.exactInt(room["max_players"]), (2...4).contains(maxPlayers),
              let isPrivate = WireScalarParser.exactBool(room["is_private"]),
              let game = data["game"] as? [String: Any],
              let gameSessionID = requiredString(game["game_session_id"]),
              let gameStatus = requiredString(game["status"]),
              let yourPlayerID = positiveInt(game["your_player_id"]),
              let players = game["players"] as? [[String: Any]],
              let cities = game["cities"] as? [[String: Any]],
              let boardCells = game["board_cells"] as? [[String: Any]],
              let staticInformationRaw = game["static_information"] as? [String: Any],
              let turnRaw = game["turn"] as? [String: Any],
              let privatePlayer = data["private_player"] as? [String: Any],
              positiveInt(privatePlayer["player_id"]) == yourPlayerID
        else { throw GameRecoveryParserError.invalidMessage }

        let currentPlayerRaw = game["current_player_id"]
        let currentPlayerID: Int?
        if currentPlayerRaw == nil || currentPlayerRaw is NSNull {
            currentPlayerID = nil
        } else {
            guard let parsed = positiveInt(currentPlayerRaw) else { throw GameRecoveryParserError.invalidMessage }
            currentPlayerID = parsed
        }

        let gameState: GameStateSnapshot
        do {
            gameState = try GameplayParser.gameState([
                "type": "game_state",
                "players": players,
                "cities": cities,
                "current_player_id": currentPlayerID ?? NSNull(),
            ])
        } catch {
            throw GameRecoveryParserError.invalidMessage
        }
        guard gameState.players.contains(where: { $0.playerID == yourPlayerID }) else {
            throw GameRecoveryParserError.invalidMessage
        }

        let boardCatalog: BoardCatalogSnapshot
        do {
            boardCatalog = try BoardCellsParser.parse([
                "type": "board_cells",
                "board_cells": boardCells,
            ])
        } catch {
            throw GameRecoveryParserError.invalidMessage
        }

        let staticInformation: StaticInformationCatalogSnapshot
        do {
            staticInformation = try StaticInformationCatalogParser.parse(staticInformationRaw)
        } catch {
            throw GameRecoveryParserError.invalidMessage
        }

        try validateTeams(data["teams"], players: gameState.players)

        let turn = try parseTurn(turnRaw, players: gameState.players)
        if turn.currentPlayerID != currentPlayerID {
            throw GameRecoveryParserError.invalidMessage
        }

        let heldCard = try parseHeldCard(privatePlayer["held_card"])
        let salaryBoosterCardID = try optionalNonblankString(privatePlayer["salary_booster_card_id"])
        guard let turnPreparation = privatePlayer["turn_preparation"] as? [String: Any] else {
            throw GameRecoveryParserError.invalidMessage
        }
        let selectedActiveCardID = try optionalNonblankString(turnPreparation["selected_active_card_id"])
        let reservationType: IslandEscapeReservationType?
        if turnPreparation["island_escape_reservation_type"] == nil || turnPreparation["island_escape_reservation_type"] is NSNull {
            reservationType = nil
        } else {
            guard let raw = turnPreparation["island_escape_reservation_type"] as? String,
                  let parsed = IslandEscapeReservationType(rawValue: raw) else {
                throw GameRecoveryParserError.invalidMessage
            }
            reservationType = parsed
        }

        let pendingInteraction: InteractionRequestSnapshot?
        if privatePlayer["pending_interaction_request"] == nil || privatePlayer["pending_interaction_request"] is NSNull {
            pendingInteraction = nil
        } else {
            guard let raw = privatePlayer["pending_interaction_request"] as? [String: Any] else {
                throw GameRecoveryParserError.invalidMessage
            }
            do { pendingInteraction = try InteractionRequestParser.parse(raw) }
            catch { throw GameRecoveryParserError.invalidMessage }
        }

        return GameRecoverySnapshot(
            recoveryID: recoveryID,
            roomID: roomID,
            roomTitle: roomTitle,
            maxPlayers: maxPlayers,
            isPrivate: isPrivate,
            gameSessionID: gameSessionID,
            gameStatus: gameStatus,
            yourPlayerID: yourPlayerID,
            gameState: gameState,
            boardCatalog: boardCatalog,
            staticInformation: staticInformation,
            turn: turn,
            heldCard: heldCard,
            salaryBoosterCardID: salaryBoosterCardID,
            selectedActiveCardID: selectedActiveCardID,
            islandEscapeReservationType: reservationType,
            pendingInteraction: pendingInteraction
        )
    }

    private static func parseTurn(_ data: [String: Any], players: [GamePlayerSnapshot]) throws -> RecoveryTurnSnapshot {
        let current: Int?
        if data["current_player_id"] == nil || data["current_player_id"] is NSNull {
            current = nil
        } else {
            guard let value = positiveInt(data["current_player_id"]), players.contains(where: { $0.playerID == value }) else {
                throw GameRecoveryParserError.invalidMessage
            }
            current = value
        }
        let generation: Int?
        if data["turn_generation"] == nil || data["turn_generation"] is NSNull {
            generation = nil
        } else {
            guard let value = positiveInt(data["turn_generation"]) else { throw GameRecoveryParserError.invalidMessage }
            generation = value
        }
        guard let hasStarted = WireScalarParser.exactBool(data["has_started"]) else {
            throw GameRecoveryParserError.invalidMessage
        }
        let next = try optionalNonblankString(data["next_turn_command"])
        if current == nil, next != nil { throw GameRecoveryParserError.invalidMessage }
        if current != nil, next == nil { throw GameRecoveryParserError.invalidMessage }
        let deadline = try optionalNonblankString(data["turn_deadline_at"])
        let remaining: Double?
        if data["turn_remaining_seconds"] == nil || data["turn_remaining_seconds"] is NSNull {
            remaining = nil
        } else {
            guard let number = WireScalarParser.nonBooleanNumber(data["turn_remaining_seconds"]), number.doubleValue >= 0 else {
                throw GameRecoveryParserError.invalidMessage
            }
            remaining = number.doubleValue
        }
        return .init(
            currentPlayerID: current,
            turnGeneration: generation,
            hasStarted: hasStarted,
            nextTurnCommand: next,
            turnDeadlineAt: deadline,
            turnRemainingSeconds: remaining
        )
    }

    private static func parseHeldCard(_ value: Any?) throws -> RecoveryHeldCardSnapshot? {
        if value == nil || value is NSNull { return nil }
        guard let raw = value as? [String: Any],
              let cardID = requiredString(raw["card_id"]),
              let name = requiredString(raw["name"]),
              let description = exactString(raw["description"], allowEmpty: true)
        else { throw GameRecoveryParserError.invalidMessage }
        return .init(cardID: cardID, name: name, description: description)
    }

    private static func validateTeams(_ value: Any?, players: [GamePlayerSnapshot]) throws {
        guard let teams = value as? [[String: Any]] else { throw GameRecoveryParserError.invalidMessage }
        var humansByUserID: [Int: GamePlayerSnapshot] = [:]
        for player in players where !player.isAI {
            guard let userID = player.userID, humansByUserID[userID] == nil else {
                throw GameRecoveryParserError.invalidMessage
            }
            humansByUserID[userID] = player
        }
        var teamIDs = Set<Int>()
        var memberIDs = Set<Int>()
        for team in teams {
            guard let teamID = positiveInt(team["id"]), teamIDs.insert(teamID).inserted,
                  exactString(team["name"], allowEmpty: true) != nil,
                  let members = team["members"] as? [[String: Any]] else {
                throw GameRecoveryParserError.invalidMessage
            }
            for member in members {
                guard let userID = positiveInt(member["user_id"]), memberIDs.insert(userID).inserted,
                      let nickname = exactString(member["nickname"], allowEmpty: true),
                      let connectionStatus = member["connection_status"] as? String,
                      ["connected", "recovering", "disconnected"].contains(connectionStatus),
                      let player = humansByUserID[userID],
                      player.nickname == nickname,
                      player.connectionStatus == connectionStatus else {
                    throw GameRecoveryParserError.invalidMessage
                }
            }
        }
    }

    private static func requiredString(_ value: Any?) -> String? {
        guard let value = value as? String,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func exactString(_ value: Any?, allowEmpty: Bool) -> String? {
        guard let value = value as? String,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              allowEmpty || !value.isEmpty else { return nil }
        return value
    }

    private static func optionalNonblankString(_ value: Any?) throws -> String? {
        if value == nil || value is NSNull { return nil }
        guard let parsed = requiredString(value) else { throw GameRecoveryParserError.invalidMessage }
        return parsed
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = WireScalarParser.exactInt(value), value > 0 else { return nil }
        return value
    }
}

public struct RecoveryCompletionTurnLifecycle: Equatable, Sendable {
    public let currentPlayerID: Int?
    public let turnGeneration: Int?
    public let hasStarted: Bool
    public let nextTurnCommand: String?
    public let turnDeadlineAt: String?
    public let turnRemainingSeconds: Double?
    public let humanControlled: Bool
}

public enum RecoveryCompletionParser {
    public static func turnLifecycle(_ data: Any?) throws -> RecoveryCompletionTurnLifecycle {
        guard let data = data as? [String: Any],
              let hasStarted = WireScalarParser.exactBool(data["has_started"]),
              let humanControlled = WireScalarParser.exactBool(data["human_controlled"]) else {
            throw GameRecoveryParserError.invalidMessage
        }
        let current: Int?
        if data["current_player_id"] == nil || data["current_player_id"] is NSNull { current = nil }
        else { guard let value = positiveInt(data["current_player_id"]) else { throw GameRecoveryParserError.invalidMessage }; current = value }
        let generation: Int?
        if data["turn_generation"] == nil || data["turn_generation"] is NSNull { generation = nil }
        else { guard let value = positiveInt(data["turn_generation"]) else { throw GameRecoveryParserError.invalidMessage }; generation = value }
        let next = try optionalNonblankString(data["next_turn_command"])
        if current == nil, next != nil { throw GameRecoveryParserError.invalidMessage }
        if current != nil, next == nil { throw GameRecoveryParserError.invalidMessage }
        let deadline = try optionalNonblankString(data["turn_deadline_at"])
        let remaining: Double?
        if data["turn_remaining_seconds"] == nil || data["turn_remaining_seconds"] is NSNull { remaining = nil }
        else {
            guard let number = WireScalarParser.nonBooleanNumber(data["turn_remaining_seconds"]), number.doubleValue >= 0 else {
                throw GameRecoveryParserError.invalidMessage
            }
            remaining = number.doubleValue
        }
        return .init(
            currentPlayerID: current,
            turnGeneration: generation,
            hasStarted: hasStarted,
            nextTurnCommand: next,
            turnDeadlineAt: deadline,
            turnRemainingSeconds: remaining,
            humanControlled: humanControlled
        )
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = WireScalarParser.exactInt(value), value > 0 else { return nil }
        return value
    }

    private static func optionalNonblankString(_ value: Any?) throws -> String? {
        if value == nil || value is NSNull { return nil }
        guard let value = value as? String,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { throw GameRecoveryParserError.invalidMessage }
        return value
    }
}
