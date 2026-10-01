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

extension Phase1CoreTests {

    private func staticInformationPayloadForDirectTouchTests() -> [String: Any] {
        let items: [[String: Any]] = [
            [
                "city_id": 2,
                "city_name": "도시 2",
                "city_description": "도시 2 설명",
            ],
            [
                "city_id": 2,
                "city_name": "도시 2",
                "city_type": "general",
                "building_type": "땅",
                "build_cost": 20_000,
                "toll_value": 2_000,
                "acquisition_value": 30_000,
                "sell_value": 10_000,
            ],
            [
                "city_id": 2,
                "city_name": "도시 2",
                "city_type": "general",
                "building_type": "빌라",
                "build_cost": 50_000,
                "toll_value": 5_000,
                "acquisition_value": 75_000,
                "sell_value": 25_000,
            ],
        ]
        return [
            "info": NSNull(),
            "items": items,
            "empty_reason": NSNull(),
            "subject_nickname": NSNull(),
            "index": NSNull(),
            "total_count": items.count,
        ]
    }

    private func boardCellsPayloadForDirectTouchTests() -> [String: Any] {
        var cells: [[String: Any]] = []
        for index in 1...32 {
            let row: Int
            let col: Int
            switch index {
            case 1...9:
                row = 8
                col = 9 - index
            case 10...16:
                row = 17 - index
                col = 0
            case 17...25:
                row = 0
                col = index - 17
            default:
                row = index - 25
                col = 8
            }

            let isStart = index == 1
            cells.append([
                "index": index,
                "name": isStart ? "출발" : "도시 \(index)",
                "cell_type": isStart ? "START" : "CITY",
                "city_id": isStart ? NSNull() : index,
                "city_type": isStart ? NSNull() : "general",
                "group": isStart ? NSNull() : "연두",
                "base_price": isStart ? 0 : 20_000,
                "row": row,
                "col": col,
            ])
        }
        return ["type": "board_cells", "board_cells": cells]
    }

    func testBoardCellsParserMatchesServer677StaticBoardContract() throws {
        let original = boardCellsPayloadForDirectTouchTests()
        let encoded = try JSONSerialization.data(withJSONObject: original)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let board = try BoardCellsParser.parse(payload)

        XCTAssertEqual(board.cells.count, 32)
        XCTAssertEqual(board.cell(at: 1)?.row, 8)
        XCTAssertEqual(board.cell(at: 1)?.column, 8)
        XCTAssertEqual(board.cell(at: 1)?.shortDescription, "출발")
        XCTAssertEqual(board.cell(at: 2)?.shortDescription, "도시 2, 연두")
        XCTAssertEqual(board.cell(at: 17)?.row, 0)
        XCTAssertEqual(board.cell(at: 17)?.column, 0)
        XCTAssertEqual(board.cell(at: 32)?.row, 7)
        XCTAssertEqual(board.cell(at: 32)?.column, 8)
    }

    func testBoardCellsParserRejectsMalformedTopology() throws {
        var duplicateIndex = boardCellsPayloadForDirectTouchTests()
        var cells = try XCTUnwrap(duplicateIndex["board_cells"] as? [[String: Any]])
        cells[1]["index"] = 1
        duplicateIndex["board_cells"] = cells
        XCTAssertThrowsError(try BoardCellsParser.parse(duplicateIndex))

        var booleanIndex = boardCellsPayloadForDirectTouchTests()
        cells = try XCTUnwrap(booleanIndex["board_cells"] as? [[String: Any]])
        cells[0]["index"] = true
        booleanIndex["board_cells"] = cells
        let encoded = try JSONSerialization.data(withJSONObject: booleanIndex)
        let roundTripped = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertThrowsError(try BoardCellsParser.parse(roundTripped))
    }

    func testBoardSpatialNavigationMatchesClient393GridContract() throws {
        let board = try BoardCellsParser.parse(boardCellsPayloadForDirectTouchTests())

        // 우하단 출발지: 왼쪽(A라인)과 위(D라인)만 열린다.
        XCTAssertEqual(board.adjacentCell(from: 1, direction: .left)?.index, 2)
        XCTAssertEqual(board.adjacentCell(from: 1, direction: .up)?.index, 32)
        XCTAssertNil(board.adjacentCell(from: 1, direction: .right))
        XCTAssertNil(board.adjacentCell(from: 1, direction: .down))

        // 좌하단 모서리 9: 오른쪽(A) / 위(B).
        XCTAssertEqual(board.adjacentCell(from: 9, direction: .right)?.index, 8)
        XCTAssertEqual(board.adjacentCell(from: 9, direction: .up)?.index, 10)
        XCTAssertNil(board.adjacentCell(from: 9, direction: .left))
        XCTAssertNil(board.adjacentCell(from: 9, direction: .down))

        // 좌상단 17: 오른쪽(C) / 아래(B).
        XCTAssertEqual(board.adjacentCell(from: 17, direction: .right)?.index, 18)
        XCTAssertEqual(board.adjacentCell(from: 17, direction: .down)?.index, 16)

        // 우상단 25: 왼쪽(C) / 아래(D).
        XCTAssertEqual(board.adjacentCell(from: 25, direction: .left)?.index, 24)
        XCTAssertEqual(board.adjacentCell(from: 25, direction: .down)?.index, 26)

        // 중간 라인은 각 라인의 물리 축 외 방향을 허용하지 않는다.
        XCTAssertEqual(board.adjacentCell(from: 5, direction: .left)?.index, 6)
        XCTAssertNil(board.adjacentCell(from: 5, direction: .up))
        XCTAssertEqual(board.adjacentCell(from: 13, direction: .up)?.index, 14)
        XCTAssertNil(board.adjacentCell(from: 13, direction: .right))
    }

    func testBoardCursorUsesCircularPreviousAndNextOrder() {
        var cursor = BoardCursorState(index: 1)
        XCTAssertEqual(cursor.movePrevious(), 32)
        XCTAssertEqual(cursor.moveNext(), 1)
        XCTAssertEqual(cursor.moveNext(), 2)
    }

    func testCityCostCycleDownIsForwardAndUpIsReverse() {
        var cycle = CityCostCycleState()
        XCTAssertEqual(cycle.moveForward(), .toll)
        XCTAssertEqual(cycle.moveForward(), .acquisition)
        XCTAssertEqual(cycle.moveForward(), .sale)
        XCTAssertEqual(cycle.moveForward(), .toll)

        cycle.reset()
        XCTAssertEqual(cycle.moveBackward(), .sale)
        XCTAssertEqual(cycle.moveBackward(), .acquisition)
        XCTAssertEqual(cycle.moveBackward(), .toll)
    }
}

extension Phase1CoreTests {
    func testGameplayWireMessagesMatchServer677Protocol() {
        XCTAssertEqual(WireMessages.gameStart() as NSDictionary, ["type": "game_start"] as NSDictionary)
        XCTAssertEqual(
            WireMessages.gameStartAISelectionResponse(requestID: "req-1", selectedAIIDs: ["ai-a", "ai-b"]) as NSDictionary,
            ["type": "game_start_ai_selection_response", "request_id": "req-1", "selected_ai_ids": ["ai-a", "ai-b"]] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.gameStartAISelectionCancel(requestID: "req-1") as NSDictionary,
            ["type": "game_start_ai_selection_cancel", "request_id": "req-1"] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.turnReady(turnGeneration: 1) as NSDictionary,
            ["type": "game_action", "action": "turn_ready", "turn_generation": 1] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.rollDice() as NSDictionary,
            ["type": "game_action", "action": "roll_dice"] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.toggleBailPayment() as NSDictionary,
            ["type": "game_action", "action": "toggle_bail_payment"] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.toggleHeldCardUse() as NSDictionary,
            ["type": "game_action", "action": "toggle_held_card_use"] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.interactionResponse(
                requestID: "interaction-1",
                responseType: "selected",
                payload: ["selected_ids": ["villa", "hotel"]]
            ) as NSDictionary,
            [
                "type": "game_action", "action": "interaction_response",
                "request_id": "interaction-1", "response_type": "selected",
                "payload": ["selected_ids": ["villa", "hotel"]],
            ] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.interactionPresentationActivate(requestID: "interaction-1") as NSDictionary,
            ["type": "game_action", "action": "interaction_presentation_activate", "request_id": "interaction-1"] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.informationQuery(
                queryType: "player_info",
                payload: ["opponent_player_id": 2]
            ) as NSDictionary,
            [
                "type": "game_action", "action": "information_query",
                "query_type": "player_info", "opponent_player_id": 2,
            ] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.informationQuery(
                queryType: "city_cost", cityID: 1,
                payload: ["cost_type": "toll"]
            ) as NSDictionary,
            [
                "type": "game_action", "action": "information_query",
                "query_type": "city_cost", "city_id": 1, "cost_type": "toll",
            ] as NSDictionary
        )
    }

    func testAISelectionParserAcceptsRealNetworkIntegerOneAndPreservesServerOrder() throws {
        let payload = try roundTripJSON([
            "type": "game_start_ai_selection_required",
            "request_id": "selection-1",
            "room_id": 1,
            "human_player_count": 1,
            "max_players": 4,
            "minimum_ai_count": 1,
            "maximum_ai_count": 3,
            "allowed_ai_counts": [1, 2, 3],
            "available_ai_participants": [
                ["ai_id": "ai-one", "nickname": "AI하나"],
                ["ai_id": "ai-two", "nickname": "AI둘"],
                ["ai_id": "ai-three", "nickname": "AI셋"],
            ],
        ])
        let request = try AIPlayerSelectionParser.parse(payload)
        XCTAssertEqual(request.roomID, 1)
        XCTAssertEqual(request.humanPlayerCount, 1)
        XCTAssertEqual(request.allowedAICounts, [1, 2, 3])
        XCTAssertEqual(request.availableAI.map(\.aiID), ["ai-one", "ai-two", "ai-three"])

        var invalid = payload
        invalid["human_player_count"] = true
        XCTAssertThrowsError(try AIPlayerSelectionParser.parse(invalid))
    }

