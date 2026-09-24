import Foundation

public enum GameRotorCategory: Int, CaseIterable, Equatable, Sendable {
    case playerInformation
    case monopolyInformation
    case cityStatusInformation
    case unitCostInformation

    public var displayName: String {
        switch self {
        case .playerInformation: return "플레이어 정보"
        case .monopolyInformation: return "독점 정보"
        case .cityStatusInformation: return "도시 상태 정보"
        case .unitCostInformation: return "단위 비용 조회"
        }
    }
}

public enum GameRotorPlayerTarget: Equatable, Sendable {
    case player(Int)
    case unowned
}

public enum GameRotorMonopolyKind: Int, CaseIterable, Equatable, Sendable {
    case achieved
    case endingAlert

    public var displayName: String {
        switch self {
        case .achieved: return "달성된 독점"
        case .endingAlert: return "엔딩 독점 경보"
        }
    }
}

public enum GameRotorCityStatusKind: Int, CaseIterable, Equatable, Sendable {
    case festival
    case olympic
    case activeEffect

    public var displayName: String {
        switch self {
        case .festival: return "축제 도시"
        case .olympic: return "올림픽 개최 도시"
        case .activeEffect: return "효과 발효 중인 도시"
        }
    }
}

public enum GameRotorUnitValueKind: Int, CaseIterable, Equatable, Sendable {
    case buildCost
    case tollValue
    case acquisitionValue
    case sellValue

    public var valueField: String {
        switch self {
        case .buildCost: return "build_cost"
        case .tollValue: return "toll_value"
        case .acquisitionValue: return "acquisition_value"
        case .sellValue: return "sell_value"
        }
    }

    public var displayName: String {
        switch self {
        case .buildCost: return "건설 비용"
        case .tollValue: return "통행료"
        case .acquisitionValue: return "인수 비용"
        case .sellValue: return "매각 대금"
        }
    }
}

public struct GameRotorState: Equatable, Sendable {
    public private(set) var category: GameRotorCategory = .playerInformation
    public private(set) var playerTarget: GameRotorPlayerTarget?
    public private(set) var monopolyKind: GameRotorMonopolyKind = .achieved
    public private(set) var cityStatusKind: GameRotorCityStatusKind = .festival
    public private(set) var unitValueKind: GameRotorUnitValueKind = .buildCost
    public private(set) var unitBuildingType: String?

    public private(set) var ownedCityIndex = -1
    public private(set) var opponentCityIndex = -1
    public private(set) var unownedCityIndex = -1
    public private(set) var achievedMonopolyIndex = -1
    public private(set) var endingMonopolyIndex = -1
    public private(set) var festivalCityIndex = -1
    public private(set) var activeEffectCityIndex = -1

    public init() {}

    public mutating func reset() { self = GameRotorState() }

    @discardableResult
    public mutating func moveCategoryForward() -> GameRotorCategory {
        category = Self.next(category, in: GameRotorCategory.allCases, step: 1)
        return category
    }

    @discardableResult
    public mutating func moveCategoryBackward() -> GameRotorCategory {
        category = Self.next(category, in: GameRotorCategory.allCases, step: -1)
        return category
    }

    public mutating func synchronizePlayers(myPlayerID: Int?, players: [GamePlayerSnapshot]) {
        guard let myPlayerID, players.contains(where: { $0.playerID == myPlayerID }) else {
            playerTarget = nil
            return
        }
        if case .player(let id) = playerTarget, players.contains(where: { $0.playerID == id }) { return }
        if playerTarget == .unowned { return }
        playerTarget = .player(myPlayerID)
    }

    public func playerTargets(myPlayerID: Int?, players: [GamePlayerSnapshot]) -> [GameRotorPlayerTarget] {
        guard let myPlayerID, players.contains(where: { $0.playerID == myPlayerID }) else { return [] }
        let ids = players.map(\.playerID).sorted()
        guard let start = ids.firstIndex(of: myPlayerID) else { return [] }
        let rotated = Array(ids[start...]) + Array(ids[..<start])
        return rotated.map(GameRotorPlayerTarget.player) + [.unowned]
    }

    @discardableResult
    public mutating func movePlayerTarget(
        forward: Bool,
        myPlayerID: Int?,
        players: [GamePlayerSnapshot]
    ) -> GameRotorPlayerTarget? {
        let targets = playerTargets(myPlayerID: myPlayerID, players: players)
        guard !targets.isEmpty else { playerTarget = nil; return nil }
        let current = playerTarget.flatMap { targets.firstIndex(of: $0) } ?? 0
        let next = Self.normalized(current + (forward ? 1 : -1), count: targets.count)
        let nextTarget = targets[next]
        if case .player(let playerID) = nextTarget, playerID != myPlayerID {
            // PC판 T 대상 변경 시 V 순환 인덱스를 초기화하는 계약을 모바일의
            // 플레이어 로터 대상 변경에도 그대로 적용한다.
            opponentCityIndex = -1
        }
        playerTarget = nextTarget
        return playerTarget
    }

