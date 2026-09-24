import Foundation

// MARK: - Central information DTOs

public struct InformationInfo: Equatable, Sendable {
    public let playerID: Int?
    public let nickname: String?
    public let teamName: String?

    public let marble: Int?
    public let isStranded: Bool?
    public let isBankrupt: Bool?
    public let ownedCityCount: Int?
    public let connectionStatus: String?

    public let cellName: String?

    public let cityID: Int?
    public let cityName: String?
    public let cityType: String?

    public let ownerID: Int?
    public let ownerNickname: String?
    public let groupName: String?

    public let buildings: [String]
    public let buildingType: String?

    public let cityEffectTypes: [String]

    public let isColorMonopoly: Bool?
    public let groupNames: [String]
    public let isFestival: Bool?

    public let hasOlympic: Bool?
    public let olympicCount: Int?

    public let buildCost: Int?
    public let tollValue: Int?
    public let acquisitionValue: Int?
    public let sellValue: Int?

    public let costType: String?
    public let amount: Int?
    public let reason: String?

    public let cityDescription: String?

    public let heldCardID: String?
    public let heldCardName: String?
    public let heldCardDescription: String?

    public let endingMonopolyType: String?
    public let endingMonopolyTypes: [String]
    public let lineType: String?

    public let cityIDs: [Int]
    public let cityNames: [String]

    public init(
        playerID: Int? = nil,
        nickname: String? = nil,
        teamName: String? = nil,
        marble: Int? = nil,
        isStranded: Bool? = nil,
        isBankrupt: Bool? = nil,
        ownedCityCount: Int? = nil,
        connectionStatus: String? = nil,
        cellName: String? = nil,
        cityID: Int? = nil,
        cityName: String? = nil,
        cityType: String? = nil,
        ownerID: Int? = nil,
        ownerNickname: String? = nil,
        groupName: String? = nil,
        buildings: [String] = [],
        buildingType: String? = nil,
        cityEffectTypes: [String] = [],
        isColorMonopoly: Bool? = nil,
        groupNames: [String] = [],
        isFestival: Bool? = nil,
        hasOlympic: Bool? = nil,
        olympicCount: Int? = nil,
        buildCost: Int? = nil,
        tollValue: Int? = nil,
        acquisitionValue: Int? = nil,
        sellValue: Int? = nil,
        costType: String? = nil,
        amount: Int? = nil,
        reason: String? = nil,
        cityDescription: String? = nil,
        heldCardID: String? = nil,
        heldCardName: String? = nil,
        heldCardDescription: String? = nil,
        endingMonopolyType: String? = nil,
        endingMonopolyTypes: [String] = [],
        lineType: String? = nil,
        cityIDs: [Int] = [],
        cityNames: [String] = []
    ) {
        self.playerID = playerID
        self.nickname = nickname
        self.teamName = teamName
        self.marble = marble
        self.isStranded = isStranded
        self.isBankrupt = isBankrupt
        self.ownedCityCount = ownedCityCount
        self.connectionStatus = connectionStatus
        self.cellName = cellName
        self.cityID = cityID
        self.cityName = cityName
        self.cityType = cityType
        self.ownerID = ownerID
        self.ownerNickname = ownerNickname
        self.groupName = groupName
        self.buildings = buildings
        self.buildingType = buildingType
        self.cityEffectTypes = cityEffectTypes
        self.isColorMonopoly = isColorMonopoly
        self.groupNames = groupNames
        self.isFestival = isFestival
        self.hasOlympic = hasOlympic
        self.olympicCount = olympicCount
        self.buildCost = buildCost
        self.tollValue = tollValue
        self.acquisitionValue = acquisitionValue
        self.sellValue = sellValue
        self.costType = costType
        self.amount = amount
        self.reason = reason
        self.cityDescription = cityDescription
        self.heldCardID = heldCardID
        self.heldCardName = heldCardName
        self.heldCardDescription = heldCardDescription
        self.endingMonopolyType = endingMonopolyType
        self.endingMonopolyTypes = endingMonopolyTypes
        self.lineType = lineType
        self.cityIDs = cityIDs
        self.cityNames = cityNames
    }
}