    func testGameStartedParserAcceptsServer677InitialPlayerShape() throws {
        let boardPayload = boardCellsPayloadForDirectTouchTests()
        let cells = try XCTUnwrap(boardPayload["board_cells"] as? [[String: Any]])
        let payload = try roundTripJSON([
            "type": "game_started",
            "your_player_id": 1,
            "current_player_id": 2,
            "players": [
                [
                    "player_id": 1, "user_id": 1, "nickname": "사용자", "team_name": "사용자",
                    "marble": 2_000_000, "position": 1, "lap_count": 0,
                    "connection_status": "connected", "is_ai": false,
                ],
                [
                    "player_id": 2, "user_id": NSNull(), "nickname": "AI돌이", "team_name": "AI돌이",
                    "marble": 2_000_000, "position": 1, "lap_count": 0,
                    "connection_status": NSNull(), "is_ai": true,
                ],
            ],
            "festival_city_ids": [1, 2, 3],
            "cities": [],
            "board_cells": cells,
            "static_information": staticInformationPayloadForDirectTouchTests(),
        ])
        let started = try GameplayParser.gameStarted(payload)
        XCTAssertEqual(started.yourPlayerID, 1)
        XCTAssertEqual(started.currentPlayerID, 2)
        XCTAssertEqual(started.players.count, 2)
        XCTAssertFalse(started.players[0].isStranded)
        XCTAssertFalse(started.players[0].isBankrupt)
        XCTAssertTrue(started.players[1].isAI)
        XCTAssertEqual(started.players[0].connectionStatus, "connected")
        XCTAssertNil(started.players[1].connectionStatus)
        XCTAssertEqual(started.staticInformation.buildingTypes(cityID: 2), ["땅", "빌라"])
        XCTAssertEqual(started.festivalCityIDs, [1, 2, 3])
        XCTAssertEqual(started.boardCatalog.cells.count, 32)
    }

    func testTurnStartedParserUsesGenerationAndDefaultsToRollDice() throws {
        let explicit = try roundTripJSON([
            "type": "notification", "notification_type": "turn_started",
            "payload": ["player_id": 1, "turn_generation": 1, "next_turn_command": "select_world_travel_destination"],
        ])
        XCTAssertEqual(
            try GameplayParser.turnStarted(explicit),
            TurnStartedSnapshot(playerID: 1, turnGeneration: 1, nextTurnCommand: "select_world_travel_destination")
        )

        let defaulted = try roundTripJSON([
            "type": "notification", "notification_type": "turn_started",
            "payload": ["player_id": 2, "turn_generation": 3],
        ])
        XCTAssertEqual(
            try GameplayParser.turnStarted(defaulted),
            TurnStartedSnapshot(playerID: 2, turnGeneration: 3, nextTurnCommand: "roll_dice")
        )
    }

