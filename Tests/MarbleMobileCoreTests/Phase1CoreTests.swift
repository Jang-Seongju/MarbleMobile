import Foundation
import XCTest
@testable import MarbleMobileCore

final class Phase1CoreTests: XCTestCase {
    func testPresenceLabelMatchesPCOrdering() {
        XCTAssertEqual(
            PresenceFormatter.label(nickname: "성주", status: .recovering, isSelf: true, isGameInProgress: true),
            "성주 (나, 게임 중, 복구 중)"
        )
        XCTAssertEqual(
            PresenceFormatter.label(nickname: "성주", status: .connected, isSelf: true, isGameInProgress: false),
            "성주 (나)"
        )
    }

    func testRoomLabelMatchesPC() {
        XCTAssertEqual(PresenceFormatter.roomLabel(.init(id: 7, title: "친선전", current: 2, maxPlayers: 4, isPrivate: false, status: "playing")), "7: 친선전 (게임 중)")
    }

    func testUserActionsMirrorPCFriendState() {
        let state = SocialState(friends: [.init(userID: 2, nickname: "강")])
        let actions = LobbyActionBuilder.userActions(targetUserID: 2, currentUserID: 1, socialState: state, hasGameRoom: true, isSpectator: false)
        XCTAssertEqual(actions.map(\.title), ["메시지 보내기", "쪽지 보내기", "초대하기", "관중석으로 초대", "친구 해제", "차단", "사용자 정보"])
    }

    func testSelfUserActionsDoNotContainFriendBlockActions() {
        let actions = LobbyActionBuilder.userActions(targetUserID: 1, currentUserID: 1, socialState: .init(), hasGameRoom: false, isSpectator: false)
        XCTAssertEqual(actions.map(\.title), ["메시지 보내기", "쪽지 보내기", "초대하기", "관중석으로 초대", "사용자 정보"])
        XCTAssertFalse(actions[1].isEnabled)
    }

    func testSocialPayloadParsing() {
        let payload: [String: Any] = [
            "friends": [["user_id": 2, "nickname": "강"]],
            "incoming_friend_requests": [["request_id": 9, "user": ["user_id": 3, "nickname": "미소"]]],
            "outgoing_friend_requests": [],
            "blocked_users": []
        ]
        let state = WireParser.socialState(from: payload)
        XCTAssertTrue(state.isFriend(2))
        XCTAssertEqual(state.incomingRequest(for: 3)?.requestID, 9)
    }
}

extension Phase1CoreTests {
    func testSessionEntryStrictNormalLobby() throws {
        XCTAssertEqual(
            try SessionEntryParser.parse(["type": "session_entry", "entry_mode": "normal_lobby"]),
            SessionEntry(mode: .normalLobby)
        )
        XCTAssertThrowsError(try SessionEntryParser.parse([
            "type": "session_entry", "entry_mode": "normal_lobby", "room_id": 1
        ]))
    }

    func testSessionEntryStrictRecovery() throws {
        let entry = try SessionEntryParser.parse([
            "type": "session_entry",
            "entry_mode": "active_game_recovery",
            "recovery_id": "r1",
            "room_id": 2,
            "game_session_id": "g1",
            "your_player_id": 3,
        ])
        XCTAssertEqual(entry.mode, .activeGameRecovery)
        XCTAssertEqual(entry.roomID, 2)
        XCTAssertThrowsError(try SessionEntryParser.parse([
            "type": "session_entry", "entry_mode": "active_game_recovery", "room_id": 2
        ]))
    }

    func testRoomInfoFormatterMatchesPC() {
        let room = GameRoomSummary(id: 7, title: "친선전", current: 2, maxPlayers: 4, isPrivate: true, status: "waiting")
        XCTAssertEqual(PresentationFormatter.roomInfoText(room), """
        방 번호: 7
        방 제목: 친선전
        게임 상태: 대기 중
        참여 인원: 2/4명
        공개 여부: 비공개
        참여 사용자:
        상세 정보 없음
        """)
    }

