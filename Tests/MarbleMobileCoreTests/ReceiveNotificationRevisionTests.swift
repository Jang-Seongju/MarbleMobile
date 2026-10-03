import XCTest
@testable import MarbleMobileCore

final class ReceiveNotificationRevisionTests: XCTestCase {
    func testFriendPresenceMergeMatchesPCFriendOrderingAndLabels() {
        var state = SocialState(friends: [
            SocialUser(userID: 2, nickname: "오프라인친구"),
            SocialUser(userID: 1, nickname: "게임친구"),
        ])
        state.mergePresence([
            LobbyUser(id: 1, nickname: "게임친구", connectionStatus: .connected, isGameInProgress: true),
        ])

        XCTAssertEqual(state.friends.map(\.userID), [1, 2])
        XCTAssertEqual(SocialPresentationFormatter.friendLabel(state.friends[0]), "게임친구, 게임 중")
        XCTAssertEqual(SocialPresentationFormatter.friendLabel(state.friends[1]), "오프라인친구, 오프라인")
    }

    func testFriendPresenceComparatorIgnoresNewFriendAndReportsExistingTransition() {
        let previous = FriendPresenceComparator.snapshot([
            SocialUser(userID: 1, nickname: "가", connectionStatus: .disconnected),
            SocialUser(userID: 2, nickname: "나", connectionStatus: .connected),
        ])
        let current = FriendPresenceComparator.snapshot([
            SocialUser(userID: 1, nickname: "가", connectionStatus: .recovering),
            SocialUser(userID: 2, nickname: "나", connectionStatus: .connected),
            SocialUser(userID: 3, nickname: "다", connectionStatus: .connected),
        ])

        XCTAssertEqual(
            FriendPresenceComparator.transitions(previous: previous, current: current),
            [FriendPresenceTransition(userID: 1, nickname: "가", isPresent: true)]
        )
    }

    func testNoteAndSocialManagementWireMessagesMatchServer679() {
        XCTAssertEqual(WireMessages.socialSearchUsers(query: "돌이")["type"] as? String, "social_search_users")
        XCTAssertEqual(WireMessages.socialSearchUsers(query: "돌이")["query"] as? String, "돌이")
        XCTAssertEqual(WireMessages.noteRecipientSearch(query: "  나비  ")["query"] as? String, "나비")
        XCTAssertEqual(WireMessages.noteDelete(noteID: 7)["note_id"] as? Int, 7)
        XCTAssertEqual(WireMessages.noteRecall(noteID: 7)["type"] as? String, "note_recall")
        XCTAssertEqual(WireMessages.noteDeleteConversation(targetUserID: 9)["target_user_id"] as? Int, 9)
    }

    func testNoteRowUsesNicknameBodyAndFullKoreanDateTime() {
        let note = NoteSnapshot(
            noteID: 1,
            counterpart: SocialUser(userID: 2, nickname: "뭉치"),
            body: "8시에 접속할게요",
            createdAt: "2026-10-01T18:42:00",
            isRead: false,
            direction: .received
        )
        XCTAssertEqual(
            NotePresentationFormatter.noteRowText(note, selfNickname: "당신"),
            "뭉치: 8시에 접속할게요, 2026년 10월 1일 오후 6시 42분, 읽지 않음"
        )
    }

    func testSentNoteRowUsesCurrentNicknameWithoutDirectionSection() {
        let note = NoteSnapshot(
            noteID: 2,
            counterpart: SocialUser(userID: 2, nickname: "뭉치"),
            body: "알겠습니다",
            createdAt: "2026-10-01T18:45:00",
            isRead: true,
            direction: .sent
        )
        XCTAssertEqual(
            NotePresentationFormatter.noteRowText(note, selfNickname: "나"),
            "나: 알겠습니다, 2026년 10월 1일 오후 6시 45분, 읽음"
        )
    }
}