public struct InformationResult: Equatable, Sendable {
    public let info: InformationInfo?
    public let items: [InformationInfo]
    public let emptyReason: String?
    public let subjectNickname: String?
    public let index: Int?
    public let totalCount: Int?

    public init(
        info: InformationInfo? = nil,
        items: [InformationInfo] = [],
        emptyReason: String? = nil,
        subjectNickname: String? = nil,
        index: Int? = nil,
        totalCount: Int? = nil
    ) {
        self.info = info
        self.items = items
        self.emptyReason = emptyReason
        self.subjectNickname = subjectNickname
        self.index = index
        self.totalCount = totalCount
    }
}

public enum InformationParser {
    public static func info(_ data: Any?) -> InformationInfo? {
        guard let data = data as? [String: Any] else { return nil }
        return InformationInfo(
            playerID: optionalInt(data["player_id"]),
            nickname: optionalString(data["nickname"]),
            teamName: optionalString(data["team_name"]),
            marble: optionalInt(data["marble"]),
            isStranded: optionalBool(data["is_stranded"]),
            isBankrupt: optionalBool(data["is_bankrupt"]),
            ownedCityCount: optionalInt(data["owned_city_count"]),
            connectionStatus: optionalString(data["connection_status"]),
            cellName: optionalString(data["cell_name"]),
            cityID: optionalInt(data["city_id"]),
            cityName: optionalString(data["city_name"]),
            cityType: optionalString(data["city_type"]),
            ownerID: optionalInt(data["owner_id"]),
            ownerNickname: optionalString(data["owner_nickname"]),
            groupName: optionalString(data["group_name"]),
            buildings: stringList(data["buildings"]),
            buildingType: optionalString(data["building_type"]),
            cityEffectTypes: stringList(data["city_effect_types"]),
            isColorMonopoly: optionalBool(data["is_color_monopoly"]),
            groupNames: stringList(data["group_names"]),
            isFestival: optionalBool(data["is_festival"]),
            hasOlympic: optionalBool(data["has_olympic"]),
            olympicCount: optionalInt(data["olympic_count"]),
            buildCost: optionalInt(data["build_cost"]),
            tollValue: optionalInt(data["toll_value"]),
            acquisitionValue: optionalInt(data["acquisition_value"]),
            sellValue: optionalInt(data["sell_value"]),
            costType: optionalString(data["cost_type"]),
            amount: optionalInt(data["amount"]),
            reason: optionalString(data["reason"]),
            cityDescription: optionalString(data["city_description"]),
            heldCardID: optionalString(data["held_card_id"]),
            heldCardName: optionalString(data["held_card_name"]),
            heldCardDescription: optionalString(data["held_card_description"]),
            endingMonopolyType: optionalString(data["ending_monopoly_type"]),
            endingMonopolyTypes: stringList(data["ending_monopoly_types"]),
            lineType: optionalString(data["line_type"]),
            cityIDs: intList(data["city_ids"]),
            cityNames: stringList(data["city_names"])
        )
    }

    public static func result(_ data: Any?) -> InformationResult? {
        guard let data = data as? [String: Any] else { return nil }
        let parsedInfo = info(data["info"])
        let rawItems = data["items"] as? [Any] ?? []
        let parsedItems = rawItems.compactMap(info)
        return InformationResult(
            info: parsedInfo,
            items: parsedItems,
            emptyReason: optionalString(data["empty_reason"]),
            subjectNickname: optionalString(data["subject_nickname"]),
            index: optionalInt(data["index"]),
            totalCount: optionalInt(data["total_count"])
        )
    }

    private static func optionalInt(_ value: Any?) -> Int? {
        guard value != nil, !(value is NSNull) else { return nil }
        return WireScalarParser.exactInt(value)
    }

    private static func optionalBool(_ value: Any?) -> Bool? {
        guard value != nil, !(value is NSNull) else { return nil }
        return WireScalarParser.exactBool(value)
    }

    private static func optionalString(_ value: Any?) -> String? {
        guard value != nil, !(value is NSNull), let value = value as? String else { return nil }
        return value
    }