    @discardableResult
    public mutating func moveMonopolyKind(forward: Bool) -> GameRotorMonopolyKind {
        monopolyKind = Self.next(monopolyKind, in: GameRotorMonopolyKind.allCases, step: forward ? 1 : -1)
        return monopolyKind
    }

    @discardableResult
    public mutating func moveCityStatusKind(forward: Bool) -> GameRotorCityStatusKind {
        cityStatusKind = Self.next(cityStatusKind, in: GameRotorCityStatusKind.allCases, step: forward ? 1 : -1)
        return cityStatusKind
    }

    @discardableResult
    public mutating func moveUnitBuildingType(forward: Bool, availableTypes: [String]) -> String? {
        guard !availableTypes.isEmpty else { unitBuildingType = nil; return nil }
        let current = unitBuildingType.flatMap { availableTypes.firstIndex(of: $0) } ?? 0
        let next = Self.normalized(current + (forward ? 1 : -1), count: availableTypes.count)
        unitBuildingType = availableTypes[next]
        return unitBuildingType
    }

    public mutating func currentUnitBuildingType(availableTypes: [String]) -> String? {
        guard !availableTypes.isEmpty else { unitBuildingType = nil; return nil }
        if let unitBuildingType, availableTypes.contains(unitBuildingType) { return unitBuildingType }
        unitBuildingType = availableTypes[0]
        return unitBuildingType
    }

    @discardableResult
    public mutating func moveUnitValueKind(forward: Bool) -> GameRotorUnitValueKind {
        // 첫 상세 이동은 기본값(건설 비용)을 그대로 조회한다. 이후부터 순환한다.
        // 역방향 첫 이동은 마지막 항목에서 시작한다.
        if unitValueTraversalStarted {
            unitValueKind = Self.next(unitValueKind, in: GameRotorUnitValueKind.allCases, step: forward ? 1 : -1)
        } else {
            unitValueTraversalStarted = true
            if !forward { unitValueKind = .sellValue }
        }
        return unitValueKind
    }

    public mutating func resetUnitBuildingSelection() {
        unitBuildingType = nil
        unitValueKind = .buildCost
        unitValueTraversalStarted = false
    }

    public mutating func nextOwnedCityIndex(forward: Bool) -> Int {
        ownedCityIndex += forward ? 1 : -1
        return ownedCityIndex
    }

    public mutating func nextOpponentCityIndex(forward: Bool) -> Int {
        opponentCityIndex += forward ? 1 : -1
        return opponentCityIndex
    }

    public mutating func nextUnownedCityIndex(forward: Bool) -> Int {
        unownedCityIndex += forward ? 1 : -1
        return unownedCityIndex
    }

    public mutating func updateFilteredCityIndex(filter: String, correctedIndex: Int) {
        switch filter {
        case "owned": ownedCityIndex = correctedIndex
        case "opponent": opponentCityIndex = correctedIndex
        case "unowned": unownedCityIndex = correctedIndex
        default: break
        }
    }

    public mutating func nextMonopolyItemIndex(kind: GameRotorMonopolyKind, forward: Bool, count: Int) -> Int {
        guard count > 0 else {
            if kind == .achieved { achievedMonopolyIndex = -1 } else { endingMonopolyIndex = -1 }
            return 0
        }
        if kind == .achieved {
            achievedMonopolyIndex = Self.normalized(achievedMonopolyIndex + (forward ? 1 : -1), count: count)
            return achievedMonopolyIndex
        }
        endingMonopolyIndex = Self.normalized(endingMonopolyIndex + (forward ? 1 : -1), count: count)
        return endingMonopolyIndex
    }

    public mutating func nextCityStatusIndex(kind: GameRotorCityStatusKind, forward: Bool, count: Int) -> Int {
        guard count > 0 else {
            if kind == .festival { festivalCityIndex = -1 }
            if kind == .activeEffect { activeEffectCityIndex = -1 }
            return 0
        }
        switch kind {
        case .festival:
            festivalCityIndex = Self.normalized(festivalCityIndex + (forward ? 1 : -1), count: count)
            return festivalCityIndex
        case .activeEffect:
            activeEffectCityIndex = Self.normalized(activeEffectCityIndex + (forward ? 1 : -1), count: count)
            return activeEffectCityIndex
        case .olympic:
            return 0
        }
    }

    private var unitValueTraversalStarted = false

    private static func next<T: Equatable>(_ current: T, in values: [T], step: Int) -> T {
        guard let index = values.firstIndex(of: current), !values.isEmpty else { return current }
        return values[normalized(index + step, count: values.count)]
    }

    private static func normalized(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let value = index % count
        return value >= 0 ? value : value + count
    }
}