    func testUserProfileFormatterMatchesPCSectionsAndPrivacy() {
        let profile: [String: Any] = [
            "account": [
                "nickname": "강",
                "username": "kang",
                "created_at": "2026-09-20T13:05:00+09:00",
                "last_connected_at": NSNull(),
                "last_disconnected_at": NSNull(),
            ],
            "stats": [
                "total_games": 2, "wins": 1, "losses": 1, "win_rate": 50.0,
                "victory_score": 4.5, "cumulative_marble": 1234567, "bankruptcies": 0,
                "last_survivor_wins": 1, "ending_monopoly_wins": 0,
                "triple_color_ending_wins": 0, "line_ending_wins": 0,
                "tourist_ending_wins": 0, "ending_monopoly_total": 0,
            ],
            "ranking": [
                "adjusted_average_marble": 617283.5,
                "adjusted_average_victory_score": 2.25,
                "marble_score": 1.5,
                "ranking_score": 3.75,
                "rank": 2,
                "ranking_exclusion_reason": NSNull(),
            ],
            "runtime": ["connection_status": "connected", "location_type": "lobby"],
        ]
        let text = PresentationFormatter.userProfileText(profile)
        XCTAssertEqual(text, """
        사용자 정보: 강

        [계정 정보]
        닉네임: 강
        아이디: kang
        가입일: 2026년 9월 20일 오후 1시 05분
        최근 접속일: 기록 없음
        최근 종료일: 기록 없음

        [현재 상태]
        접속 상태: 접속 중
        위치: 대기실

        [기본 전적]
        총 게임 수: 2
        승리: 1
        패배: 1
        승률: 50.00%
        파산 횟수: 0

        [승리 유형]
        최종 생존 승리: 1
        엔딩 독점 승리: 0
        트리플 컬러독점 승리: 0
        라인독점 승리: 0
        관광지독점 승리: 0
        엔딩 독점 합계: 0

        [누적 점수]
        누적 마블: 1,234,567
        누적 승점: 4.5

        [보정 평균]
        보정 평균 마블: 617,283.50
        보정 평균 승점: 2.250000

        [순위 평가]
        마블 점수: 1.500000
        순위 평가 점수: 3.750000
        순위: 2위
        """)
    }
}

extension Phase1CoreTests {
    func testUserActionsMirrorPCBlockedIncomingOutgoingStates() {
        var blocked = SocialState(blockedUsers: [.init(userID: 2, nickname: "강")])
        XCTAssertEqual(
            LobbyActionBuilder.userActions(targetUserID: 2, currentUserID: 1, socialState: blocked, hasGameRoom: false, isSpectator: false).map(\.title),
            ["메시지 보내기", "쪽지 보내기", "초대하기", "관중석으로 초대", "차단 해제", "사용자 정보"]
        )
        blocked = SocialState(incomingRequests: [.init(requestID: 9, user: .init(userID: 2, nickname: "강"))])
        XCTAssertEqual(
            LobbyActionBuilder.userActions(targetUserID: 2, currentUserID: 1, socialState: blocked, hasGameRoom: false, isSpectator: false).map(\.title),
            ["메시지 보내기", "쪽지 보내기", "초대하기", "관중석으로 초대", "친구 요청 수락", "차단", "사용자 정보"]
        )
        blocked = SocialState(outgoingRequests: [.init(requestID: 10, user: .init(userID: 2, nickname: "강"))])
        XCTAssertEqual(
            LobbyActionBuilder.userActions(targetUserID: 2, currentUserID: 1, socialState: blocked, hasGameRoom: false, isSpectator: false).map(\.title),
            ["메시지 보내기", "쪽지 보내기", "초대하기", "관중석으로 초대", "요청 취소", "차단", "사용자 정보"]
        )
    }

    func testRoomActionOrderMatchesPC() {
        let actions = LobbyActionBuilder.roomActions(roomInteractionImplemented: false, spectatorInteractionImplemented: false)
        XCTAssertEqual(actions.map(\.title), ["방 개설", "참여하기", "관중석 입장", "방 정렬", "방 정보"])
        XCTAssertEqual(actions.map(\.isEnabled), [false, false, false, false, true])
    }
}

extension Phase1CoreTests {
    func testSocialWireMessagesMatchPCProtocol() {
        XCTAssertEqual(WireMessages.socialGetState()["type"] as? String, "social_get_state")
        XCTAssertEqual(WireMessages.invitationSend(targetUserID: 7, inviteType: "spectator")["invite_type"] as? String, "spectator")
        XCTAssertEqual(WireMessages.friendRequestSend(targetUserID: 7)["type"] as? String, "friend_request_send")
        XCTAssertEqual(WireMessages.friendRequestAccept(requestID: 9)["request_id"] as? Int, 9)
        XCTAssertEqual(WireMessages.friendRequestCancel(requestID: 9)["type"] as? String, "friend_request_cancel")
        XCTAssertEqual(WireMessages.friendshipUnfriend(targetUserID: 7)["type"] as? String, "friendship_unfriend")
        XCTAssertEqual(WireMessages.userBlock(targetUserID: 7)["type"] as? String, "user_block")
        XCTAssertEqual(WireMessages.userUnblock(targetUserID: 7)["type"] as? String, "user_unblock")
    }
}