    private static func stringList(_ value: Any?) -> [String] {
        guard let raw = value as? [Any] else { return [] }
        return raw.compactMap { $0 as? String }
    }

    private static func intList(_ value: Any?) -> [Int] {
        guard let raw = value as? [Any] else { return [] }
        return raw.compactMap(WireScalarParser.exactInt)
    }
}

// MARK: - Display specs

public enum InformationField: String, Sendable {
    case playerID, nickname, teamName
    case marble, isStranded, isBankrupt, ownedCityCount, connectionStatus
    case cellName
    case cityID, cityName, cityType
    case ownerID, ownerNickname, groupName
    case buildings, buildingType
    case cityEffectTypes
    case isColorMonopoly, groupNames, isFestival
    case hasOlympic, olympicCount
    case buildCost, tollValue, acquisitionValue, sellValue
    case costType, amount, reason
    case cityDescription
    case heldCardID, heldCardName, heldCardDescription
    case endingMonopolyType, endingMonopolyTypes, lineType
    case cityIDs, cityNames
}

public struct InformationDisplaySpec: Equatable, Sendable {
    public enum ResultMode: String, Sendable { case single, list }
    public let name: String
    public let fields: [InformationField]
    public let resultMode: ResultMode

    public init(name: String, fields: [InformationField], resultMode: ResultMode = .single) {
        self.name = name
        self.fields = fields
        self.resultMode = resultMode
    }
}

public enum InformationDisplaySpecs {
    public static let selfPlayerInfo = InformationDisplaySpec(
        name: "self_player_info",
        fields: [.connectionStatus, .marble, .ownedCityCount, .groupNames, .endingMonopolyTypes, .lineType, .hasOlympic, .olympicCount, .heldCardName, .isBankrupt]
    )
    public static let opponentPlayerInfo = InformationDisplaySpec(
        name: "opponent_player_info",
        fields: [.nickname, .connectionStatus, .marble, .ownedCityCount, .groupNames, .endingMonopolyTypes, .lineType, .hasOlympic, .olympicCount, .isBankrupt]
    )
    public static let playerPosition = InformationDisplaySpec(
        name: "player_position", fields: [.playerID, .nickname, .cityID, .cityName, .cellName], resultMode: .list
    )
    public static let heldCard = InformationDisplaySpec(
        name: "held_card", fields: [.heldCardID, .heldCardName, .heldCardDescription]
    )
    public static let cityDescription = InformationDisplaySpec(
        name: "city_description", fields: [.cityID, .cityName, .cityDescription]
    )
    public static let cityInfo = InformationDisplaySpec(
        name: "city_info",
        fields: [.cityID, .cityName, .buildings, .groupName, .isColorMonopoly, .hasOlympic, .olympicCount, .cityEffectTypes, .isFestival, .ownerID, .ownerNickname]
    )
    public static let ownedCityInfo = InformationDisplaySpec(
        name: "owned_city_info",
        fields: [.cityID, .cityName, .buildings, .groupName, .isColorMonopoly, .hasOlympic, .olympicCount, .cityEffectTypes, .isFestival]
    )
    public static let cityTollCost = InformationDisplaySpec(name: "city_toll_cost", fields: [.cityID, .cityName, .amount, .reason])
    public static let cityAcquisitionCost = InformationDisplaySpec(name: "city_acquisition_cost", fields: [.cityID, .cityName, .amount, .reason])
    public static let citySaleCost = InformationDisplaySpec(name: "city_sale_cost", fields: [.cityID, .cityName, .amount, .reason])
    public static let buildCost = InformationDisplaySpec(name: "build_cost", fields: [.cityID, .cityName, .cityType, .buildingType, .buildCost])
    public static let buildingTollValue = InformationDisplaySpec(name: "building_toll_value", fields: [.cityID, .cityName, .cityType, .buildingType, .tollValue])
    public static let buildingAcquisitionValue = InformationDisplaySpec(name: "building_acquisition_value", fields: [.cityID, .cityName, .cityType, .buildingType, .acquisitionValue])
    public static let buildingSellValue = InformationDisplaySpec(name: "building_sell_value", fields: [.cityID, .cityName, .cityType, .buildingType, .sellValue])
    public static let activeCityEffects = InformationDisplaySpec(name: "active_city_effects", fields: [.cityID, .cityName, .cityEffectTypes], resultMode: .list)
    public static let achievedMonopolyStatus = InformationDisplaySpec(name: "achieved_monopoly_status", fields: [.playerID, .nickname, .groupNames, .endingMonopolyType, .lineType], resultMode: .list)
    public static let endingMonopolyAlert = InformationDisplaySpec(name: "ending_monopoly_alert", fields: [.nickname, .endingMonopolyType, .lineType, .cityNames], resultMode: .list)
    public static let festivalCityList = InformationDisplaySpec(name: "festival_city_list", fields: [.cityID, .cityName], resultMode: .list)
    public static let currentTurnPlayer = InformationDisplaySpec(name: "current_turn_player", fields: [.playerID, .nickname])
    public static let olympicCity = InformationDisplaySpec(name: "olympic_city", fields: [.cityID, .cityName, .ownerID, .ownerNickname, .hasOlympic, .olympicCount])
    public static let buildingStatus = InformationDisplaySpec(name: "building_status", fields: [.buildings])
}