    func testInteractionParserCoversConfirmBuildAndWorldTravelDestination() throws {
        let purchase = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-p", "request_id": "req-p",
            "action_type": "purchase_city", "interaction_type": "confirm", "cancellable": true,
            "payload": ["mission_type": "purchase_city", "city_id": 1, "city_name": "방콕", "cost": 200_000],
        ])
        let purchaseRequest = try InteractionRequestParser.parse(purchase)
        XCTAssertEqual(purchaseRequest.interactionType, "confirm")
        XCTAssertTrue(purchaseRequest.cancellable)
        XCTAssertEqual(purchaseRequest.missionType, "purchase_city")

        let build = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-b", "request_id": "req-b",
            "action_type": "build", "interaction_type": "select_multiple", "cancellable": true,
            "payload": [
                "mission_type": "build_multiple", "city_id": 1, "city_name": "방콕", "owned_marble": 2_000_000,
                "items": [
                    ["id": "villa", "building_type": "villa", "build_cost": 50_000, "disabled": false],
                    ["id": "hotel", "building_type": "hotel", "build_cost": 150_000, "disabled": true],
                ],
            ],
        ])
        let buildRequest = try InteractionRequestParser.parse(build)
        XCTAssertEqual(buildRequest.items.map(\.id), ["villa", "hotel"])
        XCTAssertEqual(buildRequest.items.map(\.label), ["별장", "호텔, 선택 불가"])
        XCTAssertEqual(buildRequest.items.map(\.cost), [50_000, 150_000])

        let travel = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-w", "request_id": "req-w",
            "action_type": "world_travel_destination", "interaction_type": "select_destination", "cancellable": false,
            "payload": [
                "mission_type": "world_travel_destination",
                "allowed_destinations": [1, 9, 17, 25], "excluded_indices": [2, 3],
            ],
        ])
        let travelRequest = try InteractionRequestParser.parse(travel)
        XCTAssertEqual(travelRequest.allowedDestinationIndices, [1, 9, 17, 25])
        XCTAssertEqual(travelRequest.excludedIndices, Set([2, 3]))
        XCTAssertFalse(travelRequest.cancellable)
    }

    func testInteractionParserCoversRemainingServer677InteractionTypes() throws {
        let liquidation = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-l", "request_id": "req-l",
            "action_type": "liquidation", "interaction_type": "select_multiple", "cancellable": false,
            "payload": [
                "mission_type": "liquidation", "required_amount": 500_000, "current_marble": 100_000,
                "items": [[
                    "id": "1", "city_id": 1, "city_name": "방콕", "group": "연두",
                    "buildings": ["빌라"], "sell_value": 450_000, "disabled": false,
                ]],
            ],
        ])
        let liquidationRequest = try InteractionRequestParser.parse(liquidation)
        XCTAssertEqual(liquidationRequest.missionType, "liquidation")
        XCTAssertEqual(liquidationRequest.requiredAmount, 500_000)
        XCTAssertEqual(liquidationRequest.ownedMarble, 100_000)
        XCTAssertEqual(liquidationRequest.items.first?.cost, 450_000)

        let olympic = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-o", "request_id": "req-o",
            "action_type": "olympic_city_select", "interaction_type": "select_one", "cancellable": true,
            "payload": [
                "mission_type": "olympic", "current_marble": 1_000_000,
                "items": [[
                    "id": "1", "city_id": 1, "city_name": "방콕",
                    "at_max": true, "disabled": true, "reason_code": "max_olympic",
                ]],
            ],
        ])
        let olympicRequest = try InteractionRequestParser.parse(olympic)
        XCTAssertEqual(olympicRequest.interactionType, "select_one")
        XCTAssertEqual(olympicRequest.items.first?.atMax, true)
        XCTAssertEqual(olympicRequest.items.first?.reasonCode, "max_olympic")

        let fortune = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-card", "request_id": "req-card",
            "action_type": "fortune_card_response", "interaction_type": "acknowledge", "cancellable": false,
            "payload": [
                "mission_type": "fortune_card", "card_id": "card-1",
                "card_name": "황사", "card_description": "도시의 통행료가 감소합니다.",
            ],
        ])
        let fortuneRequest = try InteractionRequestParser.parse(fortune)
        XCTAssertEqual(fortuneRequest.interactionType, "acknowledge")
        XCTAssertEqual(fortuneRequest.cardName, "황사")
        XCTAssertEqual(fortuneRequest.cardDescription, "도시의 통행료가 감소합니다.")

        let bonus = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-bonus", "request_id": "req-bonus",
            "action_type": "bonus_game", "interaction_type": "select_one", "cancellable": false,
            "payload": [
                "mission_type": "bonus_game", "bonus_game_step": 1, "bonus_game_earned": 0,
                "items": [
                    ["id": "coin_front", "action": "coin_front", "disabled": false],
                    ["id": "coin_back", "action": "coin_back", "disabled": false],
                ],
            ],
        ])
        XCTAssertEqual(try InteractionRequestParser.parse(bonus).items.map(\.id), ["coin_front", "coin_back"])

        let defense = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-defense", "request_id": "req-defense",
            "action_type": "defense_response", "interaction_type": "confirm", "cancellable": true,
            "payload": [
                "mission_type": "defense", "defense_type": "attack", "attack_type": "yellow_dust",
                "attacker_player_id": 2, "city_id": 1, "defense_card_name": "천사 카드",
            ],
        ])
        let defenseRequest = try InteractionRequestParser.parse(defense)
        XCTAssertEqual(defenseRequest.title, "공격 방어")
        XCTAssertTrue(defenseRequest.cancellable)
    }

    func testInteractionParserCoversGroupedFortuneAndStartCellBuild() throws {
        let fortune = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-f", "request_id": "req-f",
            "action_type": "fortune_selection", "interaction_type": "select_one_per_group", "cancellable": false,
            "payload": [
                "mission_type": "fortune_selection", "card_name": "도시 체인지",
                "groups": [
                    ["role": "owned_city", "items": [["id": "1", "city_id": 1, "disabled": false]]],
                    ["role": "opponent_city", "items": [["id": "2", "city_id": 2, "disabled": false]]],
                ],
            ],
        ])
        let fortuneRequest = try InteractionRequestParser.parse(fortune)
        XCTAssertEqual(fortuneRequest.groups.map(\.role), ["owned_city", "opponent_city"])
        XCTAssertEqual(fortuneRequest.cardName, "도시 체인지")

        let startBuild = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-s", "request_id": "req-s",
            "action_type": "start_cell_build_selection", "interaction_type": "select_city_and_buildings", "cancellable": true,
            "payload": [
                "mission_type": "start_cell_build_selection", "owned_marble": 1_500_000,
                "cities": [[
                    "city_id": 1, "city_name": "방콕", "group": "연두", "buildings": ["별장"],
                    "build_options": [
                        ["id": "building", "building_type": "building", "build_cost": 100_000, "disabled": false],
                        ["id": "hotel", "building_type": "hotel", "build_cost": 200_000, "disabled": false],
                    ],
                ]],
            ],
        ])
        let buildRequest = try InteractionRequestParser.parse(startBuild)
        XCTAssertEqual(buildRequest.ownedMarble, 1_500_000)
        XCTAssertEqual(buildRequest.startBuildCities.count, 1)
        XCTAssertEqual(buildRequest.startBuildCities[0].cityID, 1)
        XCTAssertEqual(buildRequest.startBuildCities[0].label, "방콕, 별장, 연두")
        XCTAssertEqual(buildRequest.startBuildCities[0].information.groupName, "연두")
        XCTAssertEqual(buildRequest.startBuildCities[0].buildOptions.map(\.id), ["building", "hotel"])
    }

    func testInformationInfoParserRetainsServer677CityStateFields() throws {
        let raw = try roundTripJSON([
            "city_id": 7,
            "city_name": "방콕",
            "city_type": "general",
            "owner_id": 3,
            "owner_nickname": "성주",
            "group_name": "연두",
            "buildings": ["빌라", "빌딩"],
            "city_effect_types": ["yellow_dust", "plague"],
            "is_color_monopoly": true,
            "is_festival": true,
            "has_olympic": true,
            "olympic_count": 2,
        ])
        let info = try XCTUnwrap(InformationParser.info(raw))
        XCTAssertEqual(info.cityID, 7)
        XCTAssertEqual(info.cityName, "방콕")
        XCTAssertEqual(info.ownerID, 3)
        XCTAssertEqual(info.ownerNickname, "성주")
        XCTAssertEqual(info.groupName, "연두")
        XCTAssertEqual(info.buildings, ["빌라", "빌딩"])
        XCTAssertEqual(info.cityEffectTypes, ["yellow_dust", "plague"])
        XCTAssertEqual(info.isColorMonopoly, true)
        XCTAssertEqual(info.isFestival, true)
        XCTAssertEqual(info.hasOlympic, true)
        XCTAssertEqual(info.olympicCount, 2)
    }

    func testInformationCityPresenterMatchesClient393FieldOrder() {
        let info = InformationInfo(
            cityID: 7,
            cityName: "방콕",
            ownerID: 3,
            ownerNickname: "성주",
            groupName: "연두",
            buildings: ["빌라"],
            cityEffectTypes: ["yellow_dust"],
            isColorMonopoly: true,
            isFestival: true,
            hasOlympic: true,
            olympicCount: 2
        )
        XCTAssertEqual(
            InformationCityPresenter.format(info, myPlayerID: 3),
            "방콕, 빌라, 연두, 독점, 올림픽 2회, 황사, 축제, 내 소유"
        )
        XCTAssertEqual(
            InformationCityPresenter.format(info, myPlayerID: 1),
            "방콕, 빌라, 연두, 독점, 올림픽 2회, 황사, 축제, 성주 소유"
        )
    }

    func testInteractionCityPresentationUsesCommonInformationDTO() {
        let info = InformationInfo(
            cityID: 7,
            cityName: "방콕",
            ownerID: 4,
            ownerNickname: "AI돌이",
            groupName: "연두",
            buildings: ["빌라", "빌딩"],
            cityEffectTypes: ["plague"],
            isColorMonopoly: true,
            isFestival: true,
            hasOlympic: true,
            olympicCount: 2
        )

        XCTAssertEqual(
            InformationCityPresenter.formatCityInteractionItem(
                info,
                myPlayerID: 3
            ),
            "방콕, 빌라, 빌딩, 연두, 독점, 올림픽 2회, 전염병, 축제, AI돌이 소유"
        )

        XCTAssertEqual(
            InformationCityPresenter.formatOwnedCityInteractionItem(
                info,
                atMax: true,
                disabled: true
            ),
            "방콕, 빌라, 빌딩, 연두, 독점, 올림픽 2회, 전염병, 축제, 최대, 선택 불가"
        )

        XCTAssertEqual(
            InformationCityPresenter.formatLiquidationInteractionItem(
                info,
                sellValue: 450_000
            ),
            "방콕, 빌라, 빌딩, 연두, 독점, 올림픽 2회, 전염병, 축제, 매각 대금 450,000마블"
        )

        XCTAssertEqual(
            InteractionCityItemPresenter.format(
                information: info,
                missionType: "olympic",
                cost: 0,
                atMax: true,
                disabled: true,
                myPlayerID: 3
            ),
            "방콕, 빌라, 빌딩, 연두, 독점, 올림픽 2회, 전염병, 축제, 최대, 선택 불가"
        )
        XCTAssertEqual(
            InteractionCityItemPresenter.format(
                information: info,
                missionType: "fortune_selection",
                role: "opponent_city",
                myPlayerID: 3
            ),
            "방콕, 빌라, 빌딩, 연두, 독점, 올림픽 2회, 전염병, 축제, AI돌이 소유"
        )
    }

    func testInformationPlayerPresenterKeepsSelfOpponentAndDisconnectedSemantics() {
        let selfInfo = InformationInfo(
            playerID: 3,
            nickname: "성주",
            marble: 628_000,
            ownedCityCount: 9,
            connectionStatus: "connected",
            heldCardName: "무인도 탈출 카드"
        )
        XCTAssertEqual(
            InformationResultPresenter.format(
                queryType: "player_info",
                result: InformationResult(info: selfInfo),
                myPlayerID: 3
            ),
            "628,000마블 소유 도시 9곳 보관 카드 무인도 탈출 카드"
        )

        let opponent = InformationInfo(
            playerID: 4,
            nickname: "알바스찬",
            marble: 628_000,
            ownedCityCount: 9,
            connectionStatus: "recovering"
        )
        XCTAssertEqual(
            InformationResultPresenter.format(
                queryType: "player_info",
                result: InformationResult(info: opponent),
                myPlayerID: 3
            ),
            "알바스찬 628,000마블 소유 도시 9곳 접속 끊김"
        )
    }

    func testCityBuildingPresentationUsesCanonicalAuditoryOrder() {
        let info = InformationInfo(
            cityID: 10,
            cityName: "퀘백",
            buildings: ["호텔", "빌라", "빌딩"]
        )

        // DTO 원본은 서버 순서를 그대로 보존한다. 표시할 때만 접근성 기준 순서로 정규화한다.
        XCTAssertEqual(info.buildings, ["호텔", "빌라", "빌딩"])
        XCTAssertEqual(
            InformationCityPresenter.format(info, spec: InformationDisplaySpecs.buildingStatus),
            "빌라, 빌딩, 호텔"
        )
        XCTAssertEqual(
            InformationResultPresenter.format(
                queryType: "city_info",
                result: InformationResult(info: info),
                asBuildingStatus: true
            ),
            "빌라, 빌딩, 호텔"
        )
    }

    func testStaticInformationCatalogPreservesServerBuildingOrder() throws {
        let catalog = try StaticInformationCatalogParser.parse(staticInformationPayloadForDirectTouchTests())
        XCTAssertEqual(catalog.buildingTypes(cityID: 2), ["땅", "빌라"])
        XCTAssertEqual(catalog.cityDescription(cityID: 2)?.cityDescription, "도시 2 설명")
        XCTAssertEqual(catalog.buildingValue(cityID: 2, buildingType: "빌라")?.buildCost, 50_000)
    }

    func testBoardBootstrapParsesBoardAndStaticInformationAtomically() throws {
        var payload = boardCellsPayloadForDirectTouchTests()
        payload["static_information"] = staticInformationPayloadForDirectTouchTests()
        let bootstrap = try BoardBootstrapParser.parse(payload)
        XCTAssertEqual(bootstrap.boardCatalog.cells.count, 32)
        XCTAssertEqual(bootstrap.staticInformation.buildingTypes(cityID: 2), ["땅", "빌라"])

        var missingStatic = boardCellsPayloadForDirectTouchTests()
        missingStatic.removeValue(forKey: "static_information")
        XCTAssertThrowsError(try BoardBootstrapParser.parse(missingStatic))
    }

    func testGameRotorPlayerOrderStartsAtSelfAndPlacesUnownedLast() {
        let players = [1, 2, 3, 4].map { id in
            GamePlayerSnapshot(
                playerID: id,
                userID: id,
                nickname: "P\(id)",
                teamName: "P\(id)",
                marble: 2_000_000,
                position: 1,
                lapCount: 0,
                isStranded: false,
                isBankrupt: false,
                isAI: false
            )
        }
        var rotor = GameRotorState()
        rotor.synchronizePlayers(myPlayerID: 3, players: players)
        XCTAssertEqual(rotor.playerTarget, .player(3))
        XCTAssertEqual(
            rotor.playerTargets(myPlayerID: 3, players: players),
            [.player(3), .player(4), .player(1), .player(2), .unowned]
        )
        XCTAssertEqual(rotor.movePlayerTarget(forward: false, myPlayerID: 3, players: players), .unowned)
        XCTAssertEqual(rotor.movePlayerTarget(forward: true, myPlayerID: 3, players: players), .player(3))
        XCTAssertEqual(rotor.movePlayerTarget(forward: true, myPlayerID: 3, players: players), .player(4))
        XCTAssertEqual(rotor.nextOpponentCityIndex(forward: true), 0)
        XCTAssertEqual(rotor.nextOpponentCityIndex(forward: true), 1)
        XCTAssertEqual(rotor.movePlayerTarget(forward: true, myPlayerID: 3, players: players), .player(1))
        XCTAssertEqual(rotor.nextOpponentCityIndex(forward: true), 0)
    }

    func testGameRotorPlayerPositionOrderMatchesPlayerInfoWithoutUnowned() {
        let players = [1, 2, 3, 4].map { id in
            GamePlayerSnapshot(
                playerID: id,
                userID: id,
                nickname: "P\(id)",
                teamName: "P\(id)",
                marble: 2_000_000,
                position: id,
                lapCount: 0,
                isStranded: false,
                isBankrupt: false,
                isAI: false
            )
        }
        var rotor = GameRotorState()
        rotor.synchronizePlayers(myPlayerID: 3, players: players)

        XCTAssertEqual(rotor.playerPositionPlayerID, 3)
        XCTAssertEqual(rotor.playerPositionPlayerIDs(myPlayerID: 3, players: players), [3, 4, 1, 2])
        // 2층 로터: 첫 아래 쓸기는 기본 대상인 본인, 이후 player_id 순환.
        XCTAssertEqual(rotor.movePlayerPositionTarget(forward: true, myPlayerID: 3, players: players), 3)
        XCTAssertEqual(rotor.movePlayerPositionTarget(forward: true, myPlayerID: 3, players: players), 4)
        XCTAssertEqual(rotor.movePlayerPositionTarget(forward: true, myPlayerID: 3, players: players), 1)
        XCTAssertEqual(rotor.movePlayerPositionTarget(forward: false, myPlayerID: 3, players: players), 4)

        // 플레이어 정보 로터의 특수 `미소유` 대상은 플레이어 위치에는 들어오지 않는다.
        XCTAssertEqual(
            rotor.playerTargets(myPlayerID: 3, players: players),
            [.player(3), .player(4), .player(1), .player(2), .unowned]
        )
    }

    func testGameRotorPlayerPositionFirstUpStartsReverseFromSelf() {
        let players = [1, 2, 3, 4].map { id in
            GamePlayerSnapshot(
                playerID: id,
                userID: id,
                nickname: "P\(id)",
                teamName: "P\(id)",
                marble: 2_000_000,
                position: id,
                lapCount: 0,
                isStranded: false,
                isBankrupt: false,
                isAI: false
            )
        }
        var rotor = GameRotorState()
        rotor.synchronizePlayers(myPlayerID: 3, players: players)

        XCTAssertEqual(rotor.movePlayerPositionTarget(forward: false, myPlayerID: 3, players: players), 2)
        XCTAssertEqual(rotor.movePlayerPositionTarget(forward: false, myPlayerID: 3, players: players), 1)
        XCTAssertEqual(rotor.movePlayerPositionTarget(forward: true, myPlayerID: 3, players: players), 2)
    }

    func testGameRotorCategoryAndChildCyclesAreDeterministic() {
        var rotor = GameRotorState()
        XCTAssertEqual(rotor.category, .playerInformation)
        XCTAssertEqual(GameRotorCategory.allCases.map(\.displayName), [
            "플레이어 정보",
            "독점 정보",
            "도시 상태",
            "건물별 비용",
            "비용 및 설명",
            "플레이어 위치",
        ])
        XCTAssertEqual(rotor.moveCategoryForward(), .monopolyInformation)
        XCTAssertEqual(rotor.moveCategoryForward(), .cityStatusInformation)
        XCTAssertEqual(rotor.moveCategoryForward(), .unitCostInformation)
        XCTAssertEqual(rotor.moveCategoryForward(), .cityInformation)
        XCTAssertEqual(rotor.moveCategoryForward(), .playerPositionInformation)
        XCTAssertEqual(rotor.moveCategoryForward(), .playerInformation)
        XCTAssertEqual(rotor.moveCategoryBackward(), .playerPositionInformation)

        rotor.reset()
        XCTAssertEqual(rotor.category, .playerInformation)
        XCTAssertEqual(rotor.moveCityInformationKind(forward: true), .toll)
        XCTAssertEqual(rotor.moveCityInformationKind(forward: true), .acquisition)
        XCTAssertEqual(rotor.moveCityInformationKind(forward: true), .sale)
        XCTAssertEqual(rotor.moveCityInformationKind(forward: true), .description)
        XCTAssertEqual(rotor.moveCityInformationKind(forward: true), .toll)
        rotor.resetCityInformationSelection()
        XCTAssertEqual(rotor.moveCityInformationKind(forward: false), .description)

        XCTAssertEqual(rotor.moveMonopolyKind(forward: true), .endingAlert)
        XCTAssertEqual(rotor.moveMonopolyKind(forward: true), .achieved)
        XCTAssertEqual(rotor.moveCityStatusKind(forward: true), .olympic)
        XCTAssertEqual(rotor.moveCityStatusKind(forward: true), .activeEffect)
        XCTAssertEqual(rotor.moveCityStatusKind(forward: true), .festival)
    }

    func testGameRotorUnitCostUsesServerTypeOrderAndDownMeansForward() {
        var rotor = GameRotorState()
        let types = ["땅", "빌라", "빌딩"]
        XCTAssertEqual(rotor.currentUnitBuildingType(availableTypes: types), "땅")
        XCTAssertEqual(rotor.moveUnitBuildingType(forward: true, availableTypes: types), "빌라")
        XCTAssertEqual(rotor.moveUnitBuildingType(forward: false, availableTypes: types), "땅")

        rotor.resetUnitBuildingSelection()
        XCTAssertEqual(rotor.moveUnitValueKind(forward: true), .buildCost)
        XCTAssertEqual(rotor.moveUnitValueKind(forward: true), .tollValue)
        XCTAssertEqual(rotor.moveUnitValueKind(forward: false), .buildCost)

        rotor.resetUnitBuildingSelection()
        XCTAssertEqual(rotor.moveUnitValueKind(forward: false), .sellValue)
    }

    private func presentationContextForAudioTests() -> GamePresentationContext {
        let players = [
            GamePlayerSnapshot(
                playerID: 1, userID: 10, nickname: "나", teamName: "나",
                marble: 2_000_000, position: 1, lapCount: 0,
                isStranded: false, isBankrupt: false, isAI: false
            ),
            GamePlayerSnapshot(
                playerID: 2, userID: nil, nickname: "AI돌이", teamName: "AI돌이",
                marble: 2_000_000, position: 1, lapCount: 0,
                isStranded: false, isBankrupt: false, isAI: true
            ),
        ]
        let cells = [
            BoardCellSnapshot(index: 1, name: "출발", cellType: "START", cityID: nil, cityType: nil, group: nil, basePrice: 0, row: 8, column: 8),
            BoardCellSnapshot(index: 2, name: "방콕", cellType: "CITY", cityID: 1, cityType: "NORMAL", group: "연두", basePrice: 50_000, row: 8, column: 7),
            BoardCellSnapshot(index: 8, name: "세계여행", cellType: "WORLD_TRAVEL", cityID: nil, cityType: nil, group: nil, basePrice: 0, row: 8, column: 1),
        ]
        return GamePresentationContext(
            localPlayerID: 1,
            players: players,
            boardCatalog: BoardCatalogSnapshot(cells: cells),
            cities: [GameCityStateSnapshot(cityID: 1, cityName: "방콕", ownerID: 1, buildings: ["빌라"], cityEffectTypes: [])]
        )
    }

    func testPresentationTurnStartedMatchesPCRecordedVoiceContract() throws {
        let plan = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "turn_started",
            payload: ["player_id": 1],
            context: presentationContextForAudioTests()
        ))
        XCTAssertEqual(plan.persistentNotice, "당신 차례")
        XCTAssertEqual(plan.category, .gameplay)
        XCTAssertEqual(plan.interruptRetention, .preservePending)
        guard case .parallel(let nodes) = plan.root else { return XCTFail("parallel expected") }
        XCTAssertTrue(nodes.contains(.sfx(clip: "turn_end.wav", completion: .wait)))
        XCTAssertTrue(nodes.contains(.voice(clip: "my_turn.wav", fallbackTTS: "당신 차례")))
    }

    func testPresentationArrivedSequencesDiceMoveAndArrivalSpeech() throws {
        let plan = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "arrived",
            payload: ["player_id": 2, "to_index": 2, "die1": 3, "die2": 4, "is_double": false],
            context: presentationContextForAudioTests()
        ))
        XCTAssertEqual(plan.persistentNotice, "[AI돌이] 7 → 방콕")
        guard case .sequence(let nodes) = plan.root else { return XCTFail("sequence expected") }
        XCTAssertEqual(nodes.first, .sfx(clip: "dice_roll.wav", completion: .wait))
        XCTAssertTrue(nodes.contains(.voice(clip: "dice_7.wav", fallbackTTS: "[AI돌이] 7")))
        XCTAssertTrue(nodes.contains(.sfx(clip: "move_step_7.wav", completion: .wait)))
        XCTAssertTrue(nodes.contains(.tts("[AI돌이] 방콕")))
    }

    func testPresentationTollUsesLocalMoneyDirectionSFX() throws {
        let context = presentationContextForAudioTests()
        let paid = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "toll_paid",
            payload: ["player_id": 1, "owner_id": 2, "amount": 120_000],
            context: context
        ))
        XCTAssertEqual(paid.persistentNotice, "당신 AI돌이에게 통행료 120,000마블 지불")
        guard case .parallel(let paidNodes) = paid.root else { return XCTFail("parallel expected") }
        XCTAssertTrue(paidNodes.contains(.sfx(clip: "money_out.wav", completion: .wait)))

        let received = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "toll_paid",
            payload: ["player_id": 2, "owner_id": 1, "amount": 120_000],
            context: context
        ))
        guard case .parallel(let receivedNodes) = received.root else { return XCTFail("parallel expected") }
        XCTAssertTrue(receivedNodes.contains(.sfx(clip: "money_in.wav", completion: .wait)))
    }

    func testPresentationCityPurchaseUsesCanonicalPCMessage() throws {
        let plan = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "city_purchased",
            payload: ["player_id": 2, "city_id": 1, "cost": 50_000],
            context: presentationContextForAudioTests()
        ))
        XCTAssertEqual(plan.persistentNotice, "AI돌이가 방콕을 50,000마블에 구매했습니다")
        XCTAssertEqual(plan.root, .tts("AI돌이가 방콕을 50,000마블에 구매했습니다"))
    }

    func testPresentationGameOverStopsBGMAndUsesWinningSFXForLocalWinner() throws {
        let plan = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "game_over",
            payload: ["winner_player_id": 1, "achievements": [], "is_last_survivor": true],
            context: presentationContextForAudioTests()
        ))
        XCTAssertEqual(plan.persistentNotice, "당신 승리: 최후의 1인")
        guard case .parallel(let nodes) = plan.root else { return XCTFail("parallel expected") }
        XCTAssertTrue(nodes.contains(.bgmStop))
        XCTAssertTrue(nodes.contains(.sfx(clip: "winning.wav", completion: .wait)))
        XCTAssertTrue(nodes.contains(.tts("당신 승리: 최후의 1인")))
    }

    func testGameStateCityParserRetainsOwnershipForPresentationReactions() throws {
        let payload = try roundTripJSON([
            "type": "game_state",
            "current_player_id": 1,
            "players": [[
                "player_id": 1, "nickname": "사용자", "team_name": "사용자",
                "marble": 2_000_000, "position": 1, "lap_count": 0,
                "connection_status": "connected", "is_ai": false,
            ]],
            "cities": [[
                "city_id": 1, "city_name": "방콕", "buildings": ["빌라"],
                "group_name": "연두", "is_color_monopoly": false,
                "has_olympic": false, "olympic_count": 0,
                "city_effect_types": [], "is_festival": false,
                "owner_id": 1, "owner_nickname": "사용자",
            ]],
        ])
        let state = try GameplayParser.gameState(payload)
        XCTAssertEqual(state.cities.count, 1)
        XCTAssertEqual(state.cities[0].cityID, 1)
        XCTAssertEqual(state.cities[0].ownerID, 1)
        XCTAssertEqual(state.cities[0].buildings, ["빌라"])
    }


    func testInteractionPresentationFortunePreludeUsesCardSelectionAndReactionAudio() throws {
        let plan = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "interaction_presentation",
            payload: [
                "player_id": 1,
                "request_id": "req-fortune",
                "action_type": "fortune_card",
                "interaction_type": "acknowledge",
                "payload": [
                    "mission_type": "fortune_card",
                    "card_id": "move_tax_1",
                ],
            ],
            context: presentationContextForAudioTests()
        ))
        XCTAssertNil(plan.persistentNotice)
        guard case .parallel(let nodes) = plan.root else { return XCTFail("parallel expected") }
        XCTAssertTrue(nodes.contains(.sfx(clip: "card_sellection.wav", completion: .wait)))
        XCTAssertTrue(nodes.contains(.voice(clip: "ah.wav", fallbackTTS: nil)))
    }

    func testInteractionPresentationAttackAndDefensePreludesMatchPCClips() throws {
        let context = presentationContextForAudioTests()
        let attack = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "interaction_presentation",
            payload: [
                "interaction_type": "select_one_per_group",
                "payload": [
                    "mission_type": "fortune_selection",
                    "groups": [["role": "attack_city"]],
                ],
            ],
            context: context
        ))
        XCTAssertEqual(attack.root, .voice(clip: "attack_area.wav", fallbackTTS: nil))

        let defense = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "interaction_presentation",
            payload: ["interaction_type": "confirm", "payload": ["mission_type": "defense"]],
            context: context
        ))
        XCTAssertEqual(defense.root, .voice(clip: "defence_card.wav", fallbackTTS: nil))
    }

    func testWorldTravelActivationStartsSelectionVoiceAndAirplaneBGM() throws {
        let plan = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "interaction_presentation_activated",
            payload: ["action_type": "world_travel_destination", "first_activation": true],
            context: presentationContextForAudioTests()
        ))
        guard case .sequence(let nodes) = plan.root else { return XCTFail("sequence expected") }
        guard case .parallel(let opening) = nodes.first else { return XCTFail("parallel opening expected") }
        XCTAssertTrue(opening.contains(.voice(clip: "select_area.wav", fallbackTTS: nil)))
        XCTAssertTrue(opening.contains(.bgmPlay(clip: "airplane.mp3", loop: true)))
        XCTAssertTrue(nodes.contains(.tts("목적지를 선택하고 두 손가락으로 두 번 탭하세요.")))
    }

    func testPresentationAlienInvasionBatchIsGroupedOnceLikePC() throws {
        let context = presentationContextForAudioTests()
        let primary = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "building_destroyed",
            payload: [
                "city_id": 1,
                "building_type": "villa",
                "attack_type": "alien_invasion",
                "attacker_player_id": 2,
                "attack_effect_primary": true,
                "attack_batch_items": [
                    ["city_id": 1, "building_type": "villa"],
                    ["city_id": 1, "building_type": "hotel"],
                ],
            ],
            context: context
        ))
        XCTAssertEqual(primary.persistentNotice, "AI돌이의 외계인 침공 공격으로 방콕 빌라, 방콕 호텔 파괴")
        guard case .parallel(let nodes) = primary.root else { return XCTFail("parallel expected") }
        XCTAssertTrue(nodes.contains(.sfx(clip: "destruction.wav", completion: .wait)))
        XCTAssertTrue(nodes.contains(.sequence([.voice(clip: "oh_no.wav", fallbackTTS: nil), .tts("AI돌이의 외계인 침공 공격으로 방콕 빌라, 방콕 호텔 파괴")])))

        XCTAssertNil(GameNotificationPresenter.build(
            notificationType: "building_destroyed",
            payload: [
                "city_id": 1,
                "building_type": "hotel",
                "attack_type": "alien_invasion",
                "attacker_player_id": 2,
                "attack_effect_primary": false,
                "attack_batch_items": [["city_id": 1, "building_type": "villa"]],
            ],
            context: context
        ))
    }

    func testPresentationPlagueBatchActivationAndReleaseAreGroupedOnceLikePC() throws {
        let context = presentationContextForAudioTests()
        let activated = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "city_effect_activated",
            payload: [
                "city_id": 1,
                "effect_type": "plague",
                "caused_by_player_id": 2,
                "effect_batch_city_ids": [1],
                "effect_batch_primary": true,
            ],
            context: context
        ))
        XCTAssertEqual(activated.persistentNotice, "AI돌이의 전염병 공격으로 방콕 통행료 50퍼센트 하락")
        XCTAssertEqual(activated.root, .sequence([
            .voice(clip: "oh_no.wav", fallbackTTS: nil),
            .tts("AI돌이의 전염병 공격으로 방콕 통행료 50퍼센트 하락"),
        ]))
        XCTAssertNil(GameNotificationPresenter.build(
            notificationType: "city_effect_activated",
            payload: [
                "city_id": 1, "effect_type": "plague", "caused_by_player_id": 2,
                "effect_batch_city_ids": [1], "effect_batch_primary": false,
            ],
            context: context
        ))

        let released = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "city_effect_released",
            payload: [
                "city_id": 1, "effect_type": "plague",
                "effect_batch_city_ids": [1], "effect_batch_primary": true,
            ],
            context: context
        ))
        XCTAssertEqual(released.persistentNotice, "방콕의 전염병 해제")
        XCTAssertNil(GameNotificationPresenter.build(
            notificationType: "city_effect_released",
            payload: [
                "city_id": 1, "effect_type": "plague",
                "effect_batch_city_ids": [1], "effect_batch_primary": false,
            ],
            context: context
        ))
    }

    func testPresentationLastSurvivorLossDoesNotReplayLosingSFXAtGameOver() throws {
        let plan = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "game_over",
            payload: ["winner_player_id": 2, "achievements": [], "is_last_survivor": true],
            context: presentationContextForAudioTests()
        ))
        XCTAssertEqual(plan.persistentNotice, "AI돌이 승리: 최후의 1인")
        guard case .parallel(let nodes) = plan.root else { return XCTFail("parallel expected") }
        XCTAssertTrue(nodes.contains(.bgmStop))
        XCTAssertFalse(nodes.contains(.sfx(clip: "losing.wav", completion: .wait)))
        XCTAssertTrue(nodes.contains(.tts("AI돌이 승리: 최후의 1인")))
    }

    func testPresentationRollDiceRejectedUsesPCReasonTextAndPlayerPrefix() throws {
        let plan = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "roll_dice_rejected",
            payload: ["player_id": 2, "reason_code": "turn_preparation_conflict"],
            context: presentationContextForAudioTests()
        ))
        XCTAssertEqual(plan.persistentNotice, "AI돌이 보석금과 무인도 탈출 카드를 동시에 사용할 수 없습니다.")
        XCTAssertEqual(plan.root, .tts("AI돌이 보석금과 무인도 탈출 카드를 동시에 사용할 수 없습니다."))
    }

    func testCanonicalGameEventUsesSameMessageForPersistentTextAndDefaultTTS() {
        let plan = PresentationPlan.gameEvent("같은 게임 메시지")
        XCTAssertEqual(plan.persistentNotice, "같은 게임 메시지")
        XCTAssertEqual(plan.root, .tts("같은 게임 메시지"))
        XCTAssertEqual(plan.interruptRetention, .preservePending)
    }

    func testPresentationUnknownNotificationDoesNotInventMessageFallback() {
        let plan = GameNotificationPresenter.build(
            notificationType: "future_unknown_event",
            payload: ["message": "서버 임의 문구"],
            context: presentationContextForAudioTests()
        )
        XCTAssertNil(plan)
    }

    func testLiquidationPresentationIncludesCommonCityDTOAndFullPaymentContext() throws {
        let raw = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-l2", "request_id": "req-l2",
            "action_type": "liquidation", "interaction_type": "select_multiple", "cancellable": false,
            "payload": [
                "mission_type": "liquidation", "required_amount": 500_000, "current_marble": 100_000,
                "items": [[
                    "id": "7", "city_id": 7, "city_name": "서울", "group": "빨강",
                    "buildings": ["빌라", "호텔"], "sell_value": 450_000, "disabled": false,
                ]],
            ],
        ])
        let request = try InteractionRequestParser.parse(raw)
        XCTAssertEqual(request.items.first?.information?.cityName, "서울")
        XCTAssertEqual(request.items.first?.information?.groupName, "빨강")

        let city = InformationInfo(
            cityID: 7,
            cityName: "서울",
            ownerID: 1,
            ownerNickname: "나",
            groupName: "빨강",
            buildings: ["빌라", "호텔"],
            cityEffectTypes: ["yellow_dust"],
            isColorMonopoly: true,
            isFestival: true,
            hasOlympic: true,
            olympicCount: 2
        )
        let label = InteractionCityItemPresenter.format(
            information: city,
            missionType: request.missionType,
            cost: try XCTUnwrap(request.items.first?.cost),
            myPlayerID: 1
        )
        XCTAssertTrue(label.contains("서울"))
        XCTAssertTrue(label.contains("독점"))
        XCTAssertTrue(label.contains("올림픽 2"))
        XCTAssertTrue(label.contains("황사"))
        XCTAssertTrue(label.contains("축제"))
        XCTAssertTrue(label.contains("매각 대금 450,000마블"))

        let initial = InteractionRequestPresenter.liquidationMarbleInfo(request, selectedSellValue: 0)
        XCTAssertTrue(initial.contains("보유 마블: 100,000마블"))
        XCTAssertTrue(initial.contains("필요 금액: 400,000마블"))
        XCTAssertTrue(initial.contains("총 통행료: 500,000마블"))
        XCTAssertTrue(initial.contains("매각 대금: 0마블"))
        XCTAssertTrue(initial.contains("납부 후 잔여: -400,000마블"))

        XCTAssertEqual(
            InteractionRequestPresenter.liquidationSelectionChanged(request, selectedSellValue: 300_000),
            "매각 대금 300,000마블. 부족 100,000마블"
        )
        XCTAssertEqual(
            InteractionRequestPresenter.liquidationSelectionChanged(request, selectedSellValue: 450_000),
            "매각 대금 450,000마블. 납부 가능"
        )
        XCTAssertEqual(
            InteractionRequestPresenter.liquidationShortage(request, selectedSellValue: 300_000),
            "금액이 부족합니다. 100,000마블 더 선택하세요."
        )
        XCTAssertNil(InteractionRequestPresenter.liquidationShortage(request, selectedSellValue: 450_000))
    }

    func testInteractionRequestPresenterUsesCommonCityDTOForSingleCityAndDefenseTargets() throws {
        let purchaseRaw = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-p2", "request_id": "req-p2",
            "action_type": "purchase_city", "interaction_type": "confirm", "cancellable": true,
            "payload": [
                "mission_type": "purchase_city", "city_id": 3, "city_name": "도쿄", "cost": 200_000,
            ],
        ])
        let purchase = try InteractionRequestParser.parse(purchaseRaw)
        let city = InformationInfo(
            cityID: 3,
            cityName: "도쿄",
            ownerID: nil,
            groupName: "파랑",
            buildings: [],
            cityEffectTypes: [],
            isColorMonopoly: false,
            isFestival: false,
            hasOlympic: false
        )
        let text = InteractionRequestPresenter.description(
            purchase,
            cityInformation: [3: city],
            myPlayerID: 1
        )
        XCTAssertTrue(text.contains("도쿄"))
        XCTAssertTrue(text.contains("파랑"))
        XCTAssertTrue(text.contains("미소유"))
        XCTAssertTrue(text.contains("200,000마블"))

        let defenseRaw = try roundTripJSON([
            "type": "interaction_request", "interaction_flow_id": "flow-d2", "request_id": "req-d2",
            "action_type": "defense_response", "interaction_type": "confirm", "cancellable": true,
            "payload": [
                "mission_type": "defense", "defense_type": "attack", "attack_type": "yellow_dust",
                "attacker_player_id": 2, "defense_card_name": "방어권", "city_ids": [3], "city_id": 3,
            ],
        ])
        let defense = try InteractionRequestParser.parse(defenseRaw)
        let defenseText = InteractionRequestPresenter.description(
            defense,
            cityInformation: [3: city],
            myPlayerID: 1,
            playerNicknames: [2: "AI돌이"]
        )
        XCTAssertTrue(defenseText.contains("AI돌이의 황사 공격"))
        XCTAssertTrue(defenseText.contains("도쿄"))
        XCTAssertTrue(defenseText.contains("미소유"))
        XCTAssertTrue(defenseText.contains("방어권 카드로 방어하시겠습니까?"))
    }

}