extension Phase1CoreTests {
    func testRoomCreationRequestMatchesPCValidationAndNormalization() throws {
        let publicRequest = try RoomCreationRequest(
            title: "  친선전  ", maxPlayers: 4, isPrivate: false, password: "ignored"
        )
        XCTAssertEqual(publicRequest.title, "친선전")
        XCTAssertEqual(publicRequest.maxPlayers, 4)
        XCTAssertFalse(publicRequest.isPrivate)
        XCTAssertNil(publicRequest.password)

        let privateRequest = try RoomCreationRequest(
            title: "비공개", maxPlayers: 2, isPrivate: true, password: "  1234  "
        )
        XCTAssertEqual(privateRequest.password, "1234")

        XCTAssertThrowsError(try RoomCreationRequest(title: "   ", maxPlayers: 4, isPrivate: false, password: nil))
        XCTAssertThrowsError(try RoomCreationRequest(title: "방", maxPlayers: 5, isPrivate: false, password: nil))
        XCTAssertThrowsError(try RoomCreationRequest(title: "방", maxPlayers: 4, isPrivate: true, password: "   "))
    }

    func testJoinRoomWireMessageMatchesPCProtocol() {
        XCTAssertEqual(
            WireMessages.joinRoom(roomID: 7) as NSDictionary,
            ["type": "join_room", "room_id": 7] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.joinRoom(roomID: 8, password: "  secret  ") as NSDictionary,
            ["type": "join_room", "room_id": 8, "password": "secret"] as NSDictionary
        )
        XCTAssertNil(WireMessages.joinRoom(roomID: 9, password: "   ")["password"])
    }

    func testCreateRoomWireMessageMatchesPCProtocol() throws {
        let request = try RoomCreationRequest(
            title: "친선전", maxPlayers: 3, isPrivate: true, password: "pw"
        )
        let message = WireMessages.createRoom(request)
        XCTAssertEqual(message["type"] as? String, "create_room")
        XCTAssertEqual(message["title"] as? String, "친선전")
        XCTAssertEqual(message["max_players"] as? Int, 3)
        XCTAssertEqual(message["is_private"] as? Bool, true)
        XCTAssertEqual(message["password"] as? String, "pw")

        let publicMessage = WireMessages.createRoom(try RoomCreationRequest(
            title: "공개방", maxPlayers: 4, isPrivate: false, password: "discarded"
        ))
        XCTAssertNil(publicMessage["password"])
    }

    func testRoomCreatedParsingMatchesServerAuthorityPayload() throws {
        let snapshot = try RoomEntryParser.parseCreated([
            "type": "room_created",
            "room_id": 9,
            "title": "친선전",
            "max_players": 4,
            "is_private": false,
            "host_user_id": 3,
            "game_start_authority_user_id": 3,
        ])
        XCTAssertEqual(snapshot, RoomEntrySnapshot(
            roomID: 9,
            title: "친선전",
            maxPlayers: 4,
            isPrivate: false,
            hostUserID: 3,
            gameStartAuthorityUserID: 3
        ))

        XCTAssertThrowsError(try RoomEntryParser.parseCreated([
            "type": "room_created",
            "room_id": 9,
            "title": "친선전",
            "max_players": 4,
            "is_private": false,
            "host_user_id": 3,
        ]))
    }

    func testRoomActionsCanEnableCreateWithoutJoin() {
        let actions = LobbyActionBuilder.roomActions(
            roomCreationImplemented: true,
            roomJoinImplemented: false,
            spectatorInteractionImplemented: false
        )
        XCTAssertEqual(actions.map(\.title), ["방 개설", "참여하기", "관중석 입장", "방 정렬", "방 정보"])
        XCTAssertEqual(actions.map(\.isEnabled), [true, false, false, false, true])
    }
}

extension Phase1CoreTests {
    func testGameRoomWireMessagesMatchPCProtocol() {
        let createTeam = WireMessages.createTeam(teamName: "새 팀")
        XCTAssertEqual(createTeam["type"] as? String, "create_team")
        XCTAssertEqual(createTeam["team_name"] as? String, "새 팀")

        let emptyTeam = WireMessages.createTeam(teamName: "")
        XCTAssertEqual(emptyTeam["team_name"] as? String, "")

        let roomChat = WireMessages.roomChat(message: "안녕하세요")
        XCTAssertEqual(roomChat["type"] as? String, "room_chat")
        XCTAssertEqual(roomChat["message"] as? String, "안녕하세요")

        XCTAssertEqual(WireMessages.leaveRoom()["type"] as? String, "leave_room")
    }

