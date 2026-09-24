import Foundation
import SwiftUI
import UIKit
import MarbleMobileCore

enum SocialConfirmationKind: String {
    case unfriend
    case block
}

struct SocialConfirmation: Identifiable {
    let id = UUID()
    let kind: SocialConfirmationKind
    let user: LobbyUser
    let title: String
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    enum Screen { case login, lobby, gameRoom }
    enum LobbyPage { case users, rooms }
    enum EntryPhase: Equatable { case inactive, connecting, awaitingSessionEntry, active, recoveryRequired }

    @Published var screen: Screen = .login
    @Published var session: AuthenticatedSession?
    @Published var entryPhase: EntryPhase = .inactive
    @Published var recoveryEntry: SessionEntry?
    @Published var lobbyPage: LobbyPage = .users
    @Published var users: [LobbyUser] = []
    @Published var rooms: [GameRoomSummary] = []
    @Published var socialState = SocialState()
    @Published var alertMessage: String?
    @Published var profileText: String?
    @Published var pendingSocialConfirmation: SocialConfirmation?
    @Published var isPresentingCreateRoom = false
    @Published var isRoomCreationPending = false
    @Published var roomCreationErrorMessage: String?
    @Published var pendingRoomJoin: GameRoomSummary?
    @Published var roomJoinPassword = ""
    @Published var isRoomJoinPending = false
    @Published var roomJoinErrorMessage: String?
    @Published var roomEntry: RoomEntrySnapshot?
    @Published var roomUpdate: RoomUpdateSnapshot?
    @Published var roomMessages: [String] = []
    @Published var teamNameDraft = ""
    @Published var chatDraft = ""
    @Published var isTeamCreationPending = false
    @Published var isLeaveRoomPending = false

    // LoginWindow가 재로그인/회원가입 왕복에서도 입력 상태를 보존하는 PC 계약을 유지한다.
    @Published var loginUsername = ""
    @Published var loginPassword = ""
    @Published var loginSaveCredentials = false
    private var loginCredentialsLoaded = false

    let credentials = CredentialStore()
    let api: APIClient
    let socket: WebSocketClient

    init() {
        let config = AppConfiguration.load()
        self.api = APIClient(config: config)
        self.socket = WebSocketClient(config: config)
        socket.onMessage = { [weak self] in self?.handleSocketMessage($0) }
        socket.onDisconnected = { [weak self] message in self?.handleDisconnect(message) }
    }

    func loadSavedLoginIfNeeded() {
        guard !loginCredentialsLoaded else { return }
        loginCredentialsLoaded = true
        let saved = credentials.load()
        loginUsername = saved.username
        loginPassword = saved.password
        loginSaveCredentials = saved.saveEnabled
    }

    func updateLoginUsername(_ value: String) {
        if value != loginUsername { loginPassword = "" }
        loginUsername = value
    }