extension Phase1CoreTests {
    func testAIRemainderOutputPolicyMatchesPCBoundary() {
        func player(_ id: Int, ai: Bool, bankrupt: Bool) -> GamePlayerSnapshot {
            GamePlayerSnapshot(
                playerID: id,
                userID: ai ? nil : id,
                nickname: "P\(id)",
                teamName: "",
                marble: 0,
                position: 1,
                lapCount: 0,
                isStranded: false,
                isBankrupt: bankrupt,
                isAI: ai
            )
        }

        XCTAssertFalse(AIRemainderOutputPolicy.shouldSuppressGameplayAudio(
            players: [player(1, ai: false, bankrupt: false), player(2, ai: true, bankrupt: false)],
            gameInProgress: true
        ))
        XCTAssertTrue(AIRemainderOutputPolicy.shouldSuppressGameplayAudio(
            players: [
                player(1, ai: false, bankrupt: true),
                player(2, ai: false, bankrupt: true),
                player(3, ai: true, bankrupt: false),
                player(4, ai: true, bankrupt: true),
            ],
            gameInProgress: true
        ))
        XCTAssertFalse(AIRemainderOutputPolicy.shouldSuppressGameplayAudio(
            players: [player(1, ai: false, bankrupt: true), player(2, ai: true, bankrupt: true)],
            gameInProgress: true
        ))
        XCTAssertFalse(AIRemainderOutputPolicy.shouldSuppressGameplayAudio(
            players: [player(1, ai: false, bankrupt: true), player(2, ai: true, bankrupt: false)],
            gameInProgress: false
        ))
    }
}


