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
            "static_information": ["items": []],
        ])
        let started = try GameplayParser.gameStarted(payload)
        XCTAssertEqual(started.yourPlayerID, 1)
        XCTAssertEqual(started.currentPlayerID, 2)
        XCTAssertEqual(started.players.count, 2)
        XCTAssertFalse(started.players[0].isStranded)
        XCTAssertFalse(started.players[0].isBankrupt)
        XCTAssertTrue(started.players[1].isAI)
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
                "items": [["id": "1", "city_id": 1, "city_name": "방콕", "disabled": false]],
            ],
        ])
        XCTAssertEqual(try InteractionRequestParser.parse(olympic).interactionType, "select_one")

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
        XCTAssertEqual(buildRequest.startBuildCities[0].buildOptions.map(\.id), ["building", "hotel"])
    }
}
