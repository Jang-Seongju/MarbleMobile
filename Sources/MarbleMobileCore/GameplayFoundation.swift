import Foundation

public struct AIPlayerOption: Identifiable, Equatable, Sendable {
    public let aiID: String
    public let nickname: String
    public var id: String { aiID }

    public init(aiID: String, nickname: String) {
        self.aiID = aiID
        self.nickname = nickname
    }
}

public struct AIPlayerSelectionRequest: Identifiable, Equatable, Sendable {
    public var id: String { requestID }
    public let requestID: String
    public let roomID: Int
    public let humanPlayerCount: Int
    public let maxPlayers: Int
    public let minimumAICount: Int
    public let maximumAICount: Int
    public let allowedAICounts: [Int]
    public let availableAI: [AIPlayerOption]
}

public enum AIPlayerSelectionParserError: Error, Equatable, LocalizedError, Sendable {
    case invalidMessage
    public var errorDescription: String? { "AI 플레이어 선택 정보가 올바르지 않습니다." }
}

public enum AIPlayerSelectionParser {
    public static func parse(_ data: [String: Any]) throws -> AIPlayerSelectionRequest {
        guard data["type"] as? String == "game_start_ai_selection_required",
              let requestID = trimmedRequired(data["request_id"]),
              let roomID = positiveInt(data["room_id"]),
              let humanCount = positiveInt(data["human_player_count"]),
              let maxPlayers = WireScalarParser.exactInt(data["max_players"]), (2...4).contains(maxPlayers),
              humanCount <= maxPlayers
        else { throw AIPlayerSelectionParserError.invalidMessage }

        let remaining = maxPlayers - humanCount
        guard remaining >= 1,
              let minimum = WireScalarParser.exactInt(data["minimum_ai_count"]),
              let maximum = WireScalarParser.exactInt(data["maximum_ai_count"]),
              minimum == (humanCount == 1 ? 1 : 0),
              maximum == remaining,
              let rawAllowed = data["allowed_ai_counts"] as? [Any]
        else { throw AIPlayerSelectionParserError.invalidMessage }

        let allowed = rawAllowed.compactMap(WireScalarParser.exactInt)
        guard allowed.count == rawAllowed.count,
              Set(allowed).count == allowed.count,
              allowed == Array(minimum...maximum),
              let rawOptions = data["available_ai_participants"] as? [[String: Any]]
        else { throw AIPlayerSelectionParserError.invalidMessage }

        var seen = Set<String>()
        var options: [AIPlayerOption] = []
        for raw in rawOptions {
            guard let aiID = trimmedRequired(raw["ai_id"]),
                  let nickname = trimmedRequired(raw["nickname"]),
                  seen.insert(aiID).inserted
            else { throw AIPlayerSelectionParserError.invalidMessage }
            options.append(.init(aiID: aiID, nickname: nickname))
        }
        guard options.count >= maximum else { throw AIPlayerSelectionParserError.invalidMessage }

        return .init(
            requestID: requestID,
            roomID: roomID,
            humanPlayerCount: humanCount,
            maxPlayers: maxPlayers,
            minimumAICount: minimum,
            maximumAICount: maximum,
            allowedAICounts: allowed,
            availableAI: options
        )
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = WireScalarParser.exactInt(value), value > 0 else { return nil }
        return value
    }

    private static func trimmedRequired(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return value
    }
}

public struct GamePlayerSnapshot: Identifiable, Equatable, Sendable {
    public let playerID: Int
    public let userID: Int?
    public let nickname: String
    public let teamName: String
    public let marble: Int
    public let position: Int
    public let lapCount: Int
    public let isStranded: Bool
    public let isBankrupt: Bool
    public let isAI: Bool

    public var id: Int { playerID }
}

public struct GameStartedSnapshot: Equatable, Sendable {
    public let yourPlayerID: Int
    public let currentPlayerID: Int
    public let players: [GamePlayerSnapshot]
    public let festivalCityIDs: [Int]
    public let boardCatalog: BoardCatalogSnapshot
}

public struct GameStateSnapshot: Equatable, Sendable {
    public let currentPlayerID: Int?
    public let players: [GamePlayerSnapshot]
}

public enum GameplayParserError: Error, Equatable, LocalizedError, Sendable {
    case invalidMessage
    public var errorDescription: String? { "게임 상태 정보가 올바르지 않습니다." }
}