// MARK: - Presentation

public enum InformationCityPresenter {
    public static func format(
        _ info: InformationInfo,
        spec: InformationDisplaySpec = InformationDisplaySpecs.cityInfo,
        myPlayerID: Int? = nil
    ) -> String {
        let fields = spec.fields
        let olympicCount = fields.contains(.olympicCount) ? info.olympicCount : nil
        var parts: [String] = []
        for field in fields {
            let text: String?
            switch field {
            case .cityID:
                text = nil
            case .cityName:
                text = info.cityName
            case .buildings:
                text = info.buildings.isEmpty ? nil : info.buildings.joined(separator: ", ")
            case .groupName:
                text = info.groupName
            case .isColorMonopoly:
                text = info.isColorMonopoly == true ? "독점" : nil
            case .hasOlympic:
                if info.hasOlympic == true, let olympicCount, olympicCount > 0 {
                    text = "올림픽 \(olympicCount)회"
                } else {
                    text = nil
                }
            case .olympicCount:
                text = nil
            case .cityEffectTypes:
                let labels = info.cityEffectTypes.compactMap(cityEffectLabel)
                text = labels.isEmpty ? nil : labels.joined(separator: ", ")
            case .isFestival:
                text = info.isFestival == true ? "축제" : nil
            case .ownerID:
                if info.ownerID == nil {
                    text = "미소유"
                } else if let myPlayerID, info.ownerID == myPlayerID {
                    text = "내 소유"
                } else if let nickname = info.ownerNickname, !nickname.isEmpty {
                    text = "\(nickname) 소유"
                } else {
                    text = "소유"
                }
            case .ownerNickname:
                text = nil
            default:
                text = nil
            }
            if let text, !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: ", ")
    }

    private static func cityEffectLabel(_ effectType: String) -> String? {
        let value = effectType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        switch value {
        case "yellow_dust": return "황사"
        case "blackout": return "도시 정전"
        case "plague": return "전염병"
        default: return value
        }
    }
}

public enum InformationResultPresenter {
    public static func formatResponse(
        queryType: String,
        payload: [String: Any],
        myPlayerID: Int?,
        index: Int? = nil,
        reverse: Bool = false,
        asBuildingStatus: Bool = false
    ) -> String? {
        guard let result = InformationParser.result(payload["result"]) else { return nil }
        return format(
            queryType: queryType,
            result: result,
            myPlayerID: myPlayerID,
            valueField: payload["value_field"] as? String,
            filterType: payload["filter"] as? String,
            index: index,
            reverse: reverse,
            asBuildingStatus: asBuildingStatus
        )
    }

