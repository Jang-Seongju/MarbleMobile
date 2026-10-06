import Foundation
import XCTest
@testable import MarbleMobileCore

final class RoomManagementTests: XCTestCase {
    private func roomUpdate(participants: [[String: Any]]?) -> [String: Any] {
        var payload: [String: Any] = [
            "type": "room_update", "room_id": 7, "title": "친선전", "max_players": 4,
            "is_private": false, "host_user_id": 1,
            "game_start_authority_user_id": 1, "teams": [],
        ]
        if let participants { payload["participants"] = participants }
        return payload
    }

    func testAuthoritativeParticipantsIncludeMembersWithoutTeamsInJoinOrder() throws {
        let payload = roomUpdate(participants: [
            ["user_id": 1, "nickname": "방장", "connection_status": "connected"],
            ["user_id": 2, "nickname": "참가자", "connection_status": "recovering"],
        ])
        let snapshot = try RoomUpdateParser.parse(payload)
        XCTAssertEqual(snapshot.participants?.map(\.userID), [1, 2])
        XCTAssertEqual(snapshot.participants?.map(\.nickname), ["방장", "참가자"])
        XCTAssertEqual(snapshot.participants?.last?.connectionStatus, .recovering)
        XCTAssertTrue(snapshot.teams.isEmpty)
    }

    func testMalformedParticipantsDoNotReplaceRoomState() throws {
        var payload = roomUpdate(participants: [
            ["user_id": 1, "nickname": "방장", "connection_status": "connected"],
            ["user_id": 1, "nickname": "중복", "connection_status": "connected"],
        ])
        XCTAssertThrowsError(try RoomUpdateParser.parse(payload))
        payload["participants"] = [["user_id": 2, "nickname": "참가자", "connection_status": "unknown"]]
        XCTAssertThrowsError(try RoomUpdateParser.parse(payload))
        XCTAssertNil(try RoomUpdateParser.parse(roomUpdate(participants: nil)).participants)
    }

    func testRoomManagementRequestUsesServerRulesAndExactWire() throws {
        XCTAssertThrowsError(try RoomManagementRequest(
            title: "친선전", maxPlayers: 2, isPrivate: false, password: "",
            currentCount: 3, currentlyPrivate: false
        ))
        XCTAssertThrowsError(try RoomManagementRequest(
            title: "친선전", maxPlayers: 4, isPrivate: true, password: "",
            currentCount: 2, currentlyPrivate: false
        ))
        let request = try RoomManagementRequest(
            title: " 새 방 ", maxPlayers: 3, isPrivate: true, password: "",
            currentCount: 2, currentlyPrivate: true
        )
        let message = WireMessages.roomManagementUpdate(request)
        XCTAssertEqual(message["type"] as? String, "room_management_update")
        XCTAssertEqual(message["title"] as? String, "새 방")
        XCTAssertEqual(message["max_players"] as? Int, 3)
        XCTAssertEqual(message["is_private"] as? Bool, true)
        XCTAssertTrue(message["password"] is NSNull)
        XCTAssertEqual(WireMessages.roomKick(targetUserID: 2) as NSDictionary,
                       ["type": "room_kick", "target_user_id": 2] as NSDictionary)
    }
}
