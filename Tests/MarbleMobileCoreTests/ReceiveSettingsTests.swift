import Foundation
import XCTest
@testable import MarbleMobileCore

final class ReceiveSettingsTests: XCTestCase {
    func testSocialStateCarriesServerPreferencesAndUpdateUsesExactPolicyValues() {
        let state = WireParser.socialState(from: [
            "friends": [], "incoming_friend_requests": [], "outgoing_friend_requests": [],
            "blocked_users": [],
            "preferences": [
                "message_policy": "friends_only", "note_policy": "none",
                "invitation_policy": "all", "friend_request_policy": "none",
            ],
        ])
        XCTAssertEqual(state.receiveSettings.message, .friendsOnly)
        XCTAssertEqual(state.receiveSettings.note, .none)
        XCTAssertEqual(state.receiveSettings.friendRequest, .none)
        let message = WireMessages.socialPreferencesUpdate(state.receiveSettings)
        XCTAssertEqual(message as NSDictionary, [
            "type": "social_preferences_update",
            "message_policy": "friends_only", "note_policy": "none",
            "invitation_policy": "all", "friend_request_policy": "none",
        ] as NSDictionary)
    }

    func testInvalidPartialPreferenceEventPreservesExistingValues() {
        let initial = ReceiveSettings(message: .friendsOnly, note: .none,
                                      invitation: .none, friendRequest: .none)
        let next = initial.merging(["message_policy": "invalid", "friend_request_policy": "friends_only",
                                    "note_policy": "all"])
        XCTAssertEqual(next.message, .friendsOnly)
        XCTAssertEqual(next.friendRequest, .none)
        XCTAssertEqual(next.note, .all)
        XCTAssertEqual(next.invitation, .none)
    }

    func testMobileFileMenuOmitsDesktopExit() {
        XCTAssertEqual(MainMenuDefinition.sections[0].groups.last, [.leaveRoom])
        XCTAssertFalse(MainMenuDefinition.sections.flatMap(\.groups).flatMap { $0 }
            .map(MainMenuDefinition.title).contains("종료"))
    }
}