    func testRoomUpdateAuthoritativelyDeterminesTeamMembership() throws {
        let snapshot = try RoomUpdateParser.parse([
            "type": "room_update",
            "room_id": 9,
            "title": "친선전",
            "max_players": 4,
            "is_private": false,
            "host_user_id": 3,
            "game_start_authority_user_id": 3,
            "teams": [
                [
                    "id": 11,
                    "name": "성주",
                    "members": [
                        ["user_id": 3, "nickname": "성주", "connection_status": "connected"]
                    ],
                ],
                [
                    "id": 12,
                    "name": "상대팀",
                    "members": [
                        ["user_id": 4, "nickname": "상대", "connection_status": "connected"]
                    ],
                ],
            ],
        ])

        XCTAssertTrue(snapshot.containsUserInTeam(3))
        XCTAssertEqual(snapshot.team(containing: 3)?.name, "성주")
        XCTAssertFalse(snapshot.containsUserInTeam(5))
    }

    func testRoomUpdateRejectsDuplicateUserAcrossTeams() {
        XCTAssertThrowsError(try RoomUpdateParser.parse([
            "type": "room_update",
            "room_id": 9,
            "title": "친선전",
            "max_players": 4,
            "is_private": false,
            "host_user_id": 3,
            "game_start_authority_user_id": 3,
            "teams": [
                ["id": 1, "name": "A", "members": [["user_id": 3, "nickname": "성주"]]],
                ["id": 2, "name": "B", "members": [["user_id": 3, "nickname": "성주"]]],
            ],
        ]))
    }

    func testRoomChatParsingMatchesServerEcho() throws {
        let chat = try RoomChatParser.parse([
            "type": "room_chat",
            "from_id": 3,
            "from_nickname": "성주",
            "message": "팀 만들기 전 채팅",
        ])
        XCTAssertEqual(chat, RoomChatMessage(
            fromUserID: 3,
            fromNickname: "성주",
            message: "팀 만들기 전 채팅"
        ))
    }

    func testRoomEventTeamCreatedFormattingMatchesPCClient() {
        XCTAssertEqual(
            RoomEventFormatter.message(from: [
                "type": "room_event",
                "event": "team_created",
                "actor_user_id": 3,
                "actor_nickname": "성주",
                "team_name": "새 팀",
            ]),
            "성주가 '새 팀' 팀을 만들었습니다."
        )
        XCTAssertEqual(
            RoomEventFormatter.message(from: [
                "type": "room_event",
                "event": "participant_joined",
                "actor_user_id": 4,
                "actor_nickname": "강",
            ]),
            "강이 입장했습니다."
        )
    }
}

extension Phase1CoreTests {
    func testRoomJoinedParsingUsesSameAuthorityContractAsCreated() throws {
        let snapshot = try RoomEntryParser.parseJoined([
            "type": "room_joined",
            "room_id": 12,
            "title": "기존 방",
            "max_players": 3,
            "is_private": true,
            "host_user_id": 7,
            "game_start_authority_user_id": 8,
        ])
        XCTAssertEqual(snapshot.roomID, 12)
        XCTAssertEqual(snapshot.hostUserID, 7)
        XCTAssertEqual(snapshot.gameStartAuthorityUserID, 8)
        XCTAssertThrowsError(try RoomEntryParser.parseJoined([
            "type": "room_created",
            "room_id": 12,
            "title": "기존 방",
            "max_players": 3,
            "is_private": true,
            "host_user_id": 7,
            "game_start_authority_user_id": 8,
        ]))
    }
}

extension Phase1CoreTests {
    func testRoomJoinActionCanBeEnabledIndependentlyOfRoomCreation() {
        let actions = LobbyActionBuilder.roomActions(
            roomCreationImplemented: true,
            roomJoinImplemented: true,
            spectatorInteractionImplemented: false
        )
        XCTAssertEqual(actions.map(\.title), ["방 개설", "참여하기", "관중석 입장", "방 정렬", "방 정보"])
        XCTAssertEqual(actions.map(\.isEnabled), [true, true, false, false, true])
    }
}