public enum GameplayParser {
    public static func gameStarted(_ data: [String: Any]) throws -> GameStartedSnapshot {
        guard data["type"] as? String == "game_started",
              let yourPlayerID = positiveInt(data["your_player_id"]),
              let currentPlayerID = positiveInt(data["current_player_id"]),
              let rawPlayers = data["players"] as? [[String: Any]],
              let rawFestival = data["festival_city_ids"] as? [Any],
              let rawBoard = data["board_cells"] as? [[String: Any]]
        else { throw GameplayParserError.invalidMessage }

        let players = try parsePlayers(rawPlayers)
        guard players.contains(where: { $0.playerID == yourPlayerID }),
              players.contains(where: { $0.playerID == currentPlayerID })
        else { throw GameplayParserError.invalidMessage }

        let festival = rawFestival.compactMap(WireScalarParser.exactInt)
        guard festival.count == rawFestival.count,
              !festival.isEmpty,
              festival.allSatisfy({ $0 > 0 }),
              Set(festival).count == festival.count
        else { throw GameplayParserError.invalidMessage }

        let board = try BoardCellsParser.parse(["type": "board_cells", "board_cells": rawBoard])
        return .init(
            yourPlayerID: yourPlayerID,
            currentPlayerID: currentPlayerID,
            players: players,
            festivalCityIDs: festival,
            boardCatalog: board
        )
    }

    public static func gameState(_ data: [String: Any]) throws -> GameStateSnapshot {
        guard data["type"] as? String == "game_state",
              let rawPlayers = data["players"] as? [[String: Any]]
        else { throw GameplayParserError.invalidMessage }
        let players = try parsePlayers(rawPlayers)
        let current: Int?
        if data["current_player_id"] == nil || data["current_player_id"] is NSNull {
            current = nil
        } else {
            guard let parsed = positiveInt(data["current_player_id"]) else { throw GameplayParserError.invalidMessage }
            current = parsed
        }
        if let current, !players.contains(where: { $0.playerID == current }) {
            throw GameplayParserError.invalidMessage
        }
        return .init(currentPlayerID: current, players: players)
    }

    public static func turnStarted(_ data: [String: Any]) throws -> TurnStartedSnapshot {
        guard data["type"] as? String == "notification",
              data["notification_type"] as? String == "turn_started",
              let payload = data["payload"] as? [String: Any],
              let playerID = positiveInt(payload["player_id"]),
              let generation = positiveInt(payload["turn_generation"]),
              let next = trimmedRequired(payload["next_turn_command"] ?? "roll_dice")
        else { throw GameplayParserError.invalidMessage }
        return .init(playerID: playerID, turnGeneration: generation, nextTurnCommand: next)
    }

    public static func notificationType(_ data: [String: Any]) -> String? {
        guard data["type"] as? String == "notification" else { return nil }
        return data["notification_type"] as? String
    }

    public static func notificationPayload(_ data: [String: Any]) -> [String: Any]? {
        guard data["type"] as? String == "notification" else { return nil }
        return data["payload"] as? [String: Any]
    }

    private static func parsePlayers(_ rawPlayers: [[String: Any]]) throws -> [GamePlayerSnapshot] {
        guard !rawPlayers.isEmpty else { throw GameplayParserError.invalidMessage }
        var ids = Set<Int>()
        var result: [GamePlayerSnapshot] = []
        for raw in rawPlayers {
            guard let playerID = positiveInt(raw["player_id"]), ids.insert(playerID).inserted,
                  let nickname = trimmedRequired(raw["nickname"]),
                  let teamName = trimmedRequired(raw["team_name"]),
                  let marble = WireScalarParser.exactInt(raw["marble"]),
                  let position = WireScalarParser.exactInt(raw["position"]), (1...32).contains(position),
                  let lapCount = WireScalarParser.exactInt(raw["lap_count"]), lapCount >= 0,
                  let isAI = WireScalarParser.exactBool(raw["is_ai"])
            else { throw GameplayParserError.invalidMessage }

            let userID: Int?
            if raw["user_id"] == nil || raw["user_id"] is NSNull {
                userID = nil
            } else {
                guard let parsed = positiveInt(raw["user_id"]) else { throw GameplayParserError.invalidMessage }
                userID = parsed
            }

            let stranded = WireScalarParser.exactBool(raw["is_stranded"]) ?? false
            let bankrupt = WireScalarParser.exactBool(raw["is_bankrupt"]) ?? false
            result.append(.init(
                playerID: playerID,
                userID: userID,
                nickname: nickname,
                teamName: teamName,
                marble: marble,
                position: position,
                lapCount: lapCount,
                isStranded: stranded,
                isBankrupt: bankrupt,
                isAI: isAI
            ))
        }
        return result
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = WireScalarParser.exactInt(value), value > 0 else { return nil }
        return value
    }

