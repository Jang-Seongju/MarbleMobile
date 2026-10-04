import Foundation
import XCTest
@testable import MarbleMobileCore

final class InformationNavigationTests: XCTestCase {
    func testSpectatorParticipationUsesOnlyServerCommandType() {
        XCTAssertEqual(MainMenuDefinition.title(for: .participateRoom), "게임방 참여")
        XCTAssertEqual(
            WireMessages.joinRoomFromSpectator() as NSDictionary,
            ["type": "join_room_from_spectator"] as NSDictionary
        )
    }

    func testSpectatorParticipationValidatesBothServerEventsAgainstRegistration() throws {
        let expected = SpectatorRegistrationSnapshot(roomID: 7, observedUserID: 30, observedUserNickname: "돌")
        XCTAssertTrue(SpectatorParticipationValidator.acceptsLeft(
            ["type": "spectator_left", "room_id": 7, "observed_user_id": 30], expected: expected
        ))
        XCTAssertFalse(SpectatorParticipationValidator.acceptsLeft(
            ["type": "spectator_left", "room_id": 7, "observed_user_id": 31], expected: expected
        ))
        let joined: [String: Any] = [
            "type": "room_joined", "room_id": 7, "title": "친선전", "max_players": 4,
            "is_private": false, "host_user_id": 1, "game_start_authority_user_id": 1
        ]
        XCTAssertEqual(try SpectatorParticipationValidator.joined(joined, expected: expected).roomID, 7)
        var wrongRoom = joined
        wrongRoom["room_id"] = 8
        XCTAssertThrowsError(try SpectatorParticipationValidator.joined(wrongRoom, expected: expected))
    }

    func testSpectatorParticipationIsUnavailableDuringGameAndUntilRoomReturnsToWaiting() {
        XCTAssertFalse(SpectatorParticipationAvailability.canRequest(gameIsActive: true, roomStatus: "waiting"))
        XCTAssertFalse(SpectatorParticipationAvailability.canRequest(gameIsActive: false, roomStatus: "playing"))
        XCTAssertFalse(SpectatorParticipationAvailability.canRequest(gameIsActive: false, roomStatus: nil))
        XCTAssertTrue(SpectatorParticipationAvailability.canRequest(gameIsActive: false, roomStatus: "waiting"))
    }

    func testProfileHeadingsApplyToBothSelfAndOtherProfiles() {
        for account in ["닉네임: 나\n아이디: my-id", "닉네임: 타인"] {
            let content = "사용자 정보\n[계정 정보]\n\(account)\n[현재 상태]\n접속 상태: 접속 중\n[기본 전적]\n[승리 유형]\n[누적 점수]\n[보정 평균]\n[순위 평가]"
            XCTAssertEqual(
                PresentationFormatter.profileLines(content).filter(\.isHeading).map(\.text),
                ["[계정 정보]", "[현재 상태]", "[기본 전적]", "[승리 유형]", "[누적 점수]", "[보정 평균]", "[순위 평가]"]
            )
        }
    }

    func testRankingRowsAreHeadingsAndValuesMatchPCOrder() {
        let payload: [String: Any] = [
            "baseline": ["active_user_count": 1, "baseline_game_count": 2,
                         "baseline_average_marble_score": 3000, "baseline_average_victory_score": 4.0],
            "entries": [["rank": 1, "nickname": "돌", "total_games": 3, "wins": 2,
                         "losses": 1, "win_rate": 66.67, "cumulative_marble": 1234567,
                         "victory_score": 8, "adjusted_average_marble": 6000,
                         "marble_score": 1.5, "adjusted_average_victory_score": 2.0,
                         "ranking_score": 3.5]]
        ]
        let lines = PresentationFormatter.rankingLines(payload)
        XCTAssertEqual(lines.filter(\.isHeading).map(\.text), ["1위: 돌"])
        XCTAssertEqual(lines.map(\.text).filter { $0.hasPrefix("누적 마블:") }, ["누적 마블: 1,234,567"])
        XCTAssertEqual(lines.last?.text, "순위 평가 점수: 3.500000")
    }

    func testRecordGroupsAreHeadingsEvenWhenEmpty() {
        let payload: [String: Any] = ["groups": [
            ["participant_count": 4, "entries": [["rank": 1, "nickname": "돌", "marble_delta": 2345,
                "victory_type": "ending_monopoly", "ending_monopoly_types": ["line"],
                "finished_at": "2026-10-03T12:00:00+09:00"]]]
        ]]
        let lines = PresentationFormatter.gameRecordLines(payload)
        XCTAssertEqual(lines.filter(\.isHeading).map(\.text),
                       ["[4인 게임 기록]", "[3인 게임 기록]", "[2인 게임 기록]"])
        XCTAssertTrue(lines.map(\.text).contains("획득 마블: 2,345마블"))
        XCTAssertTrue(lines.map(\.text).contains("엔딩독점 유형: 라인독점"))
        XCTAssertFalse(lines.first { $0.text == "1위" }!.isHeading)
    }
}