extension Phase1CoreTests {
    private func roundTripJSON(_ object: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testNetworkJSONIntegerOneIsAcceptedByStrictRoomEntryParser() throws {
        let payload = try roundTripJSON([
            "type": "room_created",
            "room_id": 1,
            "title": "네트워크 방",
            "max_players": 4,
            "is_private": false,
            "host_user_id": 1,
            "game_start_authority_user_id": 1,
        ])

        let snapshot = try RoomEntryParser.parseCreated(payload)
        XCTAssertEqual(snapshot.roomID, 1)
        XCTAssertEqual(snapshot.hostUserID, 1)
        XCTAssertEqual(snapshot.gameStartAuthorityUserID, 1)
    }

    func testNetworkJSONIntegerOneIsAcceptedByRoomUpdateChatAndRecoveryParsers() throws {
        let update = try roundTripJSON([
            "type": "room_update",
            "room_id": 1,
            "title": "네트워크 방",
            "max_players": 4,
            "is_private": false,
            "host_user_id": 1,
            "game_start_authority_user_id": 1,
            "teams": [[
                "id": 1,
                "name": "첫 팀",
                "members": [[
                    "user_id": 1,
                    "nickname": "첫 사용자",
                    "connection_status": "connected",
                ]],
            ]],
        ])
        let room = try RoomUpdateParser.parse(update)
        XCTAssertEqual(room.roomID, 1)
        XCTAssertEqual(room.teams.first?.id, 1)
        XCTAssertEqual(room.teams.first?.members.first?.userID, 1)

        let chat = try roundTripJSON([
            "type": "room_chat",
            "from_id": 1,
            "from_nickname": "첫 사용자",
            "message": "안녕하세요",
        ])
        XCTAssertEqual(try RoomChatParser.parse(chat).fromUserID, 1)

        let recovery = try roundTripJSON([
            "type": "session_entry",
            "entry_mode": "active_game_recovery",
            "recovery_id": "recovery-1",
            "room_id": 1,
            "game_session_id": "game-1",
            "your_player_id": 1,
        ])
        let entry = try SessionEntryParser.parse(recovery)
        XCTAssertEqual(entry.roomID, 1)
        XCTAssertEqual(entry.yourPlayerID, 1)
    }

    func testStrictNetworkIntegerParserStillRejectsBooleanAndFloatingPoint() throws {
        let booleanRoomID = try roundTripJSON([
            "type": "room_created",
            "room_id": true,
            "title": "잘못된 방",
            "max_players": 4,
            "is_private": false,
            "host_user_id": 2,
            "game_start_authority_user_id": 2,
        ])
        XCTAssertThrowsError(try RoomEntryParser.parseCreated(booleanRoomID))

        let floatingJSON = #"{"type":"room_created","room_id":1.0,"title":"잘못된 방","max_players":4,"is_private":false,"host_user_id":2,"game_start_authority_user_id":2}"#
        let floatingRoomID = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(floatingJSON.utf8)) as? [String: Any]
        )
        XCTAssertThrowsError(try RoomEntryParser.parseCreated(floatingRoomID))
    }
}


extension Phase1CoreTests {
    func testNetworkJSONNumericZeroAndOneRemainNumbersInPresentation() throws {
        let profile = try roundTripJSON([
            "account": ["nickname": "첫 사용자"],
            "stats": [
                "total_games": 1, "wins": 1, "losses": 0, "win_rate": 100.0,
                "victory_score": 1, "cumulative_marble": 1, "bankruptcies": 0,
                "last_survivor_wins": 1, "ending_monopoly_wins": 0,
                "triple_color_ending_wins": 0, "line_ending_wins": 0,
                "tourist_ending_wins": 0, "ending_monopoly_total": 0,
            ],
            "ranking": [
                "adjusted_average_marble": 1,
                "adjusted_average_victory_score": 1,
                "marble_score": 1,
                "ranking_score": 1,
                "rank": 1,
            ],
            "runtime": ["connection_status": "connected", "location_type": "lobby"],
        ])
        let text = PresentationFormatter.userProfileText(profile)
        XCTAssertTrue(text.contains("총 게임 수: 1"))
        XCTAssertTrue(text.contains("승리: 1"))
        XCTAssertTrue(text.contains("패배: 0"))
        XCTAssertTrue(text.contains("누적 마블: 1"))
        XCTAssertTrue(text.contains("순위: 1위"))
    }

    func testNetworkJSONBooleanDoesNotMasqueradeAsLobbyIntegerID() throws {
        let payload = try roundTripJSON([
            "users": [[
                "user_id": true,
                "nickname": "잘못된 사용자",
                "connection_status": "connected",
                "is_game_in_progress": false,
            ]],
        ])
        XCTAssertEqual(try WireParser.lobbyUsers(from: payload), [])
    }
}