extension Phase1CoreTests {
    func testMainMenuDefinitionMatchesClient393StructureWithoutPCShortcuts() {
        XCTAssertEqual(MainMenuDefinition.sections.map(\.title), ["파일", "동작", "설정"])
        XCTAssertEqual(
            MainMenuDefinition.sections[0].groups,
            [
                [.login, .logout],
                [.notes, .friends, .ranking, .gameRecords],
                [.exit, .leaveRoom],
            ]
        )
        XCTAssertEqual(
            MainMenuDefinition.sections[1].groups,
            [[.startGame, .showLobby, .participateRoom, .roomInfo, .myProfile, .roomManagement]]
        )
        XCTAssertEqual(
            MainMenuDefinition.sections[2].groups,
            [[.mediaManagement], [.receiveSettings]]
        )

        let allTitles = MainMenuDefinition.sections.flatMap(\.groups).flatMap { $0 }.map(MainMenuDefinition.title)
        XCTAssertEqual(
            allTitles,
            [
                "로그인", "로그아웃",
                "쪽지함", "친구 관리", "순위 보기", "게임 기록",
                "종료", "퇴장",
                "게임 시작", "대기실 열기", "게임방 참여", "방 정보", "내 정보", "방 관리",
                "미디어 관리", "수신 설정",
            ]
        )
        XCTAssertFalse(allTitles.contains { $0.contains("F4") || $0.contains("Ctrl") || $0.contains("Alt") || $0.contains("&") })
    }
}