    func login(username: String, password: String, save: Bool) async -> Bool {
        do {
            let newSession = try await api.login(username: username, password: password)
            if save { credentials.save(username: username, password: password) }
            else { credentials.clear(currentUsername: username) }
            session = newSession
            recoveryEntry = nil
            lobbyPage = .users
            users = []
            rooms = []
            socialState = .init()
            screen = .lobby
            entryPhase = .connecting
            socket.connect(accessToken: newSession.tokens.accessToken)
            entryPhase = .awaitingSessionEntry
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    func logout() {
        socket.disconnect()
        clearAuthenticatedState()
        screen = .login
    }

    func requestSocialState() { socket.send(WireMessages.socialGetState()) }

    func performUserAction(_ action: LobbyUserActionKind, user: LobbyUser) {
        guard let session else { return }
        switch action {
        case .message:
            if user.id == session.identity.userID { announce("자기 자신에게는 메시지를 보낼 수 없습니다."); return }
            if user.connectionStatus == .disconnected { announce("상대방이 오프라인 상태입니다."); return }
            if user.connectionStatus == .recovering { announce("상대방이 게임 복구 중입니다."); return }
            alertMessage = "메시지 창은 2차 UI 범위에서 구현합니다."
        case .note:
            alertMessage = "쪽지 작성 화면은 2차 UI 범위에서 구현합니다."
        case .roomInvite:
            socket.send(WireMessages.invitationSend(targetUserID: user.id, inviteType: "room"))
        case .spectatorInvite:
            socket.send(WireMessages.invitationSend(targetUserID: user.id, inviteType: "spectator"))
        case .friendRequest:
            socket.send(WireMessages.friendRequestSend(targetUserID: user.id))
        case .friendAccept:
            if let request = socialState.incomingRequest(for: user.id) {
                socket.send(WireMessages.friendRequestAccept(requestID: request.requestID))
            }
        case .friendCancel:
            if let request = socialState.outgoingRequest(for: user.id) {
                socket.send(WireMessages.friendRequestCancel(requestID: request.requestID))
            }
        case .unfriend:
            pendingSocialConfirmation = SocialConfirmation(
                kind: .unfriend,
                user: user,
                title: "친구 해제",
                message: "\(user.nickname)님과의 친구 관계를 해제하시겠습니까?"
            )
        case .block:
            pendingSocialConfirmation = SocialConfirmation(
                kind: .block,
                user: user,
                title: "차단",
                message: "\(user.nickname)님을 차단하시겠습니까?\n친구 관계와 대기 중인 친구 요청이 있으면 함께 정리됩니다."
            )
        case .unblock:
            socket.send(WireMessages.userUnblock(targetUserID: user.id))
        case .profile:
            Task { await loadProfile(userID: user.id) }
        }
    }

    func confirmSocialAction(_ confirmation: SocialConfirmation) {
        switch confirmation.kind {
        case .unfriend:
            socket.send(WireMessages.friendshipUnfriend(targetUserID: confirmation.user.id))
        case .block:
            socket.send(WireMessages.userBlock(targetUserID: confirmation.user.id))
        }
        pendingSocialConfirmation = nil
    }

    func performRoomAction(_ action: LobbyRoomActionKind, room: GameRoomSummary?) {
        switch action {
        case .roomInfo:
            guard let room else { alertMessage = "방을 선택해 주세요."; return }
            profileText = PresentationFormatter.roomInfoText(room)
        case .sort:
            announce("방 정렬은 현재 사용할 수 없습니다.")
        case .create:
            guard entryPhase == .active, screen == .lobby, roomEntry == nil else { return }
            guard !isRoomCreationPending, !isRoomJoinPending else { return }
            roomCreationErrorMessage = nil
            isPresentingCreateRoom = true
        case .join:
            guard let room else { alertMessage = "입장할 방을 선택해 주세요."; return }
            beginJoinRoom(room)
        case .spectatorEntry:
            announce("관중석 입장은 아직 연결되지 않았습니다.")
        }
    }

    func createRoom(_ request: RoomCreationRequest) {
        guard entryPhase == .active, screen == .lobby, roomEntry == nil, !isRoomCreationPending, !isRoomJoinPending else { return }
        isRoomCreationPending = true
        roomCreationErrorMessage = nil
        socket.send(WireMessages.createRoom(request))
    }

    func beginJoinRoom(_ room: GameRoomSummary) {
        guard entryPhase == .active, screen == .lobby, roomEntry == nil else { return }
        guard !isRoomCreationPending, !isRoomJoinPending else { return }
        roomJoinErrorMessage = nil
        if room.isPrivate == true {
            roomJoinPassword = ""
            pendingRoomJoin = room
        } else {
            sendJoinRoom(room: room, password: nil)
        }
    }

    func submitPendingPrivateRoomJoin() {
        guard let room = pendingRoomJoin, room.isPrivate == true else { return }
        let password = roomJoinPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else {
            roomJoinErrorMessage = "비밀번호를 입력해 주세요."
            return
        }
        sendJoinRoom(room: room, password: password)
    }

    func cancelPendingRoomJoin() {
        guard !isRoomJoinPending else { return }
        pendingRoomJoin = nil
        roomJoinPassword = ""
        roomJoinErrorMessage = nil
    }

    private func sendJoinRoom(room: GameRoomSummary, password: String?) {
        guard entryPhase == .active, screen == .lobby, roomEntry == nil else { return }
        guard !isRoomCreationPending, !isRoomJoinPending else { return }
        isRoomJoinPending = true
        roomJoinErrorMessage = nil
        socket.send(WireMessages.joinRoom(roomID: room.id, password: password))
    }

    var isInGameRoom: Bool { roomEntry != nil }

    var hasJoinedTeam: Bool {
        guard let userID = session?.identity.userID else { return false }
        return roomUpdate?.containsUserInTeam(userID) == true
    }

    var currentTeamName: String? {
        guard let userID = session?.identity.userID else { return nil }
        return roomUpdate?.team(containing: userID)?.name
    }

    func createTeamFromDraft() {
        guard roomEntry != nil, !hasJoinedTeam, !isTeamCreationPending, !isLeaveRoomPending else { return }
        let teamName = teamNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isTeamCreationPending = true
        socket.send(WireMessages.createTeam(teamName: teamName))
    }

    func sendRoomChatFromDraft() {
        guard roomEntry != nil else { return }
        let message = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        socket.send(WireMessages.roomChat(message: message))
        chatDraft = ""
    }

    func showLobbyFromGameRoom() {
        guard roomEntry != nil else { return }
        screen = .lobby
    }

    func showGameRoom() {
        guard roomEntry != nil else { return }
        screen = .gameRoom
    }

    func requestLeaveRoom() {
        guard roomEntry != nil, !isLeaveRoomPending, !isTeamCreationPending else { return }
        isLeaveRoomPending = true
        socket.send(WireMessages.leaveRoom())
    }

    private func loadProfile(userID: Int) async {
        guard let currentSession = session else { return }
        do {
            let result = try await api.getProfile(userID: userID, tokens: currentSession.tokens)
            if session?.identity.userID == currentSession.identity.userID {
                session?.tokens = result.tokens
            }
            profileText = PresentationFormatter.userProfileText(result.profile)
        } catch let error as APIAuthenticationLostError {
            returnToLogin(message: error.localizedDescription)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func handleSocketMessage(_ data: [String: Any]) {
        guard let type = data["type"] as? String else { return }
        if type == "session_entry" {
            do {
                let entry = try SessionEntryParser.parse(data)
                recoveryEntry = entry
                switch entry.mode {
                case .normalLobby:
                    entryPhase = .active
                    recoveryEntry = nil
                    requestSocialState()
                case .activeGameRecovery:
                    entryPhase = .recoveryRequired
                }
            } catch {
                socket.disconnect()
                returnToLogin(message: "서버의 로그인 상태 응답이 올바르지 않습니다.\n다시 로그인해 주세요.")
            }
            return
        }

        guard entryPhase == .active else { return }

        if type == "room_created" || type == "room_joined" {
            do {
                let snapshot = type == "room_created"
                    ? try RoomEntryParser.parseCreated(data)
                    : try RoomEntryParser.parseJoined(data)
                isRoomCreationPending = false
                isPresentingCreateRoom = false
                roomCreationErrorMessage = nil
                isRoomJoinPending = false
                pendingRoomJoin = nil
                roomJoinPassword = ""
                roomJoinErrorMessage = nil
                enterGameRoom(snapshot)
            } catch {
                isRoomCreationPending = false
                isPresentingCreateRoom = false
                isRoomJoinPending = false
                pendingRoomJoin = nil
                roomJoinPassword = ""
                roomJoinErrorMessage = nil
                socket.disconnect()
                returnToLogin(message: "방 권한 정보를 확인할 수 없어 게임방을 열지 못했습니다.\n다시 로그인해 주세요.")
            }
            return
        }

        switch type {
        case "room_update":
            handleRoomUpdate(data)
        case "room_event":
            if let message = RoomEventFormatter.message(from: data) {
                roomMessages.append(message)
                announce(message)
            }
        case "room_chat":
            if let chat = try? RoomChatParser.parse(data) {
                roomMessages.append("\(chat.fromNickname): \(chat.message)")
                announce("\(chat.fromNickname). \(chat.message)")
            }
        case "room_left":
            handleRoomLeft(data)
        case "user_list":
            if let parsed = try? WireParser.lobbyUsers(from: data) { users = parsed }
        case "room_list":
            if let parsed = try? WireParser.rooms(from: data) { rooms = parsed }
        case "social_state":
            socialState = WireParser.socialState(from: data)
        case "friend_request_sent", "friend_request_received", "friend_request_removed", "friendship_added", "friendship_removed", "user_blocked", "user_unblocked", "social_state_changed":
            requestSocialState()
        case "social_error", "chat_error", "invitation_error", "note_error":
            if let message = data["message"] as? String { alertMessage = message }
        case "error":
            if let message = data["message"] as? String {
                if isRoomCreationPending {
                    isRoomCreationPending = false
                    roomCreationErrorMessage = message
                } else if isRoomJoinPending {
                    isRoomJoinPending = false
                    if pendingRoomJoin != nil {
                        roomJoinErrorMessage = message
                    } else {
                        alertMessage = message
                    }
                } else if isTeamCreationPending {
                    isTeamCreationPending = false
                    alertMessage = message
                } else if isLeaveRoomPending {
                    isLeaveRoomPending = false
                    alertMessage = message
                } else {
                    alertMessage = message
                }
            }
        default:
            break
        }
    }


    private func enterGameRoom(_ snapshot: RoomEntrySnapshot) {
        roomEntry = snapshot
        roomUpdate = nil
        roomMessages = []
        teamNameDraft = session?.identity.nickname ?? ""
        chatDraft = ""
        isTeamCreationPending = false
        isLeaveRoomPending = false
        screen = .gameRoom
    }

    private func handleRoomUpdate(_ data: [String: Any]) {
        guard let currentRoomID = roomEntry?.roomID else { return }
        do {
            let snapshot = try RoomUpdateParser.parse(data)
            guard snapshot.roomID == currentRoomID else { return }
            let wasJoined = hasJoinedTeam
            roomUpdate = snapshot
            if !wasJoined, hasJoinedTeam {
                isTeamCreationPending = false
                if let actualTeamName = currentTeamName {
                    teamNameDraft = actualTeamName
                }
            }
        } catch {
            // PC판과 같은 원칙: 잘못된 room_update로 기존 authoritative 상태를 덮어쓰지 않는다.
            return
        }
    }

    private func handleRoomLeft(_ data: [String: Any]) {
        guard let currentRoomID = roomEntry?.roomID,
              let roomID = data["room_id"] as? Int,
              roomID == currentRoomID
        else { return }
        clearRoomState()
        screen = .lobby
    }

    private func clearRoomState() {
        roomEntry = nil
        roomUpdate = nil
        roomMessages = []
        teamNameDraft = ""
        chatDraft = ""
        isTeamCreationPending = false
        isLeaveRoomPending = false
    }

    private func handleDisconnect(_ message: String) {
        guard screen != .login else { return }
        returnToLogin(message: message)
    }

    private func returnToLogin(message: String) {
        socket.disconnect()
        clearAuthenticatedState()
        screen = .login
        if !message.isEmpty { alertMessage = message }
    }

    private func clearAuthenticatedState() {
        session = nil
        users = []
        rooms = []
        socialState = .init()
        recoveryEntry = nil
        entryPhase = .inactive
        lobbyPage = .users
        pendingSocialConfirmation = nil
        profileText = nil
        isPresentingCreateRoom = false
        isRoomCreationPending = false
        roomCreationErrorMessage = nil
        pendingRoomJoin = nil
        roomJoinPassword = ""
        isRoomJoinPending = false
        roomJoinErrorMessage = nil
        clearRoomState()
    }

    func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
