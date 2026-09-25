import Foundation
import XCTest
@testable import MarbleMobileCore

final class GameRecoveryCoreTests: XCTestCase {
    func testRecoverySnapshotParsesAuthoritativeGameAndPrivateState() throws {
        let snapshot = try GameRecoveryParser.parse(makeRecoverySnapshot())
        XCTAssertEqual(snapshot.recoveryID, "rec-1")
        XCTAssertEqual(snapshot.roomID, 10)
        XCTAssertEqual(snapshot.gameSessionID, "sess-10")
        XCTAssertEqual(snapshot.yourPlayerID, 1)
        XCTAssertEqual(snapshot.gameState.currentPlayerID, 1)
        XCTAssertEqual(snapshot.boardCatalog.cells.count, 32)
        XCTAssertEqual(snapshot.turn.turnGeneration, 7)
        XCTAssertEqual(snapshot.heldCard?.cardID, "salary_booster")
        XCTAssertEqual(snapshot.salaryBoosterCardID, "salary_booster")
        XCTAssertNil(snapshot.islandEscapeReservationType)
    }

    func testRecoverySnapshotRejectsMismatchedPrivatePlayer() {
        var payload = makeRecoverySnapshot()
        var privatePlayer = payload["private_player"] as! [String: Any]
        privatePlayer["player_id"] = 2
        payload["private_player"] = privatePlayer
        XCTAssertThrowsError(try GameRecoveryParser.parse(payload))
    }

    func testRecoveryCompletionTurnLifecycleIsStrict() throws {
        let lifecycle = try RecoveryCompletionParser.turnLifecycle([
            "current_player_id": 1,
            "turn_generation": 9,
            "has_started": false,
            "next_turn_command": "roll_dice",
            "turn_deadline_at": NSNull(),
            "turn_remaining_seconds": NSNull(),
            "human_controlled": true,
        ])
        XCTAssertEqual(lifecycle.currentPlayerID, 1)
        XCTAssertEqual(lifecycle.turnGeneration, 9)
        XCTAssertTrue(lifecycle.humanControlled)

        XCTAssertThrowsError(try RecoveryCompletionParser.turnLifecycle([
            "current_player_id": NSNull(),
            "turn_generation": NSNull(),
            "has_started": false,
            "next_turn_command": "roll_dice",
            "turn_deadline_at": NSNull(),
            "turn_remaining_seconds": NSNull(),
            "human_controlled": false,
        ]))
    }

    func testRecoveryCompletedWireMessage() {
        let message = WireMessages.gameRecoveryCompleted(recoveryID: "rec-7")
        XCTAssertEqual(message["type"] as? String, "game_recovery_completed")
        XCTAssertEqual(message["recovery_id"] as? String, "rec-7")
    }

    func testCornerClassification() throws {
        let board = try BoardCellsParser.parse([
            "type": "board_cells",
            "board_cells": makeBoardCells(),
        ])
        XCTAssertTrue(board.cell(at: 1)?.isCorner == true)
        XCTAssertTrue(board.cell(at: 9)?.isCorner == true)
        XCTAssertFalse(board.cell(at: 2)?.isCorner == true)
    }

    private func makeRecoverySnapshot() -> [String: Any] {
        [
            "type": "game_recovery_snapshot",
            "recovery_id": "rec-1",
            "room": [
                "room_id": 10,
                "title": "테스트방",
                "max_players": 4,
                "is_private": false,
            ],
            "teams": [[
                "id": 1,
                "name": "A팀",
                "members": [[
                    "user_id": 10,
                    "nickname": "철수",
                    "connection_status": "recovering",
                ]],
            ]],
            "game": [
                "game_session_id": "sess-10",
                "status": "playing",
                "your_player_id": 1,
                "players": [[
                    "player_id": 1,
                    "user_id": 10,
                    "nickname": "철수",
                    "team_name": "A팀",
                    "marble": 2_000_000,
                    "position": 1,
                    "lap_count": 0,
                    "is_stranded": false,
                    "is_bankrupt": false,
                    "connection_status": "recovering",
                    "next_turn_command": "roll_dice",
                    "is_ai": false,
                ]],
                "cities": [],
                "current_player_id": 1,
                "turn_order": [1],
                "turn": [
                    "current_player_id": 1,
                    "has_started": false,
                    "consecutive_doubles": 0,
                    "next_turn_command": "roll_dice",
                    "turn_generation": 7,
                    "turn_deadline_at": NSNull(),
                    "turn_remaining_seconds": NSNull(),
                ],
                "festival_city_ids": [],
                "board_cells": makeBoardCells(),
                "static_information": [
                    "items": [
                        ["city_id": 2, "city_description": "서울입니다."],
                        ["city_id": 2, "building_type": "VILLA", "cost": 100_000],
                    ],
                ],
            ],
            "private_player": [
                "player_id": 1,
                "held_card": [
                    "card_id": "salary_booster",
                    "name": "월급 부스터",
                    "description": "월급을 두 배로 받습니다.",
                ],
                "salary_booster_card_id": "salary_booster",
                "turn_preparation": [
                    "selected_active_card_id": NSNull(),
                    "island_escape_reservation_type": NSNull(),
                ],
                "pending_interaction_request": NSNull(),
            ],
        ]
    }

    private func makeBoardCells() -> [[String: Any]] {
        var positions: [(Int, Int)] = []
        for col in stride(from: 8, through: 0, by: -1) { positions.append((8, col)) }
        for row in stride(from: 7, through: 0, by: -1) { positions.append((row, 0)) }
        for col in 1...8 { positions.append((0, col)) }
        for row in 1...7 { positions.append((row, 8)) }
        XCTAssertEqual(positions.count, 32)

        return positions.enumerated().map { offset, position in
            let index = offset + 1
            if index == 1 {
                return [
                    "index": index,
                    "name": "출발",
                    "cell_type": "START",
                    "city_id": NSNull(),
                    "city_type": NSNull(),
                    "group": NSNull(),
                    "base_price": 0,
                    "row": position.0,
                    "col": position.1,
                ]
            }
            return [
                "index": index,
                "name": "도시 \(index)",
                "cell_type": "CITY",
                "city_id": index,
                "city_type": "NORMAL",
                "group": "A",
                "base_price": 100_000,
                "row": position.0,
                "col": position.1,
            ]
        }
    }
}