extension Phase1CoreTests {
    func testLobbyUserMenuKeepsClient393OrderWhileMobileUnimplementedActionsAreDisabled() {
        let state = SocialState(friends: [.init(userID: 2, nickname: "강")])
        let actions = LobbyActionBuilder.userActions(
            targetUserID: 2,
            currentUserID: 1,
            socialState: state,
            hasGameRoom: true,
            isSpectator: false,
            messageImplemented: false,
            noteImplemented: false,
            roomInvitationImplemented: false,
            spectatorInvitationImplemented: false,
            socialInteractionImplemented: false
        )

        XCTAssertEqual(
            actions.map(\.title),
            ["메시지 보내기", "쪽지 보내기", "초대하기", "관중석으로 초대", "친구 해제", "차단", "사용자 정보"]
        )
        XCTAssertEqual(actions.map(\.isEnabled), [false, false, false, false, false, false, true])
    }

    func testLobbyRoomMenuKeepsAllClient393ItemsWithCurrentImplementationState() {
        let actions = LobbyActionBuilder.roomActions(
            roomCreationImplemented: true,
            roomJoinImplemented: true,
            spectatorInteractionImplemented: false
        )
        XCTAssertEqual(
            actions.map(\.title),
            ["방 개설", "참여하기", "관중석 입장", "방 정렬", "방 정보"]
        )
        XCTAssertEqual(actions.map(\.isEnabled), [true, true, false, false, true])
    }