    private static func trimmedRequired(_ value: Any?) -> String? {
        guard let value = value as? String,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}

public struct TurnStartedSnapshot: Equatable, Sendable {
    public let playerID: Int
    public let turnGeneration: Int
    public let nextTurnCommand: String
}

public struct InteractionItemSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let cityID: Int?
    public let cost: Int
    public let disabled: Bool
    public let action: String?
}

public struct InteractionGroupSnapshot: Identifiable, Equatable, Sendable {
    public let role: String
    public let items: [InteractionItemSnapshot]
    public var id: String { role }
}

public struct StartBuildCitySnapshot: Identifiable, Equatable, Sendable {
    public let cityID: Int
    public let label: String
    public let buildOptions: [InteractionItemSnapshot]
    public var id: Int { cityID }
}

public struct InteractionRequestSnapshot: Identifiable, Equatable, Sendable {
    public let requestID: String
    public let flowID: String
    public let actionType: String
    public let interactionType: String
    public let cancellable: Bool
    public let missionType: String
    public let title: String
    public let description: String
    public let items: [InteractionItemSnapshot]
    public let groups: [InteractionGroupSnapshot]
    public let startBuildCities: [StartBuildCitySnapshot]
    public let excludedIndices: Set<Int>
    public let allowedDestinationIndices: [Int]
    public let ownedMarble: Int
    public let requiredAmount: Int
    public let cardName: String?
    public let cardDescription: String?
    public var id: String { requestID }
}

public enum InteractionRequestParserError: Error, Equatable, LocalizedError, Sendable {
    case invalidMessage
    public var errorDescription: String? { "게임 선택 정보가 올바르지 않습니다." }
}

public enum InteractionRequestParser {
    private static let supportedTypes: Set<String> = [
        "confirm", "select_one", "select_multiple", "select_one_per_group",
        "select_destination", "acknowledge", "select_city_and_buildings"
    ]