    public static func format(
        queryType: String,
        result: InformationResult,
        myPlayerID: Int? = nil,
        valueField: String? = nil,
        filterType: String? = nil,
        index: Int? = nil,
        reverse: Bool = false,
        asBuildingStatus: Bool = false
    ) -> String? {
        switch queryType {
        case "held_card":
            return heldCard(result)
        case "player_info":
            return playerInfo(result, myPlayerID: myPlayerID)
        case "city_description":
            return cityDescription(result)
        case "city_cost":
            return cityCost(result)
        case "building_value_info":
            return buildingValue(result, valueField: valueField)
        case "active_city_effects":
            return activeCityEffects(result, reverse: reverse)
        case "ending_monopoly_alerts":
            return endingMonopolyAlerts(result, index: index)
        case "achieved_monopoly_status":
            return achievedMonopolyStatus(result, index: index)
        case "festival_city_list":
            return festivalCityList(result)
        case "player_positions":
            return playerPosition(result, index: index)
        case "current_turn_player":
            return currentTurnPlayer(result)
        case "olympic_city":
            return olympicCity(result)
        case "city_info":
            if asBuildingStatus { return buildingStatus(result) }
            return cityInfo(result, myPlayerID: myPlayerID, filterType: filterType)
        default:
            return nil
        }
    }

    public static func buildingType(_ value: String?) -> String {
        value ?? "건물 정보 없음"
    }

    private static func heldCard(_ result: InformationResult) -> String? {
        guard let info = result.info, let cardID = info.heldCardID, !cardID.isEmpty else { return "보관 중인 카드 없음" }
        let name = info.heldCardName ?? ""
        if let description = info.heldCardDescription, !description.isEmpty { return "\(name), \(description)" }
        return name.isEmpty ? nil : name
    }

    private static func playerInfo(_ result: InformationResult, myPlayerID: Int?) -> String {
        guard let info = result.info else { return "플레이어 정보를 찾을 수 없습니다." }
        let isSelf = myPlayerID != nil && info.playerID == myPlayerID
        let spec = isSelf ? InformationDisplaySpecs.selfPlayerInfo : InformationDisplaySpecs.opponentPlayerInfo
        var parts: [String] = []
        for field in spec.fields {
            switch field {
            case .nickname:
                if let value = info.nickname, !value.isEmpty { parts.append(value) }
            case .connectionStatus:
                continue
            case .marble:
                parts.append(marble(info.marble ?? 0))
            case .ownedCityCount:
                parts.append("소유 도시 \(info.ownedCityCount ?? 0)곳")
            case .groupNames:
                parts.append(contentsOf: achievedMonopolyParts(info))
            case .endingMonopolyTypes, .lineType:
                continue
            case .hasOlympic:
                if info.hasOlympic == true, let count = info.olympicCount, count > 0 { parts.append("올림픽 \(count)회") }
            case .olympicCount:
                continue
            case .heldCardName:
                if let card = info.heldCardName, !card.isEmpty { parts.append("보관 카드 \(card)") }
            case .isBankrupt:
                if info.isBankrupt == true { parts.append("파산") }
            default:
                continue
            }
        }
        if info.connectionStatus == "recovering" || info.connectionStatus == "disconnected" { parts.append("접속 끊김") }
        return parts.isEmpty ? "플레이어 정보를 찾을 수 없습니다." : parts.joined(separator: " ")
    }

    private static func cityDescription(_ result: InformationResult) -> String {
        guard let info = result.info else { return "도시가 아닙니다." }
        return info.cityDescription ?? "설명 없음"
    }

    private static func cityCost(_ result: InformationResult) -> String {
        guard let info = result.info, let type = info.costType else { return "비용 정보를 찾을 수 없습니다." }
        let city = info.cityName ?? ""
        switch type {
        case "toll": return "\(city) 통행료 \(marble(info.amount))"
        case "acquisition": return info.amount == nil ? "\(city) 인수불가" : "\(city) 인수 비용 \(marble(info.amount))"
        case "sale": return "\(city) 매각 대금 \(marble(info.amount))"
        default: return "비용 정보를 찾을 수 없습니다."
        }
    }