    func testLobbyRoomMenuKeepsSameCanonicalItemsWithoutRoomTarget() {
        let actions = LobbyActionBuilder.roomActions(
            roomCreationImplemented: true,
            roomJoinImplemented: true,
            spectatorInteractionImplemented: false,
            hasRoomTarget: false
        )
        XCTAssertEqual(
            actions.map(\.title),
            ["방 개설", "참여하기", "관중석 입장", "방 정렬", "방 정보"]
        )
        XCTAssertEqual(actions.map(\.isEnabled), [true, false, false, false, false])
    }
    func testGameRotorBoardCellResetPreservesCategoryTargetAndTraversalContext() {
        let players = [1, 2].map { id in
            GamePlayerSnapshot(
                playerID: id,
                userID: id,
                nickname: id == 1 ? "나" : "상대",
                teamName: id == 1 ? "나" : "상대",
                marble: 2_000_000,
                position: id,
                lapCount: 0,
                isStranded: false,
                isBankrupt: false,
                isAI: false
            )
        }
        var rotor = GameRotorState()
        rotor.synchronizePlayers(myPlayerID: 1, players: players)
        XCTAssertEqual(rotor.category, .playerInformation)
        XCTAssertEqual(rotor.movePlayerTarget(forward: true, myPlayerID: 1, players: players), .player(2))
        XCTAssertEqual(rotor.nextOpponentCityIndex(forward: true), 0)

        _ = rotor.moveCategoryForward() // 독점 정보
        _ = rotor.moveCategoryForward() // 도시 상태
        _ = rotor.moveCategoryForward() // 건물별 비용
        _ = rotor.moveCategoryForward() // 비용 및 설명
        XCTAssertEqual(rotor.category, .cityInformation)
        _ = rotor.moveCityInformationKind(forward: true)
        _ = rotor.moveUnitBuildingType(forward: true, availableTypes: ["villa", "building"])

        rotor.resetBoardCellSelections()

        XCTAssertEqual(rotor.category, .cityInformation)
        XCTAssertEqual(rotor.playerTarget, .player(2))
        XCTAssertEqual(rotor.nextOpponentCityIndex(forward: true), 1)
        XCTAssertEqual(rotor.cityInformationKind, .toll)
        XCTAssertNil(rotor.unitBuildingType)
    }


    func testSpectatorWireMessagesMatchServer678Contract() {
        XCTAssertEqual(
            WireMessages.getSpectatorTargets(roomID: 7) as NSDictionary,
            ["type": "get_spectator_targets", "room_id": 7] as NSDictionary
        )

        let publicJoin = WireMessages.joinSpectator(roomID: 7, observedUserID: 30)
        XCTAssertEqual(
            publicJoin as NSDictionary,
            ["type": "join_spectator", "room_id": 7, "observed_user_id": 30] as NSDictionary
        )

        let privateJoin = WireMessages.joinSpectator(
            roomID: 7,
            observedUserID: 30,
            password: " secret "
        )
        XCTAssertEqual(privateJoin["password"] as? String, " secret ")
        XCTAssertNil(WireMessages.joinSpectator(
            roomID: 7,
            observedUserID: 30,
            password: "   "
        )["password"])
        XCTAssertEqual(WireMessages.leaveSpectator() as NSDictionary, ["type": "leave_spectator"] as NSDictionary)
    }

    func testSpectatorParsersUseObservedUserIdentityAndPreserveServerOrder() throws {
        let list = try SpectatorParser.targetList([
            "type": "spectator_target_list",
            "room_id": 7,
            "players": [
                ["observed_user_id": 30, "nickname": "삼십"],
                ["observed_user_id": 10, "nickname": "십"],
                ["observed_user_id": 20, "nickname": "이십"],
            ],
        ])
        XCTAssertEqual(list.roomID, 7)
        XCTAssertEqual(list.targets.map(\.observedUserID), [30, 10, 20])
        XCTAssertEqual(list.targets.map(\.nickname), ["삼십", "십", "이십"])

        let joined = try SpectatorParser.joined([
            "type": "spectator_joined",
            "room_id": 7,
            "observed_user_id": 30,
            "observed_user_nickname": "삼십",
        ])
        XCTAssertEqual(joined, .init(roomID: 7, observedUserID: 30, observedUserNickname: "삼십"))

        let left = try SpectatorParser.left([
            "type": "spectator_left",
            "room_id": 7,
            "observed_user_id": 30,
            "lifecycle_event": "spectator_left",
            "actor_user_id": 99,
            "actor_nickname": "관전자",
            "sound_event": "leave",
        ])
        XCTAssertEqual(left, .init(roomID: 7, observedUserID: 30))
    }

    func testSpectatorParserRejectsDuplicateOrBooleanObservedUserID() {
        XCTAssertThrowsError(try SpectatorParser.targetList([
            "type": "spectator_target_list",
            "room_id": 7,
            "players": [
                ["observed_user_id": 30, "nickname": "삼십"],
                ["observed_user_id": 30, "nickname": "중복"],
            ],
        ]))
        XCTAssertThrowsError(try SpectatorParser.joined([
            "type": "spectator_joined",
            "room_id": 7,
            "observed_user_id": true,
            "observed_user_nickname": "잘못",
        ]))
    }

    func testGameStateParsesSpectatorSceneFactsWithoutPrivateInteractionState() throws {
        let payload = try roundTripJSON([
            "type": "game_state",
            "current_player_id": 2,
            "world_travel_selection_player_id": 2,
            "game_lifecycle": "finished",
            "players": [[
                "player_id": 2, "user_id": 30, "nickname": "관전 대상", "team_name": "대상",
                "marble": 2_000_000, "position": 8, "lap_count": 0,
                "connection_status": "connected", "is_ai": false,
            ]],
            "cities": [],
        ])
        let state = try GameplayParser.gameState(payload)
        XCTAssertEqual(state.players.first?.userID, 30)
        XCTAssertEqual(state.worldTravelSelectionPlayerID, 2)
        XCTAssertEqual(state.gameLifecycle, "finished")
    }