    public static func parse(_ data: [String: Any]) throws -> InteractionRequestSnapshot {
        guard data["type"] as? String == "interaction_request",
              let requestID = requiredString(data["request_id"]),
              let flowID = requiredString(data["interaction_flow_id"]),
              let actionType = requiredString(data["action_type"]),
              let interactionType = requiredString(data["interaction_type"]),
              supportedTypes.contains(interactionType),
              let cancellable = WireScalarParser.exactBool(data["cancellable"]),
              let payload = data["payload"] as? [String: Any]
        else { throw InteractionRequestParserError.invalidMessage }

        let mission = (payload["mission_type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? actionType
        let items = try parseItems(payload["items"])
        let groups = try parseGroups(payload["groups"])
        let cities = try parseStartBuildCities(payload["cities"])
        let excluded = try parseExcluded(payload["excluded_indices"])
        let allowedDestinations = try parseAllowedDestinations(payload["allowed_destinations"])
        let owned = WireScalarParser.exactInt(payload[mission == "liquidation" ? "current_marble" : "owned_marble"]) ?? 0
        let required = WireScalarParser.exactInt(payload["required_amount"]) ?? 0
        let cardName = optionalString(payload["card_name"])
        let cardDescription = optionalString(payload["card_description"])

        return .init(
            requestID: requestID,
            flowID: flowID,
            actionType: actionType,
            interactionType: interactionType,
            cancellable: cancellable,
            missionType: mission,
            title: title(mission: mission, payload: payload, groups: groups),
            description: description(mission: mission, interactionType: interactionType, payload: payload),
            items: items,
            groups: groups,
            startBuildCities: cities,
            excludedIndices: excluded,
            allowedDestinationIndices: allowedDestinations,
            ownedMarble: owned,
            requiredAmount: required,
            cardName: cardName,
            cardDescription: cardDescription
        )
    }

    private static func parseItems(_ value: Any?) throws -> [InteractionItemSnapshot] {
        guard let value else { return [] }
        guard let raw = value as? [[String: Any]] else { throw InteractionRequestParserError.invalidMessage }
        var ids = Set<String>()
        return try raw.map { item in
            guard let itemID = itemID(item), ids.insert(itemID).inserted else { throw InteractionRequestParserError.invalidMessage }
            let disabled = WireScalarParser.exactBool(item["disabled"]) ?? false
            let cityID = WireScalarParser.exactInt(item["city_id"])
            let cost = WireScalarParser.exactInt(item["sell_value"])
                ?? WireScalarParser.exactInt(item["build_cost"])
                ?? WireScalarParser.exactInt(item["cost"])
                ?? 0
            let action = optionalString(item["action"])
            return .init(id: itemID, label: itemLabel(item), cityID: cityID, cost: cost, disabled: disabled, action: action)
        }
    }

    private static func parseGroups(_ value: Any?) throws -> [InteractionGroupSnapshot] {
        guard let value else { return [] }
        guard let raw = value as? [[String: Any]] else { throw InteractionRequestParserError.invalidMessage }
        var roles = Set<String>()
        return try raw.map { group in
            guard let role = requiredString(group["role"]), roles.insert(role).inserted else { throw InteractionRequestParserError.invalidMessage }
            let items = try parseItems(group["items"])
            guard !items.isEmpty else { throw InteractionRequestParserError.invalidMessage }
            return .init(role: role, items: items)
        }
    }

    private static func parseStartBuildCities(_ value: Any?) throws -> [StartBuildCitySnapshot] {
        guard let value else { return [] }
        guard let raw = value as? [[String: Any]] else { throw InteractionRequestParserError.invalidMessage }
        var ids = Set<Int>()
        return try raw.map { city in
            guard let cityID = positiveInt(city["city_id"]), ids.insert(cityID).inserted else { throw InteractionRequestParserError.invalidMessage }
            let name = optionalString(city["city_name"]) ?? "도시 \(cityID)"
            let group = optionalString(city["group_name"] ?? city["group"])
            let buildings = (city["buildings"] as? [String] ?? [])
            let status = buildings.isEmpty ? "" : ", \(buildings.joined(separator: ", "))"
            let groupText = group.map { ", \($0)" } ?? ""
            let options = try parseItems(city["build_options"])
            return .init(cityID: cityID, label: "\(name)\(groupText)\(status)", buildOptions: options)
        }
    }


    private static func parseAllowedDestinations(_ value: Any?) throws -> [Int] {
        guard let value else { return [] }
        guard let raw = value as? [Any] else { throw InteractionRequestParserError.invalidMessage }
        let parsed = raw.compactMap(WireScalarParser.exactInt)
        guard parsed.count == raw.count,
              parsed.allSatisfy({ (1...32).contains($0) }),
              Set(parsed).count == parsed.count
        else { throw InteractionRequestParserError.invalidMessage }
        return parsed
    }

    private static func parseExcluded(_ value: Any?) throws -> Set<Int> {
        guard let value else { return [] }
        guard let raw = value as? [Any] else { throw InteractionRequestParserError.invalidMessage }
        let parsed = raw.compactMap(WireScalarParser.exactInt)
        guard parsed.count == raw.count, parsed.allSatisfy({ (1...32).contains($0) }) else {
            throw InteractionRequestParserError.invalidMessage
        }
        return Set(parsed)
    }

    private static func title(mission: String, payload: [String: Any], groups: [InteractionGroupSnapshot]) -> String {
        if mission == "fortune_selection" {
            let card = optionalString(payload["card_name"]) ?? "포춘카드"
            if groups.contains(where: { $0.role == "attack_city" }) { return "\(card) 대상 선택" }
            return card
        }
        if mission == "defense" {
            switch optionalString(payload["defense_type"]) {
            case "attack": return "공격 방어"
            case "toll": return "통행료 방어"
            default: return "방어"
            }
        }
        return [
            "purchase_city": "도시 구매", "build_multiple": "건물 건설",
            "acquire_city": "도시 인수", "liquidation": "자산 매각",
            "world_travel_destination": "세계여행 목적지", "world_travel_offer": "세계여행",
            "olympic": "올림픽 개최", "bonus_game": "보너스 게임",
            "fortune_card": "포춘카드", "fortune_card_hold_choice": "포춘카드 보관",
            "start_cell_build_confirm": "확인", "start_cell_build_selection": "건물 건설"
        ][mission] ?? "선택"
    }

    private static func description(mission: String, interactionType: String, payload: [String: Any]) -> String {
        func marble(_ value: Any?) -> String {
            guard let number = WireScalarParser.exactInt(value) else { return "0마블" }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            return "\(formatter.string(from: NSNumber(value: number)) ?? String(number))마블"
        }
        let city = optionalString(payload["city_name"]) ?? "도시"
        switch mission {
        case "purchase_city": return "\(city) 구매하시겠습니까?\n비용: \(marble(payload["cost"]))"
        case "build_multiple": return "\(city)에 건설할 건물을 선택하세요."
        case "acquire_city": return "\(optionalString(payload["owner_nickname"]) ?? "") 소유의 \(city) 인수하시겠습니까?\n인수 비용: \(marble(payload["cost"]))"
        case "liquidation": return "매각할 자산을 선택하세요."
        case "world_travel_offer": return "세계여행을 하시겠습니까? 비용은 \(marble(payload["cost"] ?? 100000))입니다."
        case "world_travel_destination": return "세계여행 목적지를 선택하세요."
        case "olympic":
            if interactionType == "confirm" { return "올림픽을 개최하시겠습니까? 비용: \(marble(payload["cost"] ?? 100000))" }
            return "올림픽을 개최할 도시를 선택하세요."
        case "bonus_game":
            let step = WireScalarParser.exactInt(payload["bonus_game_step"] ?? payload["next_step"]) ?? 1
            let earned = payload["bonus_game_earned"] ?? payload["current_reward"]
            if let items = payload["items"] as? [[String: Any]], items.contains(where: { ($0["action"] as? String) == "coin_front" }) {
                return "\(step)단계입니다. 동전의 앞면 또는 뒷면을 선택하세요."
            }
            if step == 2 || step == 3 { return "성공!! \(marble(earned)) 보상 확정\n계속 도전하시겠습니까?" }
            let cost = WireScalarParser.exactInt(payload["cost"]) ?? 0
            return cost > 0 ? "보너스 게임에 도전하시겠습니까? 도전비 \(marble(cost))" : "보너스 게임에 도전하시겠습니까?"
        case "fortune_card_hold_choice": return "보관할 카드를 선택하세요."
        case "start_cell_build_confirm": return "건설을 진행하시겠습니까?"
        case "start_cell_build_selection": return "건설할 도시를 선택한 뒤 건물을 선택하세요."
        case "defense": return "방어 카드를 사용하시겠습니까?"
        default: return interactionType == "acknowledge" ? "" : "선택해 주세요."
        }
    }

    private static func itemLabel(_ item: [String: Any]) -> String {
        if let label = optionalString(item["label"]) { return appendDisabled(label, item) }
        if let action = optionalString(item["action"] ?? item["id"]) {
            let mapped = [
                "confirm": "확인", "cancel": "취소", "challenge": "도전", "stop": "그만하기",
                "coin_front": "앞면", "coin_back": "뒷면",
                "villa": "별장", "building": "빌딩", "hotel": "호텔", "landmark": "랜드마크",
            ][action] ?? action
            return appendDisabled(mapped, item)
        }
        if let cityName = optionalString(item["city_name"]) { return appendDisabled(cityName, item) }
        if let id = optionalString(item["id"]) { return appendDisabled(id, item) }
        return "항목"
    }

    private static func appendDisabled(_ text: String, _ item: [String: Any]) -> String {
        (WireScalarParser.exactBool(item["disabled"]) ?? false) ? "\(text), 선택 불가" : text
    }

    private static func itemID(_ item: [String: Any]) -> String? {
        if let value = optionalString(item["id"]) { return value }
        if let value = optionalString(item["action"]) { return value }
        if let cityID = WireScalarParser.exactInt(item["city_id"]) { return String(cityID) }
        return nil
    }

    private static func requiredString(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return value
    }

    private static func optionalString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = WireScalarParser.exactInt(value), value > 0 else { return nil }
        return value
    }
}
