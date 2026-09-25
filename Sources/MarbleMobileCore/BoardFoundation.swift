import Foundation

public struct BoardCellSnapshot: Identifiable, Equatable, Sendable {
    public let index: Int
    public let name: String
    public let cellType: String
    public let cityID: Int?
    public let cityType: String?
    public let group: String?
    public let basePrice: Int
    public let row: Int
    public let column: Int

    public var id: Int { index }
    public var isCity: Bool { cellType == "CITY" }

    public init(
        index: Int,
        name: String,
        cellType: String,
        cityID: Int?,
        cityType: String?,
        group: String?,
        basePrice: Int,
        row: Int,
        column: Int
    ) {
        self.index = index
        self.name = name
        self.cellType = cellType
        self.cityID = cityID
        self.cityType = cityType
        self.group = group
        self.basePrice = basePrice
        self.row = row
        self.column = column
    }

    /// PC client BoardCell.short_description()과 같은 게임 전 보드 읽기.
    public var shortDescription: String {
        guard isCity, let group, !group.isEmpty else { return name }
        return "\(name), \(group)"
    }
}

public struct BoardCatalogSnapshot: Equatable, Sendable {
    public let cells: [BoardCellSnapshot]

    public init(cells: [BoardCellSnapshot]) {
        self.cells = cells.sorted { $0.index < $1.index }
    }

    public func cell(at index: Int) -> BoardCellSnapshot? {
        cells.first { $0.index == index }
    }

    public func cell(row: Int, column: Int) -> BoardCellSnapshot? {
        cells.first { $0.row == row && $0.column == column }
    }
}

public enum BoardCellsParserError: Error, Equatable, LocalizedError, Sendable {
    case invalidMessage

    public var errorDescription: String? { "보드 정보가 올바르지 않습니다." }
}

public enum BoardCellsParser {
    public static func parse(_ data: [String: Any]) throws -> BoardCatalogSnapshot {
        guard data["type"] as? String == "board_cells",
              let rawCells = data["board_cells"] as? [[String: Any]],
              rawCells.count == 32
        else {
            throw BoardCellsParserError.invalidMessage
        }

        var indexes = Set<Int>()
        var positions = Set<String>()
        var cells: [BoardCellSnapshot] = []
        cells.reserveCapacity(rawCells.count)

        for raw in rawCells {
            guard let index = exactInt(raw["index"]), (1...32).contains(index),
                  indexes.insert(index).inserted,
                  let name = normalizedRequiredString(raw["name"]),
                  let cellType = normalizedRequiredString(raw["cell_type"]),
                  let cityIDResult = optionalPositiveInt(raw["city_id"]),
                  let cityTypeResult = optionalString(raw["city_type"]),
                  let groupResult = optionalString(raw["group"]),
                  let basePrice = exactInt(raw["base_price"]), basePrice >= 0,
                  let row = exactInt(raw["row"]), (0...8).contains(row),
                  let column = exactInt(raw["col"]), (0...8).contains(column),
                  (row == 0 || row == 8 || column == 0 || column == 8),
                  positions.insert("\(row):\(column)").inserted
            else {
                throw BoardCellsParserError.invalidMessage
            }

            cells.append(.init(
                index: index,
                name: name,
                cellType: cellType,
                cityID: cityIDResult.value,
                cityType: cityTypeResult.value,
                group: groupResult.value,
                basePrice: basePrice,
                row: row,
                column: column
            ))
        }

        guard indexes == Set(1...32), positions.count == 32 else {
            throw BoardCellsParserError.invalidMessage
        }
        return BoardCatalogSnapshot(cells: cells)
    }

    private static func exactInt(_ value: Any?) -> Int? {
        WireScalarParser.exactInt(value)
    }

    /// 성공/실패를 Optional 하나로 표현하되 JSON null은 정상적인 nil 값으로 취급한다.
    /// 외부에서는 `(accepted, value)`를 통해 malformed와 null을 구분한다.
    private static func optionalPositiveInt(_ value: Any?) -> (accepted: Bool, value: Int?)? {
        if value == nil || value is NSNull { return (true, nil) }
        guard let parsed = exactInt(value), parsed >= 1 else { return nil }
        return (true, parsed)
    }

    private static func optionalString(_ value: Any?) -> (accepted: Bool, value: String?)? {
        if value == nil || value is NSNull { return (true, nil) }
        guard let string = value as? String,
              string == string.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty
        else { return nil }
        return (true, string)
    }

    private static func normalizedRequiredString(_ value: Any?) -> String? {
        guard let string = value as? String,
              string == string.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty
        else { return nil }
        return string
    }
}

public struct BoardCursorState: Equatable, Sendable {
    public private(set) var index: Int

    public init(index: Int = 1) {
        self.index = (1...32).contains(index) ? index : 1
    }

    @discardableResult
    public mutating func moveNext() -> Int {
        index = index == 32 ? 1 : index + 1
        return index
    }

    @discardableResult
    public mutating func movePrevious() -> Int {
        index = index == 1 ? 32 : index - 1
        return index
    }

    public mutating func jump(to target: Int) {
        guard (1...32).contains(target) else { return }
        index = target
    }

    public mutating func reset() {
        index = 1
    }
}

public enum CityCostQueryKind: String, CaseIterable, Equatable, Sendable {
    case toll
    case acquisition
    case sale

    public var preGameGuide: String {
        switch self {
        case .toll:
            return "w키는 게임 중 현재 도시의 건물과 효과를 반영한 실제 통행료를 확인합니다."
        case .acquisition:
            return "e키는 게임 중 현재 도시 전체의 실제 인수 비용을 확인합니다."
        case .sale:
            return "r키는 게임 중 현재 도시 전체의 실제 매각 대금을 확인합니다."
        }
    }
}

public struct CityCostCycleState: Equatable, Sendable {
    private var selectedIndex: Int?

    public init() {}

    @discardableResult
    public mutating func moveForward() -> CityCostQueryKind {
        let values = CityCostQueryKind.allCases
        let next = selectedIndex.map { ($0 + 1) % values.count } ?? 0
        selectedIndex = next
        return values[next]
    }

    @discardableResult
    public mutating func moveBackward() -> CityCostQueryKind {
        let values = CityCostQueryKind.allCases
        let previous = selectedIndex.map { ($0 - 1 + values.count) % values.count } ?? (values.count - 1)
        selectedIndex = previous
        return values[previous]
    }

    public mutating func reset() {
        selectedIndex = nil
    }
}

public struct BoardBootstrapSnapshot: Equatable, Sendable {
    public let boardCatalog: BoardCatalogSnapshot
    public let staticInformation: StaticInformationCatalogSnapshot

    public init(boardCatalog: BoardCatalogSnapshot, staticInformation: StaticInformationCatalogSnapshot) {
        self.boardCatalog = boardCatalog
        self.staticInformation = staticInformation
    }
}

public enum BoardBootstrapParser {
    public static func parse(_ data: [String: Any]) throws -> BoardBootstrapSnapshot {
        let board = try BoardCellsParser.parse(data)
        guard let rawStatic = data["static_information"] as? [String: Any] else {
            throw BoardCellsParserError.invalidMessage
        }
        let staticInformation: StaticInformationCatalogSnapshot
        do {
            staticInformation = try StaticInformationCatalogParser.parse(rawStatic)
        } catch {
            throw BoardCellsParserError.invalidMessage
        }
        return BoardBootstrapSnapshot(boardCatalog: board, staticInformation: staticInformation)
    }
}