    func testSpectatorPresentationKeepsObjectiveTextButUsesObservedAudioPerspective() throws {
        let base = presentationContextForAudioTests()
        let context = GamePresentationContext(
            localPlayerID: nil,
            presentationPlayerID: 1,
            players: base.players,
            boardCatalog: base.boardCatalog,
            cities: base.cities
        )

        let turn = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "turn_started",
            payload: ["player_id": 1],
            context: context
        ))
        XCTAssertEqual(turn.persistentNotice, "나 차례")
        guard case .parallel(let turnNodes) = turn.root else { return XCTFail("parallel expected") }
        XCTAssertTrue(turnNodes.contains(.voice(clip: "my_turn.wav", fallbackTTS: "나 차례")))

        let toll = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "toll_paid",
            payload: ["player_id": 1, "owner_id": 2, "amount": 120_000],
            context: context
        ))
        XCTAssertEqual(toll.persistentNotice, "나 AI돌이에게 통행료 120,000마블 지불")
        guard case .parallel(let tollNodes) = toll.root else { return XCTFail("parallel expected") }
        XCTAssertTrue(tollNodes.contains(.sfx(clip: "money_out.wav", completion: .wait)))
    }

    func testSpectatorPresentationUsesObservedPerspectiveWithoutParticipantSelfWording() throws {
        let players = [
            GamePlayerSnapshot(
                playerID: 1, userID: 30, nickname: "경석", teamName: "경석",
                marble: 2_000_000, position: 8, lapCount: 0,
                isStranded: false, isBankrupt: false, isAI: false
            ),
            GamePlayerSnapshot(
                playerID: 2, userID: 40, nickname: "민수", teamName: "민수",
                marble: 2_000_000, position: 1, lapCount: 0,
                isStranded: false, isBankrupt: false, isAI: false
            ),
        ]
        let context = GamePresentationContext(
            localPlayerID: nil,
            presentationPlayerID: 1,
            players: players,
            boardCatalog: nil,
            cities: [
                GameCityStateSnapshot(
                    cityID: 1,
                    cityName: "방콕",
                    ownerID: 1,
                    buildings: ["빌라"],
                    cityEffectTypes: []
                ),
            ]
        )

        let forceSold = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "city_force_sold",
            payload: [
                "attacker_player_id": 2,
                "owner_player_id": 1,
                "city_id": 1,
                "sell_value": 110_000,
            ],
            context: context
        ))
        XCTAssertEqual(forceSold.persistentNotice, "민수가 경석의 방콕을 강제 매각했습니다. 경석이 매각 대금으로 110,000마블을 받았습니다")
        guard case .sequence(let forceNodes) = forceSold.root else { return XCTFail("sequence expected") }
        XCTAssertEqual(forceNodes.first, .voice(clip: "oh_no.wav", fallbackTTS: nil))

        let paid = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "sponsorship_paid",
            payload: ["payer_player_id": 1, "receiver_player_id": 2],
            context: context
        ))
        XCTAssertEqual(paid.persistentNotice, "경석 후원금으로 민수에게 10만 마블을 주었습니다.")

        let received = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "sponsorship_received",
            payload: ["receiver_player_id": 1, "total_amount": 100_000],
            context: context
        ))
        XCTAssertEqual(received.persistentNotice, "경석이 후원금으로 모두에게서 10만 마블씩 받았습니다.")

        let noSponsorship = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "sponsorship_received",
            payload: ["receiver_player_id": 1, "total_amount": 0],
            context: context
        ))
        XCTAssertEqual(noSponsorship.persistentNotice, "경석이 받을 수 있는 후원금이 없습니다.")

        let worldTravel = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "world_travel_started",
            payload: ["player_id": 1, "cost": 100_000],
            context: context
        ))
        XCTAssertEqual(worldTravel.persistentNotice, "경석 세계여행 비용 100,000마블 지불")
        guard case .sequence(let travelNodes) = worldTravel.root else { return XCTFail("sequence expected") }
        XCTAssertEqual(travelNodes, [
            .tts("경석 세계여행 비용 100,000마블 지불"),
            .tts("다음 턴에 목적지로 이동하세요."),
        ])

        let stranded = try XCTUnwrap(GameNotificationPresenter.build(
            notificationType: "player_stranded",
            payload: ["player_id": 1],
            context: context
        ))
        XCTAssertEqual(
            stranded.persistentNotice,
            "경석이 무인도에 갇혔습니다. 3턴 안에 더블이나 보석금(H) 또는 탈출 카드(Y)로 탈출할 수 있습니다."
        )
    }

    func testRoomEventFormatterSupportsSpectatorLifecycleMeaning() {
        XCTAssertEqual(
            RoomEventFormatter.message(from: [
                "type": "room_event",
                "event": "spectator_entered",
                "actor_user_id": 99,
                "actor_nickname": "관전자",
                "observed_user_id": 30,
                "observed_nickname": "대상",
            ]),
            "관전자가 대상의 관중석으로 입장했습니다."
        )
        XCTAssertEqual(
            RoomEventFormatter.message(from: [
                "type": "spectator_left",
                "lifecycle_event": "spectator_left",
                "actor_user_id": 99,
                "actor_nickname": "관전자",
            ], eventKey: "lifecycle_event"),
            "관전자가 퇴장했습니다."
        )
    }

    func testLobbyRoomMenuCanEnableSpectatorEntryWithoutChangingCanonicalOrder() {
        let actions = LobbyActionBuilder.roomActions(
            roomCreationImplemented: true,
            roomJoinImplemented: true,
            spectatorInteractionImplemented: true
        )
        XCTAssertEqual(
            actions.map(\.title),
            ["방 개설", "참여하기", "관중석 입장", "방 정렬", "방 정보"]
        )
        XCTAssertEqual(actions.map(\.isEnabled), [true, true, true, false, true])
    }

}

extension Phase1CoreTests {
    func testInvitationWireMessagesMatchServer678Contract() {
        XCTAssertEqual(
            WireMessages.invitationSend(targetUserID: 7, inviteType: .room) as NSDictionary,
            ["type": "invitation_send", "target_user_id": 7, "invite_type": "room"] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.invitationSend(targetUserID: 8, inviteType: .spectator) as NSDictionary,
            ["type": "invitation_send", "target_user_id": 8, "invite_type": "spectator"] as NSDictionary
        )
        XCTAssertEqual(
            WireMessages.invitationAccept(inviteID: 19) as NSDictionary,
            ["type": "invitation_accept", "invite_id": 19] as NSDictionary
        )
    }

    func testRoomInvitationParsingAndLabelMatchClient393() throws {
        let invitation = try InvitationParser.received([
            "type": "invitation_received",
            "invite_id": 11,
            "invite_type": "room",
            "inviter": ["user_id": 2, "nickname": "민수"],
            "room": ["room_id": 7, "title": "친선전", "is_private": true],
        ])
        XCTAssertEqual(invitation.inviteID, 11)
        XCTAssertEqual(invitation.inviteType, .room)
        XCTAssertNil(invitation.spectatorTarget)
        XCTAssertEqual(invitation.listLabel, "민수 - 7번 친선전 방으로 초대")
    }

    func testSpectatorInvitationParsingPreservesObservedUserCapability() throws {
        let invitation = try InvitationParser.received([
            "type": "invitation_received",
            "invite_id": 12,
            "invite_type": "spectator",
            "inviter": ["user_id": 2, "nickname": "민수"],
            "room": ["room_id": 7, "title": "친선전", "is_private": true],
            "spectator_target": ["observed_user_id": 5, "nickname": "경석"],
        ])
        XCTAssertEqual(invitation.inviteType, .spectator)
        XCTAssertEqual(invitation.spectatorTarget, .init(observedUserID: 5, nickname: "경석"))
        XCTAssertEqual(invitation.listLabel, "민수 - 7번 친선전 방 관중석으로 초대")
    }

    func testInvitationParserRejectsMalformedOrMismatchedPayloads() {
        XCTAssertThrowsError(try InvitationParser.received([
            "type": "invitation_received",
            "invite_id": 1,
            "invite_type": "spectator",
            "inviter": ["user_id": 2, "nickname": "민수"],
            "room": ["room_id": 7, "title": "친선전", "is_private": true],
        ]))
        XCTAssertThrowsError(try InvitationParser.received([
            "type": "invitation_received",
            "invite_id": 1,
            "invite_type": "room",
            "inviter": ["user_id": 2, "nickname": "민수"],
            "room": ["room_id": 7, "title": "친선전", "is_private": 1],
        ]))
        XCTAssertThrowsError(try InvitationParser.received([
            "type": "invitation_received",
            "invite_id": 1,
            "invite_type": "room",
            "inviter": ["user_id": 2, "nickname": "민수"],
            "room": ["room_id": 7, "title": "친선전", "is_private": false],
            "spectator_target": ["observed_user_id": 5, "nickname": "경석"],
        ]))
    }

    func testRepeatedInvitationIdentityReplacesOnlySameSenderRoomAndType() {
        let first = GameInvitation(
            inviteID: 1,
            inviteType: .room,
            inviter: .init(userID: 2, nickname: "민수"),
            room: .init(roomID: 7, title: "친선전", isPrivate: false)
        )
        let replacement = GameInvitation(
            inviteID: 2,
            inviteType: .room,
            inviter: .init(userID: 2, nickname: "민수"),
            room: .init(roomID: 7, title: "친선전", isPrivate: false)
        )
        let spectator = GameInvitation(
            inviteID: 3,
            inviteType: .spectator,
            inviter: .init(userID: 2, nickname: "민수"),
            room: .init(roomID: 7, title: "친선전", isPrivate: false),
            spectatorTarget: .init(observedUserID: 2, nickname: "민수")
        )
        XCTAssertTrue(replacement.replaces(first))
        XCTAssertFalse(spectator.replaces(first))
    }

    func testInvitationSentAndConsumedParsingMatchServer678() throws {
        let sent = try InvitationParser.sent([
            "type": "invitation_sent",
            "invite_id": 21,
            "invite_type": "spectator",
            "target_user_id": 8,
            "target_nickname": "경석",
            "room_id": 7,
            "room_title": "친선전",
        ])
        XCTAssertEqual(sent.inviteType, .spectator)
        XCTAssertEqual(sent.targetNickname, "경석")

        let consumed = try InvitationParser.consumed([
            "type": "invitation_consumed",
            "invite_id": 21,
            "invite_type": "spectator",
            "room_id": 7,
        ])
        XCTAssertEqual(consumed.inviteID, 21)
        XCTAssertEqual(consumed.roomID, 7)
    }
}

extension Phase1CoreTests {
    func testInvitationMenuAvailabilityMatchesClient393ParticipantAndSpectatorContexts() throws {
        let participant = LobbyActionBuilder.userActions(
            targetUserID: 2,
            currentUserID: 1,
            socialState: .init(),
            hasGameRoom: true,
            isSpectator: false
        )
        XCTAssertTrue(try XCTUnwrap(participant.first(where: { $0.kind == .roomInvite })).isEnabled)
        XCTAssertTrue(try XCTUnwrap(participant.first(where: { $0.kind == .spectatorInvite })).isEnabled)

        let spectator = LobbyActionBuilder.userActions(
            targetUserID: 2,
            currentUserID: 1,
            socialState: .init(),
            hasGameRoom: true,
            isSpectator: true
        )
        XCTAssertFalse(try XCTUnwrap(spectator.first(where: { $0.kind == .roomInvite })).isEnabled)
        XCTAssertTrue(try XCTUnwrap(spectator.first(where: { $0.kind == .spectatorInvite })).isEnabled)
    }
}