    private static func buildingValue(_ result: InformationResult, valueField: String?) -> String {
        guard let info = result.info else { return "건물 정보를 찾을 수 없습니다." }
        switch valueField {
        case "build_cost": return info.buildCost == nil ? "건설 비용 없음" : "건설 비용 \(marble(info.buildCost))"
        case "toll_value": return "통행료 \(marble(info.tollValue))"
        case "acquisition_value": return info.acquisitionValue == nil ? "인수불가" : "인수 비용 \(marble(info.acquisitionValue))"
        case "sell_value": return info.sellValue == nil ? "매각 대금 없음" : "매각 대금 \(marble(info.sellValue))"
        default: return "건물 정보를 찾을 수 없습니다."
        }
    }

    private static func activeCityEffects(_ result: InformationResult, reverse: Bool) -> String? {
        guard !result.items.isEmpty else { return "발효 중인 효과 없음" }
        let items = reverse ? Array(result.items.reversed()) : result.items
        let parts = items.compactMap { info -> String? in
            let effects = info.cityEffectTypes.compactMap { effect -> String? in
                switch effect {
                case "yellow_dust": return "황사"
                case "blackout": return "도시 정전"
                case "plague": return "전염병"
                default: return effect.isEmpty ? nil : effect
                }
            }
            let values = [info.cityName ?? ""] + effects
            let text = values.filter { !$0.isEmpty }.joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func endingMonopolyAlerts(_ result: InformationResult, index: Int?) -> String {
        guard !result.items.isEmpty else { return "엔딩독점 경보 없음" }
        let info = result.items[normalized(index ?? 0, count: result.items.count)]
        let nickname = info.nickname ?? ""
        let label: String
        switch info.endingMonopolyType {
        case "triple_color": label = "트리플 컬러독점"
        case "line": label = info.lineType.map { "라인독점 \($0)" } ?? "라인독점"
        case "tourist": label = "관광지독점"
        default: label = "엔딩독점"
        }
        let cities = info.cityNames.joined(separator: ", ")
        return cities.isEmpty ? "\(nickname): \(label) 경보" : "\(nickname): \(label) 경보: \(cities)"
    }

    private static func achievedMonopolyStatus(_ result: InformationResult, index: Int?) -> String {
        guard !result.items.isEmpty else { return "달성된 독점 없음" }
        let info = result.items[normalized(index ?? 0, count: result.items.count)]
        let parts = achievedMonopolyParts(info)
        guard let first = parts.first else { return "달성된 독점 없음" }
        return "\(info.nickname ?? ""): \(first)"
    }

    private static func achievedMonopolyParts(_ info: InformationInfo) -> [String] {
        var endingTypes = info.endingMonopolyTypes
        if let type = info.endingMonopolyType, !endingTypes.contains(type) { endingTypes.append(type) }
        var parts: [String] = []
        if !info.groupNames.isEmpty {
            let groups = info.groupNames.joined(separator: ", ")
            parts.append(endingTypes.contains("triple_color") ? "\(groups), 트리플컬러독점" : "\(groups) 독점")
        }
        if endingTypes.contains("line") { parts.append(info.lineType.map { "라인독점 \($0)" } ?? "라인독점") }
        if endingTypes.contains("tourist") { parts.append("관광지독점") }
        return parts
    }

    private static func festivalCityList(_ result: InformationResult) -> String {
        let names = result.items.compactMap { $0.cityName }.filter { !$0.isEmpty }
        return names.isEmpty ? "축제도시 없음" : "축제도시: \(names.joined(separator: ", "))"
    }

    private static func playerPosition(_ result: InformationResult, index: Int?) -> String {
        guard !result.items.isEmpty else { return "플레이어 위치 정보 없음" }
        let info = result.items[normalized(index ?? 0, count: result.items.count)]
        return "\(info.nickname ?? "") \(info.cellName ?? "")"
    }

    private static func currentTurnPlayer(_ result: InformationResult) -> String {
        guard let info = result.info else { return "현재 턴 플레이어 없음" }
        return info.nickname ?? "현재 턴 플레이어 없음"
    }

    private static func olympicCity(_ result: InformationResult) -> String {
        guard let info = result.info,
              info.hasOlympic == true,
              let count = info.olympicCount,
              count > 0
        else { return "올림픽 개최지 없음" }
        return "\(info.cityName ?? "") \(info.ownerNickname ?? "?") 올림픽 \(count)회"
    }

    private static func cityInfo(_ result: InformationResult, myPlayerID: Int?, filterType: String?) -> String {
        guard let info = result.info else {
            switch result.emptyReason {
            case "city_id_missing": return "city_id 없음"
            case "opponent_unavailable": return "상대 플레이어 없음"
            case "no_unowned_cities": return "미소유 도시 없음"
            case "no_owned_cities": return "소유한 도시 없음"
            case "no_opponent_cities":
                if let nickname = result.subjectNickname, !nickname.isEmpty { return "\(nickname) 소유 도시 없음" }
                return "상대 소유 도시 없음"
            default:
                if filterType == "unowned" { return "미소유 도시 없음" }
                if filterType == "owned" { return "소유한 도시 없음" }
                return "도시 정보를 찾을 수 없습니다."
            }
        }
        return InformationCityPresenter.format(info, spec: InformationDisplaySpecs.cityInfo, myPlayerID: myPlayerID)
    }

    private static func buildingStatus(_ result: InformationResult) -> String {
        guard let info = result.info else { return "도시 정보를 찾을 수 없습니다." }
        return info.buildings.isEmpty ? "건물 없음" : info.buildings.joined(separator: ", ")
    }

    private static func marble(_ value: Int?) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return "\(formatter.string(from: NSNumber(value: value ?? 0)) ?? String(value ?? 0))마블"
    }

    private static func normalized(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let value = index % count
        return value >= 0 ? value : value + count
    }
}

// MARK: - Static information catalog

public struct StaticInformationCatalogSnapshot: Equatable, Sendable {
    private let descriptions: [Int: InformationInfo]
    private let buildingValues: [Int: [String: InformationInfo]]
    private let buildingTypeOrders: [Int: [String]]

    public init(result: InformationResult) throws {
        guard !result.items.isEmpty else { throw StaticInformationCatalogError.invalidInformation }
        if let count = result.totalCount, count != result.items.count { throw StaticInformationCatalogError.invalidInformation }

        var descriptions: [Int: InformationInfo] = [:]
        var buildingValues: [Int: [String: InformationInfo]] = [:]
        var buildingTypeOrders: [Int: [String]] = [:]

        for info in result.items {
            guard let cityID = info.cityID else { throw StaticInformationCatalogError.invalidInformation }
            if info.cityDescription != nil {
                guard descriptions[cityID] == nil else { throw StaticInformationCatalogError.invalidInformation }
                descriptions[cityID] = info
            } else if let buildingType = info.buildingType {
                guard buildingValues[cityID]?[buildingType] == nil else { throw StaticInformationCatalogError.invalidInformation }
                buildingValues[cityID, default: [:]][buildingType] = info
                buildingTypeOrders[cityID, default: []].append(buildingType)
            } else {
                throw StaticInformationCatalogError.invalidInformation
            }
        }
        guard !descriptions.isEmpty, !buildingValues.isEmpty else { throw StaticInformationCatalogError.invalidInformation }
        self.descriptions = descriptions
        self.buildingValues = buildingValues
        self.buildingTypeOrders = buildingTypeOrders
    }

    public func cityDescription(cityID: Int) -> InformationInfo? { descriptions[cityID] }
    public func buildingValue(cityID: Int, buildingType: String) -> InformationInfo? { buildingValues[cityID]?[buildingType] }
    public func buildingTypes(cityID: Int) -> [String] { buildingTypeOrders[cityID] ?? [] }
}

public enum StaticInformationCatalogError: Error, Equatable, Sendable { case invalidInformation }

public enum StaticInformationCatalogParser {
    public static func parse(_ data: Any?) throws -> StaticInformationCatalogSnapshot {
        guard let result = InformationParser.result(data) else { throw StaticInformationCatalogError.invalidInformation }
        return try StaticInformationCatalogSnapshot(result: result)
    }
}
