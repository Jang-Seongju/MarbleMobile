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

struct PrivateMessageLine: Identifiable, Equatable {
    let id = UUID()
    let speaker: String
    let text: String
    let isMine: Bool
}

struct PrivateConversation: Identifiable, Equatable {
    let userID: Int
    var nickname: String
    var lines: [PrivateMessageLine]
    var id: Int { userID }
}

struct GameRoomMessage: Equatable {
    enum Kind: Equatable {
        case standard
        case chat
    }

    let text: String
    let kind: Kind

    static func standard(_ text: String) -> GameRoomMessage {
        GameRoomMessage(text: text, kind: .standard)
    }

    static func chat(_ text: String) -> GameRoomMessage {
        GameRoomMessage(text: text, kind: .chat)
    }
}

enum UtilitySheet: String, Identifiable {
    case receiveNotifications
    case invitations
    case privateMessages
    case noteMailbox
    case friendManagement
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    enum Screen { case login, lobby, gameRoom }
    enum LobbyPage { case users, rooms }
    enum EntryPhase: Equatable { case inactive, connecting, awaitingSessionEntry, active, recoveryRequired }
    enum IslandContextAction: Equatable { case escapeCard, bail }

    @Published var screen: Screen = .login
    @Published var session: AuthenticatedSession?
    @Published var entryPhase: EntryPhase = .inactive
    @Published var recoveryEntry: SessionEntry?
    @Published var lobbyPage: LobbyPage = .users
    @Published var users: [LobbyUser] = []
    @Published var rooms: [GameRoomSummary] = []
    @Published var socialState = SocialState()
    @Published private(set) var invitations: [GameInvitation] = []
    @Published private(set) var privateConversations: [Int: PrivateConversation] = [:]
    @Published private(set) var unseenPrivateMessageUserIDs: Set<Int> = []
    @Published private(set) var notes: [NoteSnapshot] = []
    @Published var utilitySheet: UtilitySheet?
    @Published var activePrivateMessageUserID: Int?
    @Published var preferredPrivateMessageUserID: Int?
    @Published var preferredNoteUserID: Int?
    @Published var preferredFriendRequestID: Int?
    @Published private(set) var noteRecipientSearchResults: [SocialUser] = []
    private var notifiedNoteIDs: Set<Int> = []
    private var notifiedFriendRequestIDs: Set<Int> = []
    private var pendingFriendRequestReadIDs: Set<Int> = []
    private var pendingNoteReadIDs: Set<Int> = []
    private var userPresenceLoaded = false
    private var socialStateLoaded = false
    private var friendPresenceBaselined = false
    private var friendPresenceSnapshot: [Int: FriendPresenceSnapshot] = [:]
    @Published private(set) var pendingInvitationID: Int?
    private var pendingInvitationType: GameInvitationType?
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
    @Published private(set) var spectatorPhase: SpectatorClientPhase = .idle
    @Published var pendingSpectatorTargetList: SpectatorTargetList?
    @Published var pendingSpectatorPasswordTarget: SpectatorTarget?
    @Published var spectatorErrorMessage: String?
    @Published private(set) var spectatorRegistration: SpectatorRegistrationSnapshot?
    @Published var roomEntry: RoomEntrySnapshot?
    @Published var roomUpdate: RoomUpdateSnapshot?
    @Published var roomMessages: [GameRoomMessage] = []
    @Published var boardCatalog: BoardCatalogSnapshot?
    @Published var staticInformationCatalog: StaticInformationCatalogSnapshot?
    @Published var boardCursor = BoardCursorState()
    @Published var gameRotor = GameRotorState()
    @Published var aiSelectionRequest: AIPlayerSelectionRequest?
    @Published var selectedAIIDs: Set<String> = []
    @Published var activeInteraction: InteractionRequestSnapshot?
    @Published var interactionResponseSubmitted = false
    @Published var gamePlayers: [GamePlayerSnapshot] = []
    @Published var gameCities: [GameCityStateSnapshot] = []
    @Published var gameIsActive = false
    @Published var gameFinished = false
    @Published var myPlayerID: Int?
    @Published var currentPlayerID: Int?
    @Published var currentTurnGeneration: Int?
    @Published var nextTurnCommand = "roll_dice"
    @Published var turnCommandWindowOpen = false
    @Published var turnActionStarted = false
    @Published var isGameStartPending = false
    @Published var teamNameDraft = ""
    @Published var chatDraft = ""
    @Published var isTeamCreationPending = false
    @Published var isLeaveRoomPending = false
    @Published private(set) var heldCardID: String?
    @Published private(set) var heldCardName: String?
    @Published private(set) var bailPaymentSelected = false
    @Published private(set) var islandEscapeCardSelected = false
    @Published private(set) var salaryBoosterSelected = false
    private var isRoomEntryRecoveryPending = false
    private var spectatorEntryRequest: SpectatorEntryRequest?
    private var spectatorJoinExpectation: SpectatorJoinExpectation?
    private var spectatorBootstrapBoardApplied = false
    private var pendingSpectatorRoomUpdate: RoomUpdateSnapshot?
    private var pendingSpectatorGameState: GameStateSnapshot?
    private var spectatorContextAnnounced = false
    private var spectatorSceneBootstrapPending = false
    private var pendingSilentHeldCardQuery = false
    private struct InteractionResultGate {
        let token: UUID
        let requestID: String
        let flowID: String
        var completion: (() -> Void)?
        var releaseRequested: Bool
    }

    private var aiSelectionHistory: [String] = []
    private var activatedInteractionRequestIDs: Set<String> = []
    private var pendingInteractionActivation: InteractionRequestSnapshot?
    private var pendingInteractionResultGate: InteractionResultGate?
    private var completedInteractionFlowAwaitingDismiss: String?
    private var pendingRotorDirections: [String: [Bool]] = [:]
    private var pendingPlayerPositionTargetIDs: [Int] = []
    private var aiRemainderTextOnly = false
    private var aiRemainderActivationPending = false
    private var appSceneActive = true
    private var reconnectNeeded = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var recoverySnapshotApplied = false
    private var recoveryCompletedSent = false
    private let boardCornerFeedback = UIImpactFeedbackGenerator(style: .medium)

    // LoginWindow가 재로그인/회원가입 왕복에서도 입력 상태를 보존하는 PC 계약을 유지한다.
    @Published var loginUsername = ""
    @Published var loginPassword = ""
    @Published var loginSaveCredentials = false
    private var loginCredentialsLoaded = false

    let credentials = CredentialStore()
    let api: APIClient
    let socket: WebSocketClient
    private let audio: IOSAudioController
    private let output: IOSOutputOrchestrator
    private let turnDeadlineWarning: TurnDeadlineWarningController

    init() {
        let config = AppConfiguration.load()
        let audio = IOSAudioController()
        self.api = APIClient(config: config)
        self.socket = WebSocketClient(config: config)
        self.audio = audio
        self.output = IOSOutputOrchestrator(audio: audio)
        self.turnDeadlineWarning = TurnDeadlineWarningController(audio: audio)
        output.noticeSink = { [weak self] message in self?.roomMessages.append(.standard(message)) }
        socket.onMessage = { [weak self] in self?.handleSocketMessage($0) }
        socket.onDisconnected = { [weak self] message in self?.handleDisconnect(message) }
    }

    func setApplicationSceneActive(_ active: Bool) {
        appSceneActive = active
        guard active, session != nil, screen != .login else { return }
        if reconnectNeeded || !socket.hasActiveConnection {
            scheduleReconnect()
        } else {
            socket.probeConnection()
        }
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
            resetReconnectState()
            recoveryEntry = nil
            lobbyPage = .users
            users = []
            rooms = []
            socialState = .init()
            clearInvitationState()
            clearReceiveCommunicationState()
            screen = .lobby
            output.emit(PresentationPlan(
                root: .sfx(clip: "login.WAV", completion: .startOnly),
                category: .systemUI
            ))
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
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectNeeded = false
        socket.disconnect()
        clearAuthenticatedState()
        screen = .login
        // 명시적 로그아웃에서만 재생한다. clearAuthenticatedState()가
        // transient audio를 먼저 정리한 뒤 시작하는 client(393) 계약을 따른다.
        output.emit(PresentationPlan(
            root: .sfx(clip: "logout.wav", completion: .startOnly),
            category: .systemUI
        ))
    }

    func requestSocialState() { socket.send(WireMessages.socialGetState()) }
    func requestNoteMailbox() { socket.send(WireMessages.noteMailboxGet()) }

    var unreadPrivateMessageSenderCount: Int { unseenPrivateMessageUserIDs.count }
    var unreadNoteCount: Int { notes.filter { $0.direction == .received && !$0.isRead }.count }
    var unreadFriendRequestCount: Int { socialState.incomingRequests.filter { !$0.isRead }.count }

    var receiveNotificationTotalCount: Int {
        unreadPrivateMessageSenderCount + unreadNoteCount + invitations.count + unreadFriendRequestCount
    }

    var hasReceiveNotifications: Bool { receiveNotificationTotalCount > 0 }

    var isInvitationInboxPresented: Bool { utilitySheet == .invitations }
    var isPrivateMessagesPresented: Bool { utilitySheet == .privateMessages }
    var isNoteMailboxPresented: Bool { utilitySheet == .noteMailbox }
    var isFriendManagementPresented: Bool { utilitySheet == .friendManagement }

    func presentReceiveNotifications() {
        utilitySheet = .receiveNotifications
    }

    func openPrivateMessagesFromNotifications() {
        preferredPrivateMessageUserID = nil
        utilitySheet = .privateMessages
    }

    func openNotesFromNotifications() {
        preferredNoteUserID = nil
        utilitySheet = .noteMailbox
    }

    func openInvitationsFromNotifications() {
        presentInvitationInbox()
    }

    func openFriendRequestsFromNotifications() {
        preferredFriendRequestID = socialState.incomingRequests.first(where: { !$0.isRead })?.requestID
            ?? socialState.incomingRequests.first?.requestID
        utilitySheet = .friendManagement
    }

    func openPrivateConversation(userID: Int, nickname: String) {
        if privateConversations[userID] == nil {
            privateConversations[userID] = .init(userID: userID, nickname: nickname, lines: [])
        } else if privateConversations[userID]?.nickname != nickname {
            privateConversations[userID]?.nickname = nickname
        }
        preferredPrivateMessageUserID = userID
        unseenPrivateMessageUserIDs.remove(userID)
        activePrivateMessageUserID = userID
        utilitySheet = .privateMessages
    }

    func activatePrivateConversation(userID: Int) {
        unseenPrivateMessageUserIDs.remove(userID)
        activePrivateMessageUserID = userID
    }

    func closePrivateConversation(userID: Int) {
        privateConversations.removeValue(forKey: userID)
        unseenPrivateMessageUserIDs.remove(userID)
        if activePrivateMessageUserID == userID { activePrivateMessageUserID = nil }
    }

    func sendPrivateMessage(userID: Int, nickname: String, text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        if privateConversations[userID] == nil {
            privateConversations[userID] = .init(userID: userID, nickname: nickname, lines: [])
        }
        socket.send(WireMessages.privateChat(targetUserID: userID, message: message))
    }

    func openNoteMailbox(targetUser: SocialUser? = nil) {
        preferredNoteUserID = targetUser?.userID
        utilitySheet = .noteMailbox
        requestNoteMailbox()
    }

    func sendNote(targetUserID: Int, body: String) {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        socket.send(WireMessages.noteSend(targetUserID: targetUserID, body: body))
    }

    func searchNoteRecipients(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            announce("검색할 닉네임을 입력해 주세요.")
            return
        }
        socket.send(WireMessages.noteRecipientSearch(query: query))
    }

    func clearNoteRecipientSearchResults() {
        noteRecipientSearchResults.removeAll()
    }

    func deleteNote(_ noteID: Int) {
        socket.send(WireMessages.noteDelete(noteID: noteID))
    }

    func deleteNoteConversation(userID: Int) {
        socket.send(WireMessages.noteDeleteConversation(targetUserID: userID))
    }

    func markNoteRead(_ noteID: Int) {
        guard let note = notes.first(where: { $0.noteID == noteID }), note.direction == .received,
              !note.isRead, !pendingNoteReadIDs.contains(noteID) else { return }
        pendingNoteReadIDs.insert(noteID)
        socket.send(WireMessages.noteMarkRead(noteID: noteID))
    }

    func markFriendRequestRead(_ requestID: Int) {
        guard let request = socialState.incomingRequests.first(where: { $0.requestID == requestID }),
              !request.isRead, !pendingFriendRequestReadIDs.contains(requestID) else { return }
        pendingFriendRequestReadIDs.insert(requestID)
        socket.send(WireMessages.friendRequestMarkRead(requestID: requestID))
    }

    func searchSocialUsers(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            announce("검색할 닉네임을 입력해 주세요.")
            return
        }
        socialState.searchQuery = query
        socket.send(WireMessages.socialSearchUsers(query: query))
    }

    func acceptFriendRequest(_ requestID: Int) {
        socket.send(WireMessages.friendRequestAccept(requestID: requestID))
    }

    func rejectFriendRequest(_ requestID: Int) {
        socket.send(WireMessages.friendRequestReject(requestID: requestID))
    }

    func cancelFriendRequest(_ requestID: Int) {
        socket.send(WireMessages.friendRequestCancel(requestID: requestID))
    }

    func unblockUser(_ userID: Int) {
        socket.send(WireMessages.userUnblock(targetUserID: userID))
    }

    func presentInvitationInbox() {
        guard !invitations.isEmpty else { return }
        utilitySheet = .invitations
    }

    func dismissInvitationInbox() {
        // PC client(393)의 초대 창 닫기와 동일하게 서버에 거절 요청을 보내지 않고
        // 현재 로컬 목록만 폐기한다. 이미 전송한 수락 요청은 취소하지 않는다.
        if utilitySheet == .invitations { utilitySheet = nil }
        invitations.removeAll()
    }

    func acceptInvitation(_ invitation: GameInvitation) {
        guard entryPhase == .active, pendingInvitationID == nil,
              invitations.contains(where: { $0.inviteID == invitation.inviteID })
        else { return }

        if invitation.inviteType == .spectator {
            guard prepareSpectatorInvitationJoin(invitation) else { return }
        }

        pendingInvitationID = invitation.inviteID
        pendingInvitationType = invitation.inviteType
        socket.send(WireMessages.invitationAccept(inviteID: invitation.inviteID))
    }

    func invitationRoomInfoText(_ invitation: GameInvitation) -> String {
        let participantNames: [String]?
        if let roomUpdate, roomUpdate.roomID == invitation.room.roomID {
            participantNames = roomUpdate.teams.flatMap(\.members).map(\.nickname)
        } else {
            participantNames = nil
        }

        if let cached = rooms.first(where: { $0.id == invitation.room.roomID }) {
            return PresentationFormatter.roomInfoText(cached, participantNames: participantNames)
        }
        let fallback = GameRoomSummary(
            id: invitation.room.roomID,
            title: invitation.room.title,
            current: nil,
            maxPlayers: nil,
            isPrivate: invitation.room.isPrivate,
            status: nil
        )
        return PresentationFormatter.roomInfoText(fallback, participantNames: participantNames)
    }

    private func prepareSpectatorInvitationJoin(_ invitation: GameInvitation) -> Bool {
        guard invitation.inviteType == .spectator,
              let target = invitation.spectatorTarget,
              spectatorPhase == .idle
        else {
            alertMessage = "다른 관중석 입장 처리가 진행 중입니다."
            return false
        }

        let request = SpectatorEntryRequest(
            roomID: invitation.room.roomID,
            isPrivate: invitation.room.isPrivate
        )
        spectatorEntryRequest = request
        spectatorJoinExpectation = .init(request: request, target: target)
        pendingSpectatorTargetList = nil
        pendingSpectatorPasswordTarget = nil
        spectatorErrorMessage = nil
        spectatorPhase = .joinPending
        return true
    }

    func performUserAction(_ action: LobbyUserActionKind, user: LobbyUser) {
        guard let session else { return }
        switch action {
        case .message:
            if user.id == session.identity.userID { announce("자기 자신에게는 메시지를 보낼 수 없습니다."); return }
            if user.connectionStatus == .disconnected { announce("상대방이 오프라인 상태입니다."); return }
            if user.connectionStatus == .recovering { announce("상대방이 게임 복구 중입니다."); return }
            openPrivateConversation(userID: user.id, nickname: user.nickname)
        case .note:
            openNoteMailbox(targetUser: .init(userID: user.id, nickname: user.nickname))
        case .roomInvite:
            socket.send(WireMessages.invitationSend(targetUserID: user.id, inviteType: .room))
        case .spectatorInvite:
            socket.send(WireMessages.invitationSend(targetUserID: user.id, inviteType: .spectator))
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
            guard entryPhase == .active, screen == .lobby, !isInGameRoom, spectatorPhase == .idle else { return }
            guard !isRoomCreationPending, !isRoomJoinPending else { return }
            roomCreationErrorMessage = nil
            isPresentingCreateRoom = true
        case .join:
            guard let room else { alertMessage = "입장할 방을 선택해 주세요."; return }
            beginJoinRoom(room)
        case .spectatorEntry:
            guard let room else { alertMessage = "관람할 방을 선택해 주세요."; return }
            beginSpectatorEntry(room)
        }
    }

    func createRoom(_ request: RoomCreationRequest) {
        guard entryPhase == .active, screen == .lobby, !isInGameRoom, spectatorPhase == .idle,
              !isRoomCreationPending, !isRoomJoinPending, !isRoomEntryRecoveryPending else { return }
        isRoomCreationPending = true
        roomCreationErrorMessage = nil
        socket.send(WireMessages.createRoom(request))
    }

    func beginJoinRoom(_ room: GameRoomSummary) {
        guard entryPhase == .active, screen == .lobby, roomEntry == nil, spectatorRegistration == nil, !isRoomEntryRecoveryPending else { return }
        guard !isRoomCreationPending, !isRoomJoinPending, spectatorPhase == .idle else { return }
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

    func beginSpectatorEntry(_ room: GameRoomSummary) {
        guard entryPhase == .active, screen == .lobby else { return }

        if let registration = spectatorRegistration {
            guard spectatorPhase == .active else { return }
            if registration.roomID == room.id {
                screen = .gameRoom
            } else {
                alertMessage = "관중석에서 먼저 퇴장해 주세요."
            }
            return
        }

        if roomEntry != nil {
            alertMessage = "게임방에 참여 중에는 관중석에 입장할 수 없습니다."
            return
        }
        guard spectatorPhase == .idle, !isRoomCreationPending, !isRoomJoinPending, !isRoomEntryRecoveryPending else { return }
        guard let isPrivate = room.isPrivate else {
            alertMessage = "선택한 방 정보를 찾을 수 없습니다."
            return
        }
        let request = SpectatorEntryRequest(roomID: room.id, isPrivate: isPrivate)
        spectatorEntryRequest = request
        spectatorJoinExpectation = nil
        pendingSpectatorTargetList = nil
        pendingSpectatorPasswordTarget = nil
        spectatorErrorMessage = nil
        spectatorPhase = .targetListPending
        socket.send(WireMessages.getSpectatorTargets(roomID: room.id))
    }

    func selectSpectatorTarget(_ target: SpectatorTarget) {
        guard spectatorPhase == .targetSelection,
              let request = spectatorEntryRequest,
              let list = pendingSpectatorTargetList,
              list.roomID == request.roomID,
              list.targets.contains(target)
        else { return }

        pendingSpectatorTargetList = nil
        if request.isPrivate {
            pendingSpectatorPasswordTarget = target
            spectatorErrorMessage = nil
            spectatorPhase = .passwordEntry
        } else {
            sendSpectatorJoin(request: request, target: target, password: nil)
        }
    }

    func cancelSpectatorTargetSelection() {
        guard spectatorPhase == .targetSelection else { return }
        resetPendingSpectatorEntry()
    }

    func submitSpectatorPassword(_ passwordInput: String) {
        guard spectatorPhase == .passwordEntry,
              let request = spectatorEntryRequest, request.isPrivate,
              let target = pendingSpectatorPasswordTarget
        else { return }
        guard !passwordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            spectatorErrorMessage = "비밀번호를 입력해 주세요."
            return
        }
        pendingSpectatorPasswordTarget = nil
        // PC client(393) 계약과 같이 공백뿐인지 여부만 trim으로 검사하고,
        // 실제 비밀번호 값은 사용자가 입력한 원문 그대로 이번 요청 한 번에만 사용한다.
        sendSpectatorJoin(request: request, target: target, password: passwordInput)
    }

    func cancelSpectatorPassword() {
        guard spectatorPhase == .passwordEntry else { return }
        resetPendingSpectatorEntry()
    }

    private func sendSpectatorJoin(
        request: SpectatorEntryRequest,
        target: SpectatorTarget,
        password: String?
    ) {
        guard spectatorRegistration == nil, spectatorPhase == .targetSelection || spectatorPhase == .passwordEntry else { return }
        spectatorJoinExpectation = .init(request: request, target: target)
        spectatorErrorMessage = nil
        spectatorPhase = .joinPending
        socket.send(WireMessages.joinSpectator(
            roomID: request.roomID,
            observedUserID: target.observedUserID,
            password: password
        ))
    }

    private func resetPendingSpectatorEntry() {
        spectatorPhase = .idle
        spectatorEntryRequest = nil
        spectatorJoinExpectation = nil
        pendingSpectatorTargetList = nil
        pendingSpectatorPasswordTarget = nil
        spectatorErrorMessage = nil
    }

    private func handleSpectatorTargetList(_ data: [String: Any]) {
        guard spectatorPhase == .targetListPending,
              let request = spectatorEntryRequest
        else { return }

        do {
            let list = try SpectatorParser.targetList(data)
            // stale response는 현재 선택으로 room_id를 다시 추측하지 않는다.
            guard list.roomID == request.roomID else { return }
            if list.targets.isEmpty {
                resetPendingSpectatorEntry()
                alertMessage = "관람할 수 있는 플레이어가 없습니다."
                return
            }
            pendingSpectatorTargetList = list
            spectatorErrorMessage = nil
            spectatorPhase = .targetSelection
        } catch {
            resetPendingSpectatorEntry()
            alertMessage = error.localizedDescription
        }
    }

    private func handleSpectatorJoined(_ data: [String: Any]) {
        guard spectatorPhase == .joinPending,
              let expectation = spectatorJoinExpectation
        else { return }

        do {
            let registration = try SpectatorParser.joined(data)
            guard registration.roomID == expectation.request.roomID,
                  registration.observedUserID == expectation.target.observedUserID,
                  registration.observedUserNickname == expectation.target.nickname
            else {
                abandonUntrustedSpectatorJoin(message: "관중석에 입장할 수 없습니다.")
                return
            }

            prepareSpectatorRoom(registration)
        } catch {
            // spectator_joined는 서버 등록 확정 뒤에 오지만 malformed payload는
            // 그 등록의 room/user parity 자체를 신뢰할 수 없다. 임의의
            // leave_spectator를 보내지 않고 현재 연결을 닫아 서버 연결 종료
            // lifecycle이 등록을 제거하게 한다(client(393) 계약).
            abandonUntrustedSpectatorJoin(message: "관중석에 입장할 수 없습니다.")
        }
    }

    private func abandonUntrustedSpectatorJoin(message: String) {
        guard spectatorPhase == .joinPending else { return }
        spectatorPhase = .aborting
        spectatorEntryRequest = nil
        spectatorJoinExpectation = nil
        pendingSpectatorTargetList = nil
        pendingSpectatorPasswordTarget = nil
        spectatorErrorMessage = nil
        pendingSpectatorRoomUpdate = nil
        pendingSpectatorGameState = nil
        if !message.isEmpty { alertMessage = message }
        clearRoomPresentationState()
        screen = .lobby
        // notify=true가 AppModel의 공통 연결 종료 생명주기를 실행해 인증 세션은
        // 유지한 채 normal_lobby로 다시 진입시킨다. 관중석 자체는 복구하지 않는다.
        socket.disconnect(notify: true)
    }

    private func prepareSpectatorRoom(_ registration: SpectatorRegistrationSnapshot) {
        output.stopAll()
        spectatorRegistration = registration
        spectatorPhase = .bootstrapping
        spectatorEntryRequest = nil
        spectatorJoinExpectation = nil
        pendingSpectatorTargetList = nil
        pendingSpectatorPasswordTarget = nil
        spectatorErrorMessage = nil
        spectatorBootstrapBoardApplied = false
        pendingSpectatorRoomUpdate = nil
        pendingSpectatorGameState = nil
        spectatorContextAnnounced = false
        spectatorSceneBootstrapPending = true

        // 참가 membership은 만들지 않는다. 기존 GameRoomView에 공개 게임 상태만
        // 적용하기 위해 화면/게임 presentation 상태만 새로 준비한다.
        roomEntry = nil
        roomUpdate = nil
        roomMessages = []
        boardCatalog = nil
        staticInformationCatalog = nil
        boardCursor.reset()
        gameRotor.reset()
        clearGameplayState()
        teamNameDraft = ""
        chatDraft = ""
        isTeamCreationPending = false
        isLeaveRoomPending = false
    }

    private func activateSpectatorRoomIfReady() {
        guard spectatorPhase == .bootstrapping,
              spectatorRegistration != nil,
              spectatorBootstrapBoardApplied,
              roomUpdate != nil
        else { return }

        spectatorPhase = .active
        screen = .gameRoom
        if !spectatorContextAnnounced, let registration = spectatorRegistration {
            spectatorContextAnnounced = true
            let message = "\(registration.observedUserNickname)의 관중석"
            // 입장 SFX는 server(678)의 room_sound(spectator_enter)가 관전자 본인까지
            // 포함해 공개 수신자에게 정확히 한 번 전달한다. 여기서는 PC 계약대로
            // 관전 대상 안내 TTS만 로컬로 출력해 SFX를 중복 재생하지 않는다.
            output.emit(.systemTTS(message, preservePending: true))
        }

        if let pending = pendingSpectatorGameState,
           let registration = spectatorRegistration {
            pendingSpectatorGameState = nil
            applySpectatorGameState(pending, registration: registration)
        }
    }

    private func handleSpectatorLeft(_ data: [String: Any]) {
        guard let left = try? SpectatorParser.left(data) else { return }

        guard let registration = spectatorRegistration,
              left.roomID == registration.roomID,
              left.observedUserID == registration.observedUserID
        else { return }

        let lifecycleMessage = RoomEventFormatter.message(from: data, eventKey: "lifecycle_event")
        let lifecycleClip = roomSoundClip(for: data["sound_event"] as? String)
        finishSpectatorSession()
        if let lifecycleMessage {
            let root: PresentationNode
            if let lifecycleClip {
                root = .parallel([
                    .sfx(clip: lifecycleClip, completion: .startOnly),
                    .tts(lifecycleMessage)
                ])
            } else {
                root = .tts(lifecycleMessage)
            }
            output.emit(PresentationPlan(
                root: root,
                category: .systemUI,
                queuePolicy: .enqueue,
                interruptRetention: .preservePending
            ))
        } else if let lifecycleClip {
            output.emit(PresentationPlan(
                root: .sfx(clip: lifecycleClip, completion: .startOnly),
                category: .systemUI
            ))
        }
    }

    private func abortSpectatorBootstrap(message: String) {
        let serverMayHaveRegistration = spectatorRegistration != nil
            || spectatorPhase == .bootstrapping
            || spectatorPhase == .active
            || spectatorPhase == .leavePending
            || spectatorPhase == .aborting
        guard serverMayHaveRegistration else {
            resetPendingSpectatorEntry()
            if !message.isEmpty { alertMessage = message }
            return
        }
        if spectatorPhase == .aborting { return }
        spectatorPhase = .aborting
        spectatorErrorMessage = nil
        pendingSpectatorTargetList = nil
        pendingSpectatorPasswordTarget = nil
        if !message.isEmpty { alertMessage = message }
        // 신뢰 가능한 registration은 spectator_left parity 확인을 위해 보존하되,
        // 불완전/오류 관람 화면과 게임 런타임은 즉시 폐기한다. 늦은 snapshot이
        // 다시 ACTIVE 화면을 만들 수 없도록 phase는 ABORTING을 유지한다.
        clearRoomPresentationState()
        screen = .lobby
        socket.send(WireMessages.leaveSpectator())
    }

    private func finishSpectatorSession() {
        clearSpectatorState()
        clearRoomPresentationState()
        screen = .lobby
    }

    private func clearSpectatorState() {
        spectatorPhase = .idle
        spectatorEntryRequest = nil
        spectatorJoinExpectation = nil
        pendingSpectatorTargetList = nil
        pendingSpectatorPasswordTarget = nil
        spectatorErrorMessage = nil
        spectatorRegistration = nil
        spectatorBootstrapBoardApplied = false
        pendingSpectatorRoomUpdate = nil
        pendingSpectatorGameState = nil
        spectatorContextAnnounced = false
        spectatorSceneBootstrapPending = false
    }

    private func sendJoinRoom(room: GameRoomSummary, password: String?) {
        guard entryPhase == .active, screen == .lobby, roomEntry == nil, spectatorRegistration == nil else { return }
        guard !isRoomCreationPending, !isRoomJoinPending, spectatorPhase == .idle else { return }
        isRoomJoinPending = true
        roomJoinErrorMessage = nil
        socket.send(WireMessages.joinRoom(roomID: room.id, password: password))
    }

    var isSpectating: Bool { spectatorRegistration != nil }

    var isInGameRoom: Bool { roomEntry != nil || spectatorRegistration != nil }

    var canShowGameRoom: Bool {
        roomEntry != nil || (spectatorRegistration != nil && spectatorPhase == .active)
    }

    var currentRoomID: Int? { roomEntry?.roomID ?? spectatorRegistration?.roomID }

    /// 참가자는 자기 player_id, 관전자는 observed_user_id를 현재 game_state에서
    /// 해석한 player_id를 읽기/오디오 관점으로 사용한다. 조작 권한은 myPlayerID에만 있다.
    var gamePerspectivePlayerID: Int? {
        if let myPlayerID { return myPlayerID }
        guard let registration = spectatorRegistration else { return nil }
        return gamePlayers.first(where: { $0.userID == registration.observedUserID })?.playerID
    }

    private var informationSelfPlayerID: Int? { isSpectating ? nil : myPlayerID }

    var hasJoinedTeam: Bool {
        guard let userID = session?.identity.userID else { return false }
        return roomUpdate?.containsUserInTeam(userID) == true
    }

    var currentTeamName: String? {
        guard let userID = session?.identity.userID else { return nil }
        return roomUpdate?.team(containing: userID)?.name
    }

    var isBoardReady: Bool {
        boardCatalog != nil && (hasJoinedTeam || spectatorRegistration != nil)
    }

    var isWorldTravelDestinationSelectionActive: Bool {
        guard let request = activeInteraction else { return false }
        return request.interactionType == "select_destination"
            && request.missionType == "world_travel_destination"
    }

    var isBoardDirectTouchAreaAvailable: Bool {
        isBoardReady
            && aiSelectionRequest == nil
            && pendingInteractionActivation == nil
            && (activeInteraction == nil || isWorldTravelDestinationSelectionActive)
    }

    private var localGamePlayer: GamePlayerSnapshot? {
        guard let myPlayerID else { return nil }
        return gamePlayers.first { $0.playerID == myPlayerID }
    }

    var islandContextAction: IslandContextAction? {
        guard entryPhase == .active, gameIsActive, !gameFinished, activeInteraction == nil, pendingInteractionActivation == nil, aiSelectionRequest == nil,
              let player = localGamePlayer, !player.isBankrupt, player.isStranded else { return nil }
        if heldCardID == "island_escape" { return .escapeCard }
        return player.marble >= 200_000 ? .bail : nil
    }

    var islandContextActionSelected: Bool {
        switch islandContextAction {
        case .escapeCard: return islandEscapeCardSelected
        case .bail: return bailPaymentSelected
        case nil: return false
        }
    }

    var salaryBoosterContextAvailable: Bool {
        guard entryPhase == .active, gameIsActive, !gameFinished, activeInteraction == nil, pendingInteractionActivation == nil, aiSelectionRequest == nil,
              let player = localGamePlayer, !player.isBankrupt else { return false }
        return heldCardID == "salary_booster"
    }

    var canCreateTeam: Bool {
        entryPhase == .active
            && roomEntry != nil
            && !hasJoinedTeam
            && !isTeamCreationPending
            && !isLeaveRoomPending
    }

    var canLeaveRoom: Bool {
        guard entryPhase == .active else { return false }
        if spectatorRegistration != nil {
            return spectatorPhase == .active && !isLeaveRoomPending
        }
        guard roomEntry != nil, !isLeaveRoomPending, !isTeamCreationPending else { return false }
        guard gameIsActive else { return true }
        return localGamePlayer?.isBankrupt == true
    }

    var canRollDice: Bool {
        entryPhase == .active
            && gameIsActive
            && !gameFinished
            && myPlayerID != nil
            && currentPlayerID == myPlayerID
            && turnCommandWindowOpen
            && nextTurnCommand != "select_world_travel_destination"
            && !turnActionStarted
            && activeInteraction == nil
    }

    var canCurrentUserStartGame: Bool {
        guard let userID = session?.identity.userID,
              let authority = roomUpdate?.gameStartAuthorityUserID
        else { return false }
        return userID == authority
    }

    var canRequestGameStart: Bool {
        entryPhase == .active
            && roomEntry != nil
            && hasJoinedTeam
            && !gameIsActive
            && !isGameStartPending
            && aiSelectionRequest == nil
            && activeInteraction == nil
            && canCurrentUserStartGame
    }

    func canConfirmAISelection(_ request: AIPlayerSelectionRequest) -> Bool {
        let count = selectedAIIDs.count
        return aiSelectionRequest?.requestID == request.requestID
            && canCurrentUserStartGame
            && request.allowedAICounts.contains(count)
    }

    var currentBoardCell: BoardCellSnapshot? {
        boardCatalog?.cell(at: boardCursor.index)
    }

    var currentBoardAccessibilityDescription: String {
        guard let cell = currentBoardCell else { return "보드 정보가 아직 준비되지 않았습니다." }
        guard (gameIsActive || gameFinished), cell.isCity, let cityID = cell.cityID,
              let info = gameCities.first(where: { $0.cityID == cityID })
        else { return cell.shortDescription }
        let text = InformationCityPresenter.format(
            info,
            spec: InformationDisplaySpecs.cityInfo,
            myPlayerID: informationSelfPlayerID
        )
        return text.isEmpty ? cell.shortDescription : text
    }

    func moveBoardLeft() { moveBoardCursor(.left) }
    func moveBoardRight() { moveBoardCursor(.right) }
    func moveBoardUp() { moveBoardCursor(.up) }
    func moveBoardDown() { moveBoardCursor(.down) }

    private func moveBoardCursor(_ direction: BoardNavigationDirection) {
        guard let catalog = boardCatalog else {
            announce("보드 정보가 아직 준비되지 않았습니다.")
            return
        }
        guard let target = catalog.adjacentCell(from: boardCursor.index, direction: direction) else {
            playBoardBoundaryWarning()
            return
        }
        boardCursor.jump(to: target.index)
        gameRotor.resetBoardCellSelections()
        if target.isCorner {
            boardCornerFeedback.prepare()
            boardCornerFeedback.impactOccurred()
        }
        output.emit(PresentationPlan(
            root: .parallel([
                .sfx(clip: "board_move.wav", completion: .startOnly),
                .tts(currentBoardAccessibilityDescription),
            ]),
            category: .systemUI,
            queuePolicy: .userInputInterrupt
        ))
    }

    func playBoardBoundaryWarning() {
        _ = audio.playSFX("board_boundary.wav")
    }

    func toggleIslandContextAction() {
        guard entryPhase == .active else { return }
        switch islandContextAction {
        case .escapeCard:
            socket.send(WireMessages.toggleHeldCardUse())
        case .bail:
            socket.send(WireMessages.toggleBailPayment())
        case nil:
            break
        }
    }

    func toggleSalaryBoosterUse() {
        guard entryPhase == .active, salaryBoosterContextAvailable else { return }
        socket.send(WireMessages.toggleHeldCardUse())
    }

    func performBoardMagicTap() {
        // 관전자는 참가자 입력을 만들지 않는다. PC client(393)의 read-only
        // BLOCK 경계와 같이 별도 임의 안내 문구도 만들지 않고 조용히 차단한다.
        if isSpectating { return }
        if isWorldTravelDestinationSelectionActive {
            confirmWorldTravelDestination()
            return
        }
        performRollDice()
    }

    func performBoardEscape() -> Bool {
        guard isWorldTravelDestinationSelectionActive else { return false }
        cancelActiveInteraction()
        return true
    }

    private func confirmWorldTravelDestination() {
        guard let request = activeInteraction,
              request.interactionType == "select_destination",
              request.missionType == "world_travel_destination",
              !interactionResponseSubmitted
        else { return }

        let target = boardCursor.index
        let valid: Bool
        if !request.allowedDestinationIndices.isEmpty {
            valid = request.allowedDestinationIndices.contains(target)
        } else {
            valid = !request.excludedIndices.contains(target)
        }
        guard valid else {
            announce("선택할 수 없는 칸입니다.")
            return
        }

        respondToInteraction(
            responseType: "selected",
            payload: ["target_index": target]
        )
    }

    func performRollDice() {
        guard gameIsActive, !gameFinished else {
            announce("게임이 시작되지 않았습니다.")
            return
        }
        guard canRollDice else {
            if nextTurnCommand != "select_world_travel_destination" {
                announce("내 차례가 아닙니다.")
            }
            return
        }
        turnActionStarted = true
        socket.send(WireMessages.rollDice())
    }

    func jumpToBoardLine(_ line: String) {
        let target: Int
        switch line.uppercased() {
        case "A": target = 1
        case "B": target = 9
        case "C": target = 17
        case "D": target = 25
        default: return
        }
        guard boardCatalog?.cell(at: target) != nil else {
            announce("보드 정보가 아직 준비되지 않았습니다.")
            return
        }
        boardCursor.jump(to: target)
        gameRotor.resetBoardCellSelections()
        announceCurrentBoardCell()
    }

    func rotateGameRotorForward() {
        let category = gameRotor.moveCategoryForward()
        announce(category.displayName)
    }

    func rotateGameRotorBackward() {
        let category = gameRotor.moveCategoryBackward()
        announce(category.displayName)
    }

    func moveGameRotorSelectionForward() {
        moveGameRotorSelection(forward: true)
    }

    func moveGameRotorSelectionBackward() {
        moveGameRotorSelection(forward: false)
    }

    func moveGameRotorDetailForward() {
        moveGameRotorDetail(forward: true)
    }

    func moveGameRotorDetailBackward() {
        moveGameRotorDetail(forward: false)
    }

    private func moveGameRotorSelection(forward: Bool) {
        switch gameRotor.category {
        case .cityInformation:
            announce("비용 및 설명은 두 손가락 위아래 쓸기로 조회합니다.")
        case .playerInformation:
            guard let target = gameRotor.movePlayerTarget(
                forward: forward,
                myPlayerID: gamePerspectivePlayerID,
                players: gamePlayers
            ) else {
                announce("플레이어 정보 없음")
                return
            }
            announce(playerRotorTargetName(target))
        case .monopolyInformation:
            announce(gameRotor.moveMonopolyKind(forward: forward).displayName)
        case .cityStatusInformation:
            announce(gameRotor.moveCityStatusKind(forward: forward).displayName)
        case .unitCostInformation:
            guard let cityID = currentBoardCell?.cityID, currentBoardCell?.isCity == true else {
                announce("도시가 아닙니다")
                return
            }
            guard let catalog = staticInformationCatalog else {
                announce("정적 정보가 아직 준비되지 않았습니다.")
                return
            }
            let types = catalog.buildingTypes(cityID: cityID)
            guard let type = gameRotor.moveUnitBuildingType(forward: forward, availableTypes: types) else {
                announce("건물 정보 없음")
                return
            }
            announce(InformationResultPresenter.buildingType(type))
        case .playerPositionInformation:
            announce("플레이어 위치는 두 손가락 위아래 쓸기로 조회합니다.")
        }
    }

    private func moveGameRotorDetail(forward: Bool) {
        switch gameRotor.category {
        case .cityInformation:
            requestRotorCityInformation(forward: forward)
        case .playerInformation:
            requestRotorPlayerCity(forward: forward)
        case .monopolyInformation:
            guard gameIsActive || gameFinished else {
                announce("게임이 시작되지 않았습니다.")
                return
            }
            let query = gameRotor.monopolyKind == .achieved
                ? "achieved_monopoly_status"
                : "ending_monopoly_alerts"
            pendingRotorDirections[query, default: []].append(forward)
            socket.send(WireMessages.informationQuery(queryType: query))
        case .cityStatusInformation:
            guard gameIsActive || gameFinished else {
                announce("게임이 시작되지 않았습니다.")
                return
            }
            let query: String
            switch gameRotor.cityStatusKind {
            case .festival: query = "festival_city_list"
            case .olympic: query = "olympic_city"
            case .activeEffect: query = "active_city_effects"
            }
            pendingRotorDirections[query, default: []].append(forward)
            socket.send(WireMessages.informationQuery(queryType: query))
        case .unitCostInformation:
            requestRotorUnitCost(forward: forward)
        case .playerPositionInformation:
            requestRotorPlayerPosition(forward: forward)
        }
    }

    func requestSelectedPlayerInfo() {
        guard gameIsActive || gameFinished else {
            announce("게임이 시작되지 않았습니다.")
            return
        }
        gameRotor.synchronizePlayers(myPlayerID: gamePerspectivePlayerID, players: gamePlayers)
        guard let target = gameRotor.playerTarget else {
            announce("플레이어 정보 없음")
            return
        }
        switch target {
        case .unowned:
            announce("플레이어 정보 없음")
        case .player(let playerID):
            if playerID == gamePerspectivePlayerID {
                socket.send(WireMessages.informationQuery(queryType: "player_info"))
            } else {
                socket.send(WireMessages.informationQuery(
                    queryType: "player_info",
                    payload: ["opponent_player_id": playerID]
                ))
            }
        }
    }

    private func playerRotorTargetName(_ target: GameRotorPlayerTarget) -> String {
        switch target {
        case .unowned:
            return "미소유"
        case .player(let playerID):
            if playerID == myPlayerID { return "당신" }
            return gamePlayers.first(where: { $0.playerID == playerID })?.nickname ?? "플레이어 \(playerID)"
        }
    }

    private func requestRotorPlayerPosition(forward: Bool) {
        guard gameIsActive || gameFinished else {
            announce("게임이 시작되지 않았습니다.")
            return
        }
        gameRotor.synchronizePlayers(myPlayerID: gamePerspectivePlayerID, players: gamePlayers)
        guard let playerID = gameRotor.movePlayerPositionTarget(
            forward: forward,
            myPlayerID: gamePerspectivePlayerID,
            players: gamePlayers
        ) else {
            announce("플레이어 위치 정보 없음")
            return
        }
        pendingPlayerPositionTargetIDs.append(playerID)
        socket.send(WireMessages.informationQuery(queryType: "player_positions"))
    }

    private func requestRotorPlayerCity(forward: Bool) {
        guard gameIsActive || gameFinished else {
            announce("게임이 시작되지 않았습니다.")
            return
        }
        gameRotor.synchronizePlayers(myPlayerID: gamePerspectivePlayerID, players: gamePlayers)
        guard let target = gameRotor.playerTarget else {
            announce("플레이어 정보 없음")
            return
        }
        switch target {
        case .unowned:
            let index = gameRotor.nextUnownedCityIndex(forward: forward)
            socket.send(WireMessages.informationQuery(
                queryType: "city_info",
                payload: ["filter": "unowned", "index": index]
            ))
        case .player(let playerID):
            if playerID == gamePerspectivePlayerID {
                let index = gameRotor.nextOwnedCityIndex(forward: forward)
                socket.send(WireMessages.informationQuery(
                    queryType: "city_info",
                    payload: ["filter": "owned", "index": index]
                ))
            } else {
                let index = gameRotor.nextOpponentCityIndex(forward: forward)
                socket.send(WireMessages.informationQuery(
                    queryType: "city_info",
                    payload: [
                        "filter": "opponent",
                        "index": index,
                        "opponent_player_id": playerID,
                    ]
                ))
            }
        }
    }

    private func requestRotorCityInformation(forward: Bool) {
        requestCurrentCityInformation(gameRotor.moveCityInformationKind(forward: forward))
    }

    /// 로터 상태와 무관하게 현재 선택 도시의 통행료를 조회하는 전역 보드 동작.
    /// 기존 비용 및 설명 로터가 사용하는 city_cost/toll 경로를 그대로 재사용하며
    /// 로터의 현재 범주/하위 선택은 변경하지 않는다.
    func requestCurrentCityToll() {
        requestCurrentCityInformation(.toll)
    }

    private func requestCurrentCityInformation(_ kind: GameRotorCityInformationKind) {
        guard let cell = currentBoardCell, cell.isCity, let cityID = cell.cityID else {
            announce("도시가 아닙니다")
            return
        }
        if kind == .description {
            if gameIsActive || gameFinished {
                socket.send(WireMessages.informationQuery(queryType: "city_description", cityID: cityID))
                return
            }
            guard let catalog = staticInformationCatalog else {
                announce("정적 정보가 아직 준비되지 않았습니다.")
                return
            }
            let text = InformationResultPresenter.format(
                queryType: "city_description",
                result: InformationResult(info: catalog.cityDescription(cityID: cityID)),
                myPlayerID: informationSelfPlayerID
            ) ?? "도시 설명을 찾을 수 없습니다."
            announce(text)
            return
        }
        guard let costType = kind.cityCostType else { return }
        guard gameIsActive || gameFinished else {
            let guide: String
            switch costType {
            case "toll": guide = CityCostQueryKind.toll.preGameGuide
            case "acquisition": guide = CityCostQueryKind.acquisition.preGameGuide
            default: guide = CityCostQueryKind.sale.preGameGuide
            }
            announce(guide)
            return
        }
        socket.send(WireMessages.informationQuery(
            queryType: "city_cost",
            cityID: cityID,
            payload: ["cost_type": costType]
        ))
    }

    private func requestRotorUnitCost(forward: Bool) {
        guard let cell = currentBoardCell, cell.isCity, let cityID = cell.cityID else {
            announce("도시가 아닙니다")
            return
        }
        guard let catalog = staticInformationCatalog else {
            announce("정적 정보가 아직 준비되지 않았습니다.")
            return
        }
        let types = catalog.buildingTypes(cityID: cityID)
        guard let buildingType = gameRotor.currentUnitBuildingType(availableTypes: types) else {
            announce("건물 정보 없음")
            return
        }
        let valueKind = gameRotor.moveUnitValueKind(forward: forward)
        if gameIsActive || gameFinished {
            socket.send(WireMessages.informationQuery(
                queryType: "building_value_info",
                cityID: cityID,
                payload: [
                    "building_type": buildingType,
                    "value_field": valueKind.valueField,
                ]
            ))
            return
        }
        let info = catalog.buildingValue(cityID: cityID, buildingType: buildingType)
        let text = InformationResultPresenter.format(
            queryType: "building_value_info",
            result: InformationResult(info: info),
            myPlayerID: informationSelfPlayerID,
            valueField: valueKind.valueField
        ) ?? "건물 정보를 찾을 수 없습니다."
        announce(text)
    }

    private func announceCurrentBoardCell() {
        announce(currentBoardAccessibilityDescription)
    }


    func requestGameStart() {
        guard roomEntry != nil, hasJoinedTeam, !gameIsActive, !isGameStartPending else { return }
        guard aiSelectionRequest == nil, activeInteraction == nil else { return }
        guard let userID = session?.identity.userID,
              let authority = roomUpdate?.gameStartAuthorityUserID
        else {
            announce("현재 게임 시작 권한 정보를 확인할 수 없습니다.")
            return
        }
        guard userID == authority else {
            announce("게임 시작 권한이 있는 사용자만 게임을 시작할 수 있습니다.")
            return
        }
        guard canRequestGameStart else { return }
        isGameStartPending = true
        socket.send(WireMessages.gameStart())
    }

    func setAISelected(_ aiID: String, selected: Bool) {
        guard let request = aiSelectionRequest,
              request.availableAI.contains(where: { $0.aiID == aiID }) else { return }
        if selected {
            aiSelectionHistory.removeAll { $0 == aiID }
            selectedAIIDs.insert(aiID)
            aiSelectionHistory.append(aiID)
            if selectedAIIDs.count > request.maximumAICount,
               aiSelectionHistory.count >= 2 {
                let victim = aiSelectionHistory[aiSelectionHistory.count - 2]
                selectedAIIDs.remove(victim)
                aiSelectionHistory.removeAll { $0 == victim }
            }
        } else {
            selectedAIIDs.remove(aiID)
            aiSelectionHistory.removeAll { $0 == aiID }
        }
    }

    func confirmAISelection() {
        guard let request = aiSelectionRequest else { return }
        guard canCurrentUserStartGame else {
            announce("게임 시작 권한이 있는 사용자만 게임을 시작할 수 있습니다.")
            return
        }
        guard canConfirmAISelection(request) else {
            alertMessage = "AI 플레이어를 선택하세요"
            return
        }
        let selected = request.availableAI.map(\.aiID).filter { selectedAIIDs.contains($0) }
        socket.send(WireMessages.gameStartAISelectionResponse(requestID: request.requestID, selectedAIIDs: selected))
        clearAISelection()
        isGameStartPending = true
    }

    func cancelAISelection() {
        guard let request = aiSelectionRequest else { return }
        socket.send(WireMessages.gameStartAISelectionCancel(requestID: request.requestID))
        clearAISelection()
        isGameStartPending = false
    }

    private func clearAISelection() {
        aiSelectionRequest = nil
        selectedAIIDs = []
        aiSelectionHistory = []
    }

    func interactionDescription(_ request: InteractionRequestSnapshot) -> String {
        let cityInformation: [Int: InformationInfo] = Dictionary(uniqueKeysWithValues: gameCities.compactMap { info in
            guard let cityID = info.cityID else { return nil }
            return (cityID, info)
        })
        let playerNicknames = Dictionary(uniqueKeysWithValues: gamePlayers.map { ($0.playerID, $0.nickname) })
        return InteractionRequestPresenter.description(
            request,
            cityInformation: cityInformation,
            myPlayerID: myPlayerID,
            playerNicknames: playerNicknames
        )
    }

    func liquidationMarbleInfo(
        _ request: InteractionRequestSnapshot,
        selectedSellValue: Int
    ) -> String {
        InteractionRequestPresenter.liquidationMarbleInfo(
            request,
            selectedSellValue: selectedSellValue
        )
    }

    func announceLiquidationSelectionChanged(
        _ request: InteractionRequestSnapshot,
        selectedSellValue: Int
    ) {
        guard let text = InteractionRequestPresenter.liquidationSelectionChanged(
            request,
            selectedSellValue: selectedSellValue
        ) else { return }
        announce(text)
    }

    func respondToInteraction(responseType: String, payload: [String: Any] = [:]) {
        guard !isSpectating, entryPhase == .active,
              let request = activeInteraction, !interactionResponseSubmitted else { return }
        interactionResponseSubmitted = true

        // For modal interactions, install a narrow result gate before the response leaves
        // the device. Server result presentations then queue behind it. A same-flow next
        // request releases the gate so its result is heard before the next panel replaces
        // this one; final flow completion releases it only after the sheet is gone.
        if request.interactionType != "select_destination" {
            armInteractionResultGate(for: request)
        }

        socket.send(WireMessages.interactionResponse(
            requestID: request.requestID,
            responseType: responseType,
            payload: payload
        ))
    }

    func cancelActiveInteraction() {
        guard let request = activeInteraction else { return }
        guard request.cancellable else {
            announce("취소할 수 없습니다.")
            return
        }
        respondToInteraction(responseType: "cancelled")
    }

    func interactionItemLabel(
        _ item: InteractionItemSnapshot,
        request: InteractionRequestSnapshot,
        role: String? = nil
    ) -> String {
        guard let cityID = item.cityID else { return item.label }

        let information: InformationInfo?
        if let live = gameCities.first(where: { $0.cityID == cityID }) {
            information = live
        } else if let snapshot = item.information {
            information = snapshot
        } else if let cell = boardCatalog?.cells.first(where: { $0.cityID == cityID }) {
            information = InformationInfo(
                cityID: cityID,
                cityName: cell.name,
                groupName: cell.group
            )
        } else {
            information = nil
        }

        guard let information else { return item.label }

        let formatted = InteractionCityItemPresenter.format(
            information: information,
            missionType: request.missionType,
            role: role,
            cost: item.cost,
            atMax: item.atMax,
            disabled: item.disabled,
            myPlayerID: myPlayerID
        )
        return formatted.isEmpty ? item.label : formatted
    }

    private func handleAISelectionRequired(_ data: [String: Any]) {
        guard !isSpectating else { return }
        do {
            let request = try AIPlayerSelectionParser.parse(data)
            guard request.roomID == roomEntry?.roomID, canCurrentUserStartGame else { return }
            if aiSelectionRequest?.requestID == request.requestID { return }
            aiSelectionRequest = request
            selectedAIIDs = []
            aiSelectionHistory = []
            isGameStartPending = false
        } catch {
            return
        }
    }

    private func handleAISelectionCancelled(_ data: [String: Any]) {
        guard !isSpectating else { return }
        guard data["type"] as? String == "game_start_ai_selection_cancelled",
              let roomID = WireScalarParser.exactInt(data["room_id"]), roomID == roomEntry?.roomID,
              let requestID = data["request_id"] as? String,
              requestID == requestID.trimmingCharacters(in: .whitespacesAndNewlines), !requestID.isEmpty,
              aiSelectionRequest?.requestID == requestID
        else { return }
        clearAISelection()
        isGameStartPending = false
    }

    private func handleGameStartFestivalCities(_ data: [String: Any]) {
        guard data["type"] as? String == "game_start_festival_cities",
              let rawIDs = data["festival_city_ids"] as? [Any], !rawIDs.isEmpty else { return }
        let ids = rawIDs.compactMap(WireScalarParser.exactInt)
        guard ids.count == rawIDs.count,
              ids.allSatisfy({ $0 > 0 }),
              Set(ids).count == ids.count,
              let boardCatalog else { return }
        let names = ids.sorted().compactMap { cityID in
            boardCatalog.cells.first(where: { $0.cityID == cityID })?.name
        }
        guard names.count == ids.count else { return }
        let message = "축제 도시는 \(names.joined(separator: ", "))입니다."
        output.emit(.gameEvent(message))
    }

    private func handleGameStartTurnOrderEvent(_ data: [String: Any]) {
        guard data["type"] as? String == "game_start_turn_order_event",
              let event = data["event"] as? String else { return }
        let message: String?
        switch event {
        case "preparing":
            message = "플레이 순서를 정합니다."
        case "personal_roll":
            guard let high = WireScalarParser.exactInt(data["high_die"]),
                  let low = WireScalarParser.exactInt(data["low_die"]),
                  let total = WireScalarParser.exactInt(data["total"]),
                  let isDouble = WireScalarParser.exactBool(data["is_double"]),
                  high > 0, low > 0, total == high + low else { return }
            message = isDouble
                ? "플레이 순서 주사위 결과는 \(high), \(low), 합계 \(total), 더블입니다."
                : "플레이 순서 주사위 결과는 \(high), \(low), 합계 \(total)입니다."
        case "first_player":
            guard let playerID = WireScalarParser.exactInt(data["player_id"]), playerID > 0,
                  let nickname = data["nickname"] as? String,
                  !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if !isSpectating,
               let userID = WireScalarParser.exactInt(data["user_id"]),
               userID == session?.identity.userID {
                message = "당신이 선입니다."
            } else {
                message = "\(KoreanPresentationText.subject(nickname.trimmingCharacters(in: .whitespacesAndNewlines))) 선입니다."
            }
        default:
            return
        }
        guard let message else { return }
        // client(393)는 플레이 순서 구조화 이벤트를 출력 큐와 별개로
        // 메시지 창에 항상 기록한다. Voice/TTS는 아래 plan이 담당한다.
        roomMessages.append(.standard(message))
        switch event {
        case "preparing":
            output.emit(PresentationPlan(
                root: .voice(clip: "dice_order.wav", fallbackTTS: message),
                category: .gameplay,
                queuePolicy: .enqueue,
                interruptRetention: .preservePending
            ))
        case "first_player":
            let firstUserID = WireScalarParser.exactInt(data["user_id"])
            let useFirstPlayerVoice = (!isSpectating && firstUserID == session?.identity.userID)
                || (isSpectating && firstUserID == spectatorRegistration?.observedUserID)
            if useFirstPlayerVoice {
                output.emit(PresentationPlan(
                    root: .voice(clip: "first_player.wav", fallbackTTS: message),
                    category: .systemUI,
                    queuePolicy: .enqueue,
                    interruptRetention: .preservePending
                ))
            } else {
                output.emit(.systemTTS(message, preservePending: true))
            }
        default:
            output.emit(.systemTTS(message, preservePending: true))
        }
    }

    private func handleGameStarted(_ data: [String: Any]) {
        if isSpectating {
            // game_started는 관전 대상 presentation stream에도 전달된다. 관전자는
            // payload의 your_player_id를 조작 권한(myPlayerID)으로 저장하지 않는다.
            gameRotor.reset()
            resetPrivateTurnPreparationState()
            clearInteractionPresentationGates()
            activeInteraction = nil
            interactionResponseSubmitted = false
            let message = "게임을 시작합니다."
            output.emit(.gameEvent(message, root: .sequence([
                .voice(clip: "game_start.wav", fallbackTTS: message)
            ])))
            return
        }

        do {
            let snapshot = try GameplayParser.gameStarted(data)
            resetAIRemainderOutputMode()
            gamePlayers = snapshot.players
            gameCities = snapshot.cities
            gameIsActive = true
            gameFinished = false
            myPlayerID = snapshot.yourPlayerID
            currentPlayerID = snapshot.currentPlayerID
            staticInformationCatalog = snapshot.staticInformation
            gameRotor.reset()
            gameRotor.synchronizePlayers(myPlayerID: snapshot.yourPlayerID, players: snapshot.players)
            pendingPlayerPositionTargetIDs = []
            currentTurnGeneration = nil
            nextTurnCommand = "roll_dice"
            turnCommandWindowOpen = false
            turnActionStarted = false
            isGameStartPending = false
            clearAISelection()
            clearInteractionPresentationGates()
            activeInteraction = nil
            interactionResponseSubmitted = false
            activatedInteractionRequestIDs = []
            boardCatalog = snapshot.boardCatalog
            boardCursor.reset()
            resetPrivateTurnPreparationState()
            refreshHeldCardStateSilently()
            let message = "게임을 시작합니다."
            output.emit(.gameEvent(message, root: .sequence([
                .voice(clip: "game_start.wav", fallbackTTS: message)
            ])))
        } catch {
            return
        }
    }

    private func handleGameState(_ data: [String: Any]) {
        if isSpectating {
            guard spectatorPhase == .bootstrapping || spectatorPhase == .active,
                  let registration = spectatorRegistration
            else { return }
            do {
                let snapshot = try GameplayParser.gameState(data)
                let matches = snapshot.players.filter { $0.userID == registration.observedUserID }
                guard matches.count == 1 else {
                    abortSpectatorBootstrap(message: "관전 대상의 게임 정보를 확인할 수 없습니다.")
                    return
                }

                // spectator_joined 뒤 board_cells/room_update보다 game_state가 먼저
                // 도착할 수 있다. PC client(393)처럼 최신 snapshot 하나만 보관해
                // GameRoomView/bootstrap이 준비된 뒤 공통 적용 경로를 탄다.
                if spectatorPhase == .bootstrapping,
                   (!spectatorBootstrapBoardApplied || roomUpdate == nil) {
                    pendingSpectatorGameState = snapshot
                    return
                }

                applySpectatorGameState(snapshot, registration: registration)
            } catch {
                abortSpectatorBootstrap(message: "게임 상태를 적용할 수 없습니다.")
            }
            return
        }

        guard gameIsActive || gameFinished else { return }
        do {
            let snapshot = try GameplayParser.gameState(data)
            gamePlayers = snapshot.players
            gameCities = snapshot.cities
            gameRotor.synchronizePlayers(myPlayerID: myPlayerID, players: snapshot.players)
            if let current = snapshot.currentPlayerID { currentPlayerID = current }
            refreshAIRemainderOutputMode()
            refreshHeldCardStateSilently()
        } catch {
            return
        }
    }

    private func applySpectatorGameState(
        _ snapshot: GameStateSnapshot,
        registration: SpectatorRegistrationSnapshot
    ) {
        let matches = snapshot.players.filter { $0.userID == registration.observedUserID }
        guard matches.count == 1 else {
            abortSpectatorBootstrap(message: "관전 대상의 게임 정보를 확인할 수 없습니다.")
            return
        }

        let wasFinished = gameFinished
        gamePlayers = snapshot.players
        gameCities = snapshot.cities
        myPlayerID = nil
        currentPlayerID = snapshot.currentPlayerID

        if snapshot.gameLifecycle == "finished" {
            gameIsActive = false
            gameFinished = true
            turnDeadlineWarning.stop(preserveZeroSFX: false)
            currentTurnGeneration = nil
            turnCommandWindowOpen = false
            turnActionStarted = false
        } else {
            gameIsActive = true
            gameFinished = false
        }

        let perspectiveID = matches[0].playerID
        if wasFinished && snapshot.gameLifecycle != "finished" {
            gameRotor.reset()
            resetAIRemainderOutputMode()
        }
        gameRotor.synchronizePlayers(myPlayerID: perspectiveID, players: snapshot.players)
        refreshAIRemainderOutputMode()
        synchronizeSpectatorSceneAudio(snapshot: snapshot, perspectivePlayerID: perspectiveID)
    }

    private func synchronizeSpectatorSceneAudio(
        snapshot: GameStateSnapshot,
        perspectivePlayerID: Int
    ) {
        guard snapshot.gameLifecycle != "finished" else {
            spectatorSceneBootstrapPending = false
            output.stopBGM()
            return
        }

        let replayPrompt = spectatorSceneBootstrapPending
        spectatorSceneBootstrapPending = false

        if snapshot.worldTravelSelectionPlayerID == perspectivePlayerID {
            audio.playBGM("airplane.mp3", loop: true)
            if replayPrompt {
                let prompt = "목적지를 선택하고 두 손가락으로 두 번 탭하세요."
                output.emit(PresentationPlan(
                    root: .sequence([
                        .voice(clip: "select_area.wav", fallbackTTS: nil),
                        .tts(prompt)
                    ]),
                    category: .gameplay,
                    queuePolicy: .enqueue,
                    interruptRetention: .preservePending
                ))
            }
            return
        }
        guard let player = snapshot.players.first(where: { $0.playerID == perspectivePlayerID }),
              let cell = boardCatalog?.cell(at: player.position),
              cell.cellType == "WORLD_TRAVEL"
        else {
            output.stopBGM()
            return
        }
        audio.playBGM("airport_world.mp3", loop: true)
    }

    private func handleNotification(_ data: [String: Any]) {
        guard let type = GameplayParser.notificationType(data),
              let payload = GameplayParser.notificationPayload(data) else { return }

        updatePrivateTurnPreparationState(notificationType: type, payload: payload)

        if type == "turn_started" {
            activatePendingAIRemainderOnTurnStarted()
            if turnDeadlineWarning.hasPendingZeroSFX {
                output.enqueueAsyncBarrier { [weak self] completion in
                    guard let self else { completion(); return }
                    self.turnDeadlineWarning.waitForPendingZeroSFX(completion)
                }
            }
            turnCommandWindowOpen = false
            turnActionStarted = false
            guard let turn = try? GameplayParser.turnStarted(data) else { return }
            currentPlayerID = turn.playerID
            currentTurnGeneration = turn.turnGeneration
            nextTurnCommand = turn.nextTurnCommand
            if turn.playerID == myPlayerID {
                let expectedPlayerID = turn.playerID
                let expectedGeneration = turn.turnGeneration
                output.enqueueBarrier { [weak self] in
                    guard let self,
                          self.currentPlayerID == expectedPlayerID,
                          self.currentPlayerID == self.myPlayerID,
                          self.currentTurnGeneration == expectedGeneration
                    else { return }
                    self.socket.send(WireMessages.turnReady(turnGeneration: expectedGeneration))
                    self.turnCommandWindowOpen = true
                }
            }
        } else if type == "turn_activated" {
            let playerID = WireScalarParser.exactInt(payload["player_id"])
            let generation = WireScalarParser.exactInt(payload["turn_generation"])
            let perspectivePlayerID = gamePerspectivePlayerID
            if isSpectating, currentTurnGeneration == nil, playerID == perspectivePlayerID,
               let generation {
                // ACTIVE 턴 도중 관중석에 들어오면 bootstrap turn_activated가
                // 과거 TURN_STARTED를 대신해 presentation lifecycle을 연다.
                currentTurnGeneration = generation
                if let next = payload["next_turn_command"] as? String, !next.isEmpty {
                    nextTurnCommand = next
                }
            }
            if playerID == perspectivePlayerID,
               generation == currentTurnGeneration,
               currentPlayerID == perspectivePlayerID {
                let remaining = WireScalarParser.nonBooleanNumber(payload["turn_remaining_seconds"])?.doubleValue
                let deadline = payload["turn_deadline_at"] as? String
                _ = turnDeadlineWarning.startForTurn(
                    playerID: playerID,
                    localPlayerID: perspectivePlayerID,
                    turnGeneration: generation,
                    turnDeadlineAt: deadline,
                    turnRemainingSeconds: remaining
                )
            }
        } else if type == "turn_ended" {
            turnDeadlineWarning.stop(preserveZeroSFX: true)
            turnCommandWindowOpen = false
            turnActionStarted = false
            currentTurnGeneration = nil
        } else if type == "game_over" {
            turnDeadlineWarning.stop(preserveZeroSFX: true)
            turnCommandWindowOpen = false
            turnActionStarted = false
            currentTurnGeneration = nil
            gameIsActive = false
            gameFinished = true
            clearInteractionPresentationGates()
            activeInteraction = nil
            interactionResponseSubmitted = false
        } else if type == "roll_dice_rejected" {
            if let playerID = WireScalarParser.exactInt(payload["player_id"]),
               myPlayerID != nil, playerID != myPlayerID { return }
            turnActionStarted = false
        } else if type == "arrived",
                  let playerID = WireScalarParser.exactInt(payload["player_id"]),
                  let index = WireScalarParser.exactInt(payload["to_index"]), (1...32).contains(index),
                  playerID == gamePerspectivePlayerID {
            boardCursor.jump(to: index)
            gameRotor.resetBoardCellSelections()
        }

        let context = GamePresentationContext(
            localPlayerID: myPlayerID,
            presentationPlayerID: gamePerspectivePlayerID,
            players: gamePlayers,
            boardCatalog: boardCatalog,
            cities: gameCities
        )
        if let plan = GameNotificationPresenter.build(
            notificationType: type,
            payload: payload,
            context: context
        ) {
            output.emit(plan)
            if type == "game_over", aiRemainderTextOnly, let result = plan.persistentNotice, !result.isEmpty {
                // client(393): AI remainder의 진행 GAMEPLAY 음향은 무음이지만
                // 최종 승자 결과 한 줄은 SYSTEM_UI TTS로 예외 출력한다.
                output.emit(.systemTTS(result, preservePending: true))
            }
        }
        if type == "game_over" { resetAIRemainderOutputMode() }
    }

    private func refreshHeldCardStateSilently() {
        guard gameIsActive, let myPlayerID, !pendingSilentHeldCardQuery else { return }
        pendingSilentHeldCardQuery = true
        socket.send(WireMessages.informationQuery(queryType: "held_card", playerID: myPlayerID))
    }

    private func applyHeldCardInformation(_ result: InformationResult) {
        heldCardID = result.info?.heldCardID
        heldCardName = result.info?.heldCardName
        if heldCardID != "island_escape" { islandEscapeCardSelected = false }
        if heldCardID != "salary_booster" { salaryBoosterSelected = false }
    }

    private func resetPrivateTurnPreparationState() {
        heldCardID = nil
        heldCardName = nil
        bailPaymentSelected = false
        islandEscapeCardSelected = false
        salaryBoosterSelected = false
        pendingSilentHeldCardQuery = false
    }

    private func updatePrivateTurnPreparationState(notificationType: String, payload: [String: Any]) {
        guard !isSpectating else { return }
        let playerID = WireScalarParser.exactInt(payload["player_id"])
        if let playerID, let myPlayerID, playerID != myPlayerID { return }

        switch notificationType {
        case "card_held":
            heldCardID = payload["card_id"] as? String
            heldCardName = payload["card_name"] as? String
            if heldCardID != "island_escape" { islandEscapeCardSelected = false }
            if heldCardID != "salary_booster" { salaryBoosterSelected = false }
        case "bail_payment_selection_changed":
            guard let selected = payload["selected"] as? Bool else { return }
            bailPaymentSelected = selected
            if selected { islandEscapeCardSelected = false }
        case "held_card_use_selection_changed":
            guard let selected = payload["selected"] as? Bool,
                  let cardType = payload["card_type"] as? String else { return }
            if cardType == "island_escape" {
                islandEscapeCardSelected = selected
                if selected { bailPaymentSelected = false }
            } else if cardType == "salary_booster" {
                salaryBoosterSelected = selected
            }
        case "bail_paid":
            bailPaymentSelected = false
        case "player_escaped_island":
            bailPaymentSelected = false
            islandEscapeCardSelected = false
            refreshHeldCardStateSilently()
        case "salary_paid":
            if salaryBoosterSelected { salaryBoosterSelected = false }
            refreshHeldCardStateSilently()
        case "player_effect_activated":
            if payload["effect_type"] as? String == "salary_booster" {
                salaryBoosterSelected = false
                refreshHeldCardStateSilently()
            }
        default:
            break
        }
    }

    func announceBoardInspectionStarted() {
        announce("보드 조회 모드입니다. 방향 제스처와 정보 제스처를 사용할 수 있습니다.")
    }

    func announceBoardInspectionFinished() {
        announce("인터렉션으로 돌아갑니다.")
    }

    func announceBoardInspectionActionBlocked() {
        announce("보드 조회 중에는 게임 행동을 실행할 수 없습니다.")
    }

    private func refreshAIRemainderOutputMode() {
        if aiRemainderTextOnly { return }
        let condition = AIRemainderOutputPolicy.shouldSuppressGameplayAudio(
            players: gamePlayers,
            gameInProgress: gameIsActive && !gameFinished
        )
        if condition {
            aiRemainderActivationPending = true
        } else {
            aiRemainderActivationPending = false
        }
    }

    private func activatePendingAIRemainderOnTurnStarted() {
        guard aiRemainderActivationPending, !aiRemainderTextOnly else { return }
        let condition = AIRemainderOutputPolicy.shouldSuppressGameplayAudio(
            players: gamePlayers,
            gameInProgress: gameIsActive && !gameFinished
        )
        guard condition else {
            aiRemainderActivationPending = false
            return
        }
        guard output.setFutureGameplayAudioSuppressed(true) else { return }
        aiRemainderActivationPending = false
        aiRemainderTextOnly = true
    }

    private func resetAIRemainderOutputMode() {
        aiRemainderActivationPending = false
        aiRemainderTextOnly = false
        _ = output.setFutureGameplayAudioSuppressed(false)
    }

    private func handleInteractionRequest(_ data: [String: Any]) {
        guard !isSpectating, gameIsActive else { return }
        do {
            let request = try InteractionRequestParser.parse(data)
            if activeInteraction?.requestID == request.requestID
                || pendingInteractionActivation?.requestID == request.requestID { return }

            // A response from the previous panel in the same flow may have result
            // presentation queued behind its gate. Release that gate first; the open
            // barrier below is appended after those already-queued results, so the next
            // panel appears only after the causal result output, without waiting for any
            // later unrelated output.
            if let current = activeInteraction,
               current.flowID == request.flowID,
               current.requestID != request.requestID {
                requestInteractionResultGateRelease(flowID: request.flowID)
            }

            pendingInteractionActivation = request
            // If this replaces a submitted panel in the same flow, keep the old panel
            // disabled until the output boundary reaches the new request. Reset the
            // submitted flag only when the new request actually becomes active.
            turnActionStarted = true

            // OPEN boundary: wait only for presentation that was already queued before
            // this request. Do not enqueue a duplicate question TTS and do not wait for
            // the SwiftUI sheet's appear/focus callback. Once the boundary is reached,
            // publish the request immediately; VoiceOver reads the sheet title/form.
            output.enqueueBarrier { [weak self] in
                guard let self,
                      self.pendingInteractionActivation?.requestID == request.requestID,
                      self.gameIsActive else { return }

                self.pendingInteractionActivation = nil
                self.activeInteraction = request
                self.interactionResponseSubmitted = false

                if request.interactionType == "select_destination",
                   self.activatedInteractionRequestIDs.insert(request.requestID).inserted {
                    self.socket.send(WireMessages.interactionPresentationActivate(requestID: request.requestID))
                }
            }
        } catch {
            return
        }
    }

    private func handleInteractionFlowCompleted(_ data: [String: Any]) {
        guard !isSpectating else { return }
        guard let flowID = data["interaction_flow_id"] as? String,
              !flowID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if pendingInteractionActivation?.flowID == flowID {
            pendingInteractionActivation = nil
        }
        guard activeInteraction == nil || activeInteraction?.flowID == flowID else { return }
        guard let current = activeInteraction else {
            interactionResponseSubmitted = false
            activatedInteractionRequestIDs.removeAll()
            requestInteractionResultGateRelease(flowID: flowID)
            return
        }

        if current.interactionType == "select_destination" {
            output.stopBGM()
            output.enqueueBarrier { [weak self] in
                guard let self, self.activeInteraction?.flowID == flowID else { return }
                self.activeInteraction = nil
                self.interactionResponseSubmitted = false
                self.activatedInteractionRequestIDs.removeAll()
            }
            return
        }

        // CLOSE boundary: remove the modal immediately. Any server result emitted after
        // the local response is already waiting behind the result gate, so it cannot be
        // cut off by the sheet's VoiceOver focus transition. onDismiss releases only
        // that narrow gate; TURN_STARTED and later output then continue in wire order.
        completedInteractionFlowAwaitingDismiss = flowID
        activeInteraction = nil
        interactionResponseSubmitted = false
        activatedInteractionRequestIDs.removeAll()
        scheduleInteractionDismissFallback(flowID: flowID)
    }

    func interactionSheetDidDismiss() {
        guard let flowID = completedInteractionFlowAwaitingDismiss else { return }
        completedInteractionFlowAwaitingDismiss = nil
        requestInteractionResultGateRelease(flowID: flowID)
    }

    private func armInteractionResultGate(for request: InteractionRequestSnapshot) {
        // A submitted request cannot submit again until the server advances the flow.
        // If stale state somehow remains, fail it open rather than stacking gates.
        releaseInteractionResultGateImmediately()

        let token = UUID()
        pendingInteractionResultGate = InteractionResultGate(
            token: token,
            requestID: request.requestID,
            flowID: request.flowID,
            completion: nil,
            releaseRequested: false
        )

        output.enqueueAsyncBarrier { [weak self] completion in
            guard let self, var gate = self.pendingInteractionResultGate, gate.token == token else {
                completion()
                return
            }
            if gate.releaseRequested {
                self.pendingInteractionResultGate = nil
                completion()
                return
            }
            gate.completion = completion
            self.pendingInteractionResultGate = gate
        }
    }

    private func requestInteractionResultGateRelease(flowID: String) {
        guard var gate = pendingInteractionResultGate, gate.flowID == flowID else { return }
        if let completion = gate.completion {
            pendingInteractionResultGate = nil
            completion()
        } else {
            gate.releaseRequested = true
            pendingInteractionResultGate = gate
        }
    }

    private func releaseInteractionResultGateImmediately() {
        guard let gate = pendingInteractionResultGate else { return }
        pendingInteractionResultGate = nil
        gate.completion?()
    }

    private func scheduleInteractionDismissFallback(flowID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.completedInteractionFlowAwaitingDismiss == flowID else { return }
            self.completedInteractionFlowAwaitingDismiss = nil
            self.requestInteractionResultGateRelease(flowID: flowID)
        }
    }

    private func clearInteractionPresentationGates() {
        pendingInteractionActivation = nil
        completedInteractionFlowAwaitingDismiss = nil
        releaseInteractionResultGateImmediately()
    }

    private func dequeuePendingRotorDirection(for queryType: String) -> Bool? {
        guard var queue = pendingRotorDirections[queryType], !queue.isEmpty else { return nil }
        let value = queue.removeFirst()
        if queue.isEmpty { pendingRotorDirections.removeValue(forKey: queryType) }
        else { pendingRotorDirections[queryType] = queue }
        return value
    }

    private func dequeuePendingPlayerPositionTargetID() -> Int? {
        guard !pendingPlayerPositionTargetIDs.isEmpty else { return nil }
        return pendingPlayerPositionTargetIDs.removeFirst()
    }

    private func formatInformationResponse(_ data: [String: Any]) -> String? {
        guard let queryType = data["query_type"] as? String,
              let payload = data["payload"] as? [String: Any],
              let result = InformationParser.result(payload["result"])
        else { return nil }

        if queryType == "held_card", pendingSilentHeldCardQuery {
            pendingSilentHeldCardQuery = false
            applyHeldCardInformation(result)
            return nil
        }

        if queryType == "city_info", let filter = payload["filter"] as? String {
            if let correctedIndex = result.index {
                gameRotor.updateFilteredCityIndex(filter: filter, correctedIndex: correctedIndex)
            }
            if let info = result.info { jumpBoardToInformationCity(info) }
        }

        if queryType == "player_positions", let playerID = dequeuePendingPlayerPositionTargetID() {
            return formatRotorPlayerPositionResponse(result: result, playerID: playerID)
        }

        if queryType == "achieved_monopoly_status" || queryType == "ending_monopoly_alerts" {
            let forward = dequeuePendingRotorDirection(for: queryType) ?? true
            let kind: GameRotorMonopolyKind = queryType == "achieved_monopoly_status" ? .achieved : .endingAlert
            let index = gameRotor.nextMonopolyItemIndex(kind: kind, forward: forward, count: result.items.count)
            return InformationResultPresenter.format(
                queryType: queryType,
                result: result,
                myPlayerID: informationSelfPlayerID,
                index: index
            )
        }

        if queryType == "festival_city_list" || queryType == "olympic_city" || queryType == "active_city_effects" {
            if let forward = dequeuePendingRotorDirection(for: queryType) {
                return formatRotorCityStatusResponse(
                    queryType: queryType,
                    result: result,
                    forward: forward
                )
            }
        }

        let asBuildingStatus = payload["view"] as? String == "building_status"
        return InformationResultPresenter.format(
            queryType: queryType,
            result: result,
            myPlayerID: informationSelfPlayerID,
            valueField: payload["value_field"] as? String,
            filterType: payload["filter"] as? String,
            asBuildingStatus: asBuildingStatus
        )
    }

    private func formatRotorPlayerPositionResponse(
        result: InformationResult,
        playerID: Int
    ) -> String? {
        guard !result.items.isEmpty else {
            return InformationResultPresenter.format(
                queryType: "player_positions",
                result: result,
                myPlayerID: informationSelfPlayerID
            )
        }
        guard let index = result.items.firstIndex(where: { $0.playerID == playerID }) else {
            return "플레이어 위치 정보 없음"
        }

        if let player = gamePlayers.first(where: { $0.playerID == playerID }),
           boardCatalog?.cell(at: player.position) != nil {
            boardCursor.jump(to: player.position)
            gameRotor.resetBoardCellSelections()
        }

        return InformationResultPresenter.format(
            queryType: "player_positions",
            result: result,
            myPlayerID: informationSelfPlayerID,
            index: index
        )
    }

    private func formatRotorCityStatusResponse(
        queryType: String,
        result: InformationResult,
        forward: Bool
    ) -> String? {
        let selectedInfo: InformationInfo?
        switch queryType {
        case "festival_city_list":
            guard !result.items.isEmpty else {
                return InformationResultPresenter.format(
                    queryType: queryType, result: result, myPlayerID: informationSelfPlayerID
                )
            }
            let index = gameRotor.nextCityStatusIndex(kind: .festival, forward: forward, count: result.items.count)
            selectedInfo = result.items[index]
        case "active_city_effects":
            guard !result.items.isEmpty else {
                return InformationResultPresenter.format(
                    queryType: queryType, result: result, myPlayerID: informationSelfPlayerID
                )
            }
            let index = gameRotor.nextCityStatusIndex(kind: .activeEffect, forward: forward, count: result.items.count)
            selectedInfo = result.items[index]
        case "olympic_city":
            selectedInfo = result.info
            if selectedInfo == nil {
                return InformationResultPresenter.format(
                    queryType: queryType, result: result, myPlayerID: informationSelfPlayerID
                )
            }
        default:
            return nil
        }

        guard let selectedInfo else { return nil }
        jumpBoardToInformationCity(selectedInfo)
        guard let cityID = selectedInfo.cityID else {
            return InformationResultPresenter.format(
                queryType: queryType, result: result, myPlayerID: informationSelfPlayerID
            )
        }
        if let fullInfo = gameCities.first(where: { $0.cityID == cityID }) {
            let text = InformationCityPresenter.format(
                fullInfo,
                spec: InformationDisplaySpecs.cityInfo,
                myPlayerID: informationSelfPlayerID
            )
            if !text.isEmpty { return text }
        }
        return InformationResultPresenter.format(
            queryType: queryType, result: result, myPlayerID: informationSelfPlayerID
        )
    }

    private func jumpBoardToInformationCity(_ info: InformationInfo) {
        guard let cityID = info.cityID,
              let index = boardCatalog?.cells.first(where: { $0.cityID == cityID })?.index
        else { return }
        boardCursor.jump(to: index)
        gameRotor.resetBoardCellSelections()
    }

    func createTeamFromDraft() {
        guard canCreateTeam else { return }
        let teamName = teamNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isTeamCreationPending = true
        socket.send(WireMessages.createTeam(teamName: teamName))
    }

    func sendRoomChatFromDraft() {
        guard isInGameRoom else { return }
        if isSpectating {
            guard spectatorPhase == .active else { return }
        }
        let message = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        socket.send(WireMessages.roomChat(message: message))
        chatDraft = ""
    }

    func showLobbyFromGameRoom() {
        guard isInGameRoom else { return }
        screen = .lobby
    }

    func showGameRoom() {
        guard canShowGameRoom else { return }
        screen = .gameRoom
    }

    func requestLeaveRoom() {
        guard canLeaveRoom else { return }
        isLeaveRoomPending = true
        if spectatorRegistration != nil {
            spectatorPhase = .leavePending
            socket.send(WireMessages.leaveSpectator())
        } else {
            socket.send(WireMessages.leaveRoom())
        }
    }

    func openMyProfile() {
        guard let userID = session?.identity.userID else { return }
        Task { await loadProfile(userID: userID) }
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
            handleSessionEntry(data)
            return
        }

        if entryPhase == .recoveryRequired {
            if type == "game_recovery_snapshot" {
                handleGameRecoverySnapshot(data)
            } else if type == "game_recovery_completed" {
                handleGameRecoveryCompleted(data)
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
                // room_created / room_joined는 서버가 membership을 확정한 뒤 보내는
                // 성공 응답이다. 응답이 malformed여도 인증 세션 전체를 끊지 않는다.
                // 이미 확정된 room membership만 명시적으로 되돌린 뒤 대기실을 유지한다.
                isRoomCreationPending = false
                isPresentingCreateRoom = false
                isRoomJoinPending = false
                pendingRoomJoin = nil
                roomJoinPassword = ""
                roomJoinErrorMessage = nil
                isRoomEntryRecoveryPending = true
                socket.send(WireMessages.leaveRoom())
                alertMessage = error.localizedDescription
            }
            return
        }

        switch type {
        case "spectator_target_list":
            handleSpectatorTargetList(data)
        case "spectator_joined":
            handleSpectatorJoined(data)
        case "spectator_left":
            handleSpectatorLeft(data)
        case "game_start_ai_selection_required":
            handleAISelectionRequired(data)
        case "game_start_ai_selection_cancelled":
            handleAISelectionCancelled(data)
        case "game_start_festival_cities":
            handleGameStartFestivalCities(data)
        case "game_start_turn_order_event":
            handleGameStartTurnOrderEvent(data)
        case "game_started":
            handleGameStarted(data)
        case "game_state":
            handleGameState(data)
        case "notification":
            handleNotification(data)
        case "interaction_request":
            handleInteractionRequest(data)
        case "interaction_flow_completed":
            handleInteractionFlowCompleted(data)
        case "information_response":
            if let text = formatInformationResponse(data) {
                output.emit(.systemTTS(text, queuePolicy: .userInputInterrupt))
            }
        case "game_notice":
            if let message = data["message"] as? String, !message.isEmpty {
                output.emit(.gameEvent(message))
            }
        case "board_cells":
            handleBoardCells(data)
        case "room_update":
            handleRoomUpdate(data)
        case "room_event":
            if let message = RoomEventFormatter.message(from: data) {
                roomMessages.append(.standard(message))
                let clip = roomSoundClip(for: data["sound_event"] as? String)
                if let clip {
                    output.emit(PresentationPlan(
                        root: .parallel([
                            .sfx(clip: clip, completion: .startOnly),
                            .tts(message)
                        ]),
                        category: .systemUI,
                        queuePolicy: .enqueue,
                        interruptRetention: .preservePending
                    ))
                } else {
                    output.emit(.systemTTS(message, preservePending: true))
                }
            }
        case "room_sound":
            if let clip = roomSoundClip(for: data["sound_event"] as? String) {
                output.emit(PresentationPlan(
                    root: .sfx(clip: clip, completion: .startOnly),
                    category: .systemUI
                ))
            }
        case "chat":
            handlePrivateChatReceived(data)
        case "chat_sent":
            handlePrivateChatSent(data)
        case "chat_error":
            handlePrivateChatError(data)
        case "note_mailbox":
            handleNoteMailbox(data)
        case "note_received":
            handleNoteReceived(data)
        case "note_sent":
            handleNoteSent(data)
        case "note_marked_read":
            handleNoteMarkedRead(data)
        case "note_recipient_search_result":
            noteRecipientSearchResults = WireParser.socialUsers(from: data["users"])
        case "note_deleted":
            handleNoteDeleted(data)
        case "note_conversation_deleted":
            handleNoteConversationDeleted(data)
        case "room_chat":
            if let chat = try? RoomChatParser.parse(data) {
                roomMessages.append(.chat("\(chat.fromNickname): \(chat.message)"))
                output.emit(PresentationPlan(
                    root: .parallel([
                        .sfx(clip: "chat.wav", completion: .startOnly),
                        .tts("\(chat.fromNickname). \(chat.message)")
                    ]),
                    category: .chat,
                    queuePolicy: .interrupt,
                    interruptRetention: .preservePending
                ))
            }
        case "room_left":
            handleRoomLeft(data)
        case "user_list":
            if let parsed = try? WireParser.lobbyUsers(from: data) {
                users = parsed
                userPresenceLoaded = true
                socialState.mergePresence(parsed)
                syncFriendPresenceNotifications(notify: true)
            }
        case "room_list":
            if let parsed = try? WireParser.rooms(from: data) { rooms = parsed }
        case "invitation_received":
            handleInvitationReceived(data)
        case "invitation_sent":
            handleInvitationSent(data)
        case "invitation_consumed":
            handleInvitationConsumed(data)
        case "invitation_error":
            handleInvitationError(data)
        case "social_state":
            handleSocialState(data)
        case "social_search_result":
            handleSocialSearchResult(data)
        case "friend_request_received":
            handleFriendRequestReceived(data)
        case "friend_request_marked_read":
            handleFriendRequestMarkedRead(data)
        case "friend_request_sent", "friend_request_removed", "friendship_added", "friendship_removed", "user_blocked", "user_unblocked", "social_state_changed":
            requestSocialState()
            if !socialState.searchQuery.isEmpty {
                socket.send(WireMessages.socialSearchUsers(query: socialState.searchQuery))
            }
        case "social_error":
            if data["request_type"] as? String == "friend_request_mark_read" {
                pendingFriendRequestReadIDs.removeAll()
            }
            if let message = data["message"] as? String { alertMessage = message }
        case "note_error":
            if data["request_type"] as? String == "note_mark_read" { pendingNoteReadIDs.removeAll() }
            if let message = data["message"] as? String { alertMessage = message }
        case "error":
            if let message = data["message"] as? String {
                let requestType = data["request_type"] as? String
                if requestType == "invitation_accept" && pendingInvitationID != nil {
                    finishInvitationAcceptanceForRetry(message: message)
                } else if requestType == "get_spectator_targets" && spectatorPhase == .targetListPending {
                    resetPendingSpectatorEntry()
                    alertMessage = message
                } else if requestType == "join_spectator" && spectatorPhase == .joinPending {
                    resetPendingSpectatorEntry()
                    clearRoomPresentationState()
                    alertMessage = message
                    screen = .lobby
                } else if requestType == "join_spectator" && spectatorPhase == .aborting {
                    // 신뢰할 수 없는 spectator_joined 때문에 이미 연결 폐기를
                    // 확정한 상태다. 늦게 온 join 오류로 IDLE에 복귀하지 않는다.
                    alertMessage = message
                } else if requestType == "leave_spectator" && spectatorPhase == .leavePending {
                    spectatorPhase = .active
                    isLeaveRoomPending = false
                    alertMessage = message
                } else if requestType == "leave_spectator" && spectatorPhase == .aborting {
                    // 보상 퇴장까지 실패하면 서버에 stale spectator 등록을 남기지
                    // 않도록 연결 종료 생명주기에 맡긴다. 관중석은 복구하지 않는다.
                    alertMessage = message
                    socket.disconnect(notify: true)
                } else if isRoomCreationPending {
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
                    if isGameStartPending { isGameStartPending = false }
                    alertMessage = message
                }
            }
        default:
            break
        }
    }


    private func handlePrivateChatReceived(_ data: [String: Any]) {
        guard let event = ReceivePayloadParser.privateChat(data) else { return }
        var conversation = privateConversations[event.userID]
            ?? PrivateConversation(userID: event.userID, nickname: event.nickname, lines: [])
        conversation.nickname = event.nickname
        conversation.lines.append(.init(speaker: event.nickname, text: event.message, isMine: false))
        privateConversations[event.userID] = conversation

        let isActivelyViewing = isPrivateMessagesPresented && activePrivateMessageUserID == event.userID
        if isActivelyViewing {
            output.emit(.systemTTS("\(event.nickname). \(event.message)", preservePending: true))
        } else {
            unseenPrivateMessageUserIDs.insert(event.userID)
            output.emit(PresentationPlan(
                root: .parallel([
                    .sfx(clip: "message.wav", completion: .startOnly),
                    .tts("새 메시지가 도착했습니다.")
                ]),
                category: .systemUI,
                queuePolicy: .enqueue,
                interruptRetention: .preservePending
            ))
        }
    }

    private func handlePrivateChatSent(_ data: [String: Any]) {
        guard let event = ReceivePayloadParser.privateChatSent(data) else { return }
        var conversation = privateConversations[event.userID]
            ?? PrivateConversation(userID: event.userID, nickname: event.nickname, lines: [])
        conversation.nickname = event.nickname
        conversation.lines.append(.init(
            speaker: session?.identity.nickname ?? "당신",
            text: event.message,
            isMine: true
        ))
        privateConversations[event.userID] = conversation
        if isPrivateMessagesPresented && activePrivateMessageUserID == event.userID {
            output.emit(.systemTTS(event.message, preservePending: true))
        }
    }

    private func handlePrivateChatError(_ data: [String: Any]) {
        let message = (data["message"] as? String) ?? "상대방에게 메시지를 보낼 수 없습니다."
        alertMessage = message
        output.emit(.systemTTS(message, preservePending: true))
    }

    private func handleNoteMailbox(_ data: [String: Any]) {
        guard let parsed = ReceivePayloadParser.notes(from: data) else { return }
        notes = parsed
        pendingNoteReadIDs = pendingNoteReadIDs.filter { noteID in
            parsed.contains(where: { $0.noteID == noteID && !$0.isRead })
        }
        let unseen = parsed.filter {
            $0.direction == .received && !$0.isRead && !notifiedNoteIDs.contains($0.noteID)
        }
        notifiedNoteIDs.formUnion(unseen.map(\.noteID))
        if !unseen.isEmpty {
            output.emit(.systemTTS("읽지 않은 쪽지가 \(unseen.count)개 있습니다.", preservePending: true))
        }
    }

    private func handleNoteReceived(_ data: [String: Any]) {
        guard let note = ReceivePayloadParser.noteEvent(data, direction: .received) else { return }
        upsertNote(note)
        notifiedNoteIDs.insert(note.noteID)
        let isActive = isNoteMailboxPresented
        let message = isActive ? "\(note.counterpart.nickname). \(note.body)" : "새 쪽지가 도착했습니다."
        output.emit(PresentationPlan(
            root: .parallel([
                .sfx(clip: "memo.wav", completion: .startOnly),
                .tts(message)
            ]),
            category: .systemUI,
            queuePolicy: .enqueue,
            interruptRetention: .preservePending
        ))
    }

    private func handleNoteSent(_ data: [String: Any]) {
        guard let note = ReceivePayloadParser.noteEvent(data, direction: .sent) else { return }
        upsertNote(note)
        output.emit(.systemTTS("\(note.counterpart.nickname)님에게 쪽지를 보냈습니다.", preservePending: true))
    }

    private func handleNoteMarkedRead(_ data: [String: Any]) {
        guard let noteID = WireScalarParser.exactInt(data["note_id"]) else { return }
        pendingNoteReadIDs.remove(noteID)
        if let index = notes.firstIndex(where: { $0.noteID == noteID && $0.direction == .received }) {
            notes[index].isRead = true
        }
    }

    private func handleNoteDeleted(_ data: [String: Any]) {
        guard let noteID = WireScalarParser.exactInt(data["note_id"]) else { return }
        let mailbox = data["mailbox"] as? String
        notes.removeAll { note in
            guard note.noteID == noteID else { return false }
            if mailbox == "received" { return note.direction == .received }
            if mailbox == "sent" { return note.direction == .sent }
            return true
        }
        pendingNoteReadIDs.remove(noteID)
        notifiedNoteIDs.remove(noteID)
        output.emit(.systemTTS("쪽지를 삭제했습니다.", preservePending: true))
    }

    private func handleNoteConversationDeleted(_ data: [String: Any]) {
        guard let userID = WireScalarParser.exactInt(data["target_user_id"]) else { return }
        let removedIDs = Set(notes.filter { $0.counterpart.userID == userID }.map(\.noteID))
        notes.removeAll { $0.counterpart.userID == userID }
        pendingNoteReadIDs.subtract(removedIDs)
        notifiedNoteIDs.subtract(removedIDs)
        output.emit(.systemTTS("이 사람과의 쪽지를 삭제했습니다.", preservePending: true))
    }

    private func upsertNote(_ note: NoteSnapshot) {
        notes.removeAll(where: { $0.noteID == note.noteID && $0.direction == note.direction })
        notes.append(note)
        notes.sort {
            let lhs = $0.createdAt ?? ""
            let rhs = $1.createdAt ?? ""
            if lhs != rhs { return lhs > rhs }
            return $0.noteID > $1.noteID
        }
    }

    private func handleSocialState(_ data: [String: Any]) {
        var parsed = WireParser.socialState(from: data)
        parsed.searchQuery = socialState.searchQuery
        parsed.searchResults = socialState.searchResults
        parsed.mergePresence(users)
        let unreadIDs = Set(parsed.incomingRequests.filter { !$0.isRead }.map(\.requestID))
        pendingFriendRequestReadIDs.formIntersection(unreadIDs)
        let unseen = parsed.incomingRequests.filter {
            !$0.isRead && !notifiedFriendRequestIDs.contains($0.requestID)
        }
        notifiedFriendRequestIDs.formUnion(unseen.map(\.requestID))
        socialState = parsed
        socialStateLoaded = true
        syncFriendPresenceNotifications(notify: false)
        if !unseen.isEmpty {
            output.emit(.systemTTS("새 친구 요청이 \(unseen.count)개 있습니다.", preservePending: true))
        }
    }

    private func handleSocialSearchResult(_ data: [String: Any]) {
        socialState.searchQuery = (data["query"] as? String) ?? socialState.searchQuery
        socialState.searchResults = WireParser.socialUsers(from: data["users"])
        socialState.mergePresence(users)
    }

    private func syncFriendPresenceNotifications(notify: Bool) {
        guard userPresenceLoaded, socialStateLoaded else { return }
        let current = FriendPresenceComparator.snapshot(socialState.friends)
        guard friendPresenceBaselined else {
            friendPresenceSnapshot = current
            friendPresenceBaselined = true
            return
        }
        let changes = notify
            ? FriendPresenceComparator.transitions(previous: friendPresenceSnapshot, current: current)
            : []
        friendPresenceSnapshot = current
        for change in changes {
            let clip = change.isPresent ? "friend_on.wav" : "friend_out.wav"
            let message = change.isPresent
                ? "\(change.nickname)님이 게임에 들어왔습니다."
                : "\(change.nickname)님이 게임을 나갔습니다."
            output.emit(PresentationPlan(
                root: .parallel([
                    .sfx(clip: clip, completion: .startOnly),
                    .tts(message)
                ]),
                category: .systemUI,
                queuePolicy: .enqueue,
                interruptRetention: .preservePending
            ))
        }
    }

    private func handleFriendRequestReceived(_ data: [String: Any]) {
        guard let request = ReceivePayloadParser.friendRequestEvent(data) else {
            requestSocialState()
            return
        }
        socialState.incomingRequests.removeAll(where: { $0.requestID == request.requestID })
        socialState.incomingRequests.append(request)
        socialState.mergePresence(users)
        notifiedFriendRequestIDs.insert(request.requestID)

        let message = "새 친구 요청이 도착했습니다."
        output.emit(PresentationPlan(
            root: .parallel([
                .sfx(clip: "frendship.wav", completion: .startOnly),
                .tts(message)
            ]),
            category: .systemUI,
            queuePolicy: .enqueue,
            interruptRetention: .preservePending
        ))
        requestSocialState()
        if !socialState.searchQuery.isEmpty {
            socket.send(WireMessages.socialSearchUsers(query: socialState.searchQuery))
        }
    }

    private func handleFriendRequestMarkedRead(_ data: [String: Any]) {
        guard let requestID = WireScalarParser.exactInt(data["request_id"]) else { return }
        pendingFriendRequestReadIDs.remove(requestID)
        if let index = socialState.incomingRequests.firstIndex(where: { $0.requestID == requestID }) {
            socialState.incomingRequests[index].isRead = true
        }
    }

    private func handleInvitationReceived(_ data: [String: Any]) {
        let invitation: GameInvitation
        do {
            invitation = try InvitationParser.received(data)
        } catch {
            let message = "초대 정보를 처리하지 못했습니다."
            alertMessage = message
            output.emit(.systemTTS(message, preservePending: true))
            return
        }
        let inboxWasActive = isInvitationInboxPresented

        invitations.removeAll(where: { invitation.replaces($0) })
        invitations.append(invitation)

        let message: String
        if inboxWasActive {
            message = "\(invitation.inviter.nickname)님이 \(invitation.room.title) \(invitation.inviteType.koreanKind)으로 초대했습니다."
        } else {
            message = "새 초대가 도착했습니다."
        }
        output.emit(PresentationPlan(
            root: .parallel([
                .sfx(clip: "invitation.wav", completion: .startOnly),
                .tts(message)
            ]),
            category: .systemUI,
            queuePolicy: .enqueue,
            interruptRetention: .preservePending
        ))
    }

    private func handleInvitationSent(_ data: [String: Any]) {
        guard let sent = try? InvitationParser.sent(data) else { return }
        output.emit(.systemTTS(
            "\(sent.targetNickname)님에게 \(sent.inviteType.koreanKind) 초대를 보냈습니다.",
            preservePending: true
        ))
    }

    private func handleInvitationConsumed(_ data: [String: Any]) {
        guard (try? InvitationParser.consumed(data)) != nil else { return }
        // 서버는 성공 수락 뒤 이 사용자가 받았던 다른 capability도 모두 폐기한다.
        // PC client(393)도 성공 시 초대 창 전체를 닫는다.
        clearInvitationState()
    }

    private func handleInvitationError(_ data: [String: Any]) {
        guard let message = data["message"] as? String, !message.isEmpty else { return }
        let requestType = data["request_type"] as? String
        let inviteID = WireScalarParser.exactInt(data["invite_id"])

        if requestType == "invitation_accept" {
            if let inviteID {
                // invite_id가 있는 invitation_error는 서버 capability 자체가 더 이상
                // 유효하지 않다는 뜻이므로 해당 한 항목만 제거한다.
                invitations.removeAll(where: { $0.inviteID == inviteID })
                if invitations.isEmpty, utilitySheet == .invitations { utilitySheet = nil }
            }
            if pendingInvitationID != nil,
               inviteID == nil || inviteID == pendingInvitationID {
                finishInvitationAcceptanceForRetry(message: message)
                return
            }
        }

        alertMessage = message
        output.emit(.systemTTS(message, preservePending: true))
    }

    private func finishInvitationAcceptanceForRetry(message: String) {
        if pendingInvitationType == .spectator, spectatorPhase == .joinPending {
            resetPendingSpectatorEntry()
        }
        pendingInvitationID = nil
        pendingInvitationType = nil
        alertMessage = message
        output.emit(.systemTTS(message, preservePending: true))
    }

    private func clearInvitationState() {
        invitations.removeAll()
        if utilitySheet == .invitations { utilitySheet = nil }
        pendingInvitationID = nil
        pendingInvitationType = nil
    }

    private func handleSessionEntry(_ data: [String: Any]) {
        do {
            let entry = try SessionEntryParser.parse(data)
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectNeeded = false
            reconnectAttempt = 0
            recoveryEntry = entry

            switch entry.mode {
            case .normalLobby:
                recoverySnapshotApplied = false
                recoveryCompletedSent = false
                recoveryEntry = nil
                entryPhase = .active
                if roomEntry != nil || spectatorRegistration != nil || spectatorPhase != .idle {
                    clearRoomState()
                    screen = .lobby
                }
                requestSocialState()
                requestNoteMailbox()

            case .activeGameRecovery:
                recoverySnapshotApplied = false
                recoveryCompletedSent = false
                entryPhase = .recoveryRequired
                turnCommandWindowOpen = false
                turnDeadlineWarning.stop(preserveZeroSFX: false)
            }
        } catch {
            socket.disconnect()
            returnToLogin(message: "서버의 로그인 상태 응답이 올바르지 않습니다.\n다시 로그인해 주세요.")
        }
    }

    private func handleGameRecoverySnapshot(_ data: [String: Any]) {
        guard entryPhase == .recoveryRequired,
              let entry = recoveryEntry,
              entry.mode == .activeGameRecovery,
              !recoverySnapshotApplied else { return }

        let snapshot: GameRecoverySnapshot
        do {
            snapshot = try GameRecoveryParser.parse(data)
        } catch {
            socket.disconnect()
            returnToLogin(message: "게임 복구 정보를 적용할 수 없습니다.\n다시 로그인해 주세요.")
            return
        }

        // 이전 reconnect 시도의 늦은 snapshot은 현재 복구를 훼손하지 않는다.
        guard snapshot.recoveryID == entry.recoveryID else { return }
        guard snapshot.roomID == entry.roomID,
              snapshot.gameSessionID == entry.gameSessionID,
              snapshot.yourPlayerID == entry.yourPlayerID else {
            socket.disconnect()
            returnToLogin(message: "게임 복구 정보를 적용할 수 없습니다.\n다시 로그인해 주세요.")
            return
        }

        // transient disconnect 복구는 기존 게임방 presentation을 보존한다.
        // 만약 화면 전환 중 roomEntry만 비어 있다면 기존 roomUpdate의
        // authoritative host/authority 값을 이용해 같은 방 header만 복원한다.
        if roomEntry == nil,
           let update = roomUpdate,
           update.roomID == snapshot.roomID {
            roomEntry = RoomEntrySnapshot(
                roomID: update.roomID,
                title: update.title,
                maxPlayers: update.maxPlayers,
                isPrivate: update.isPrivate,
                hostUserID: update.hostUserID,
                gameStartAuthorityUserID: update.gameStartAuthorityUserID
            )
        }
        guard roomEntry?.roomID == snapshot.roomID else {
            socket.disconnect()
            returnToLogin(message: "게임 복구 정보를 적용할 수 없습니다.\n다시 로그인해 주세요.")
            return
        }

        turnDeadlineWarning.stop(preserveZeroSFX: false)
        clearAISelection()
        clearInteractionPresentationGates()
        activeInteraction = nil
        interactionResponseSubmitted = false
        activatedInteractionRequestIDs = []

        boardCatalog = snapshot.boardCatalog
        staticInformationCatalog = snapshot.staticInformation
        gamePlayers = snapshot.gameState.players
        gameCities = snapshot.gameState.cities
        gameIsActive = true
        gameFinished = false
        myPlayerID = snapshot.yourPlayerID
        currentPlayerID = snapshot.gameState.currentPlayerID
        currentTurnGeneration = snapshot.turn.turnGeneration
        nextTurnCommand = snapshot.turn.nextTurnCommand ?? "roll_dice"
        turnCommandWindowOpen = false
        turnActionStarted = snapshot.turn.hasStarted
        gameRotor.reset()
        gameRotor.synchronizePlayers(myPlayerID: snapshot.yourPlayerID, players: snapshot.gameState.players)
        pendingRotorDirections = [:]
        pendingPlayerPositionTargetIDs = []

        if let me = snapshot.gameState.players.first(where: { $0.playerID == snapshot.yourPlayerID }) {
            boardCursor.jump(to: me.position)
        } else {
            boardCursor.reset()
        }

        heldCardID = snapshot.heldCard?.cardID
        heldCardName = snapshot.heldCard?.name
        salaryBoosterSelected = snapshot.salaryBoosterCardID != nil
        switch snapshot.islandEscapeReservationType {
        case .bailPayment:
            bailPaymentSelected = true
            islandEscapeCardSelected = false
        case .islandEscapeCard:
            bailPaymentSelected = false
            islandEscapeCardSelected = true
        case nil:
            bailPaymentSelected = false
            islandEscapeCardSelected = false
        }
        pendingSilentHeldCardQuery = false

        resetAIRemainderOutputMode()
        refreshAIRemainderOutputMode()
        screen = .gameRoom

        recoverySnapshotApplied = true
        socket.send(WireMessages.gameRecoveryCompleted(recoveryID: snapshot.recoveryID))
        recoveryCompletedSent = true
    }

    private func handleGameRecoveryCompleted(_ data: [String: Any]) {
        guard entryPhase == .recoveryRequired,
              let entry = recoveryEntry,
              recoverySnapshotApplied,
              recoveryCompletedSent,
              data["recovery_id"] as? String == entry.recoveryID,
              let accepted = WireScalarParser.exactBool(data["accepted"])
        else { return }

        if !accepted {
            if data["entry_mode"] as? String == SessionEntryMode.normalLobby.rawValue,
               let reason = data["reason_code"] as? String,
               !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recoveryEntry = nil
                recoverySnapshotApplied = false
                recoveryCompletedSent = false
                entryPhase = .active
                clearRoomState()
                screen = .lobby
                requestSocialState()
                requestNoteMailbox()
                return
            }
            socket.disconnect()
            returnToLogin(message: "게임 복구를 완료할 수 없습니다.\n다시 로그인해 주세요.")
            return
        }

        guard let rawGameState = data["game_state"] as? [String: Any] else {
            socket.disconnect()
            returnToLogin(message: "게임 복구를 완료할 수 없습니다.\n다시 로그인해 주세요.")
            return
        }

        let gameState: GameStateSnapshot
        let lifecycle: RecoveryCompletionTurnLifecycle
        let pendingInteractionData: [String: Any]?
        do {
            gameState = try GameplayParser.gameState(rawGameState)
            lifecycle = try RecoveryCompletionParser.turnLifecycle(data["turn_lifecycle"])
            if let current = lifecycle.currentPlayerID,
               !gameState.players.contains(where: { $0.playerID == current }) {
                throw GameRecoveryParserError.invalidMessage
            }
            if data["pending_interaction_request"] == nil || data["pending_interaction_request"] is NSNull {
                pendingInteractionData = nil
            } else {
                guard let raw = data["pending_interaction_request"] as? [String: Any] else {
                    throw GameRecoveryParserError.invalidMessage
                }
                _ = try InteractionRequestParser.parse(raw)
                pendingInteractionData = raw
            }
        } catch {
            socket.disconnect()
            returnToLogin(message: "게임 복구를 완료할 수 없습니다.\n다시 로그인해 주세요.")
            return
        }

        gamePlayers = gameState.players
        gameCities = gameState.cities
        gameRotor.synchronizePlayers(myPlayerID: myPlayerID, players: gameState.players)
        currentPlayerID = lifecycle.currentPlayerID
        currentTurnGeneration = lifecycle.turnGeneration
        nextTurnCommand = lifecycle.nextTurnCommand ?? "roll_dice"
        turnActionStarted = lifecycle.hasStarted
        turnCommandWindowOpen = false
        refreshAIRemainderOutputMode()

        recoveryEntry = nil
        recoverySnapshotApplied = false
        recoveryCompletedSent = false
        entryPhase = .active
        screen = .gameRoom
        requestSocialState()
        requestNoteMailbox()

        output.emit(.systemTTS("재접속했습니다.", preservePending: true))
        resumeTurnAfterRecovery(lifecycle)

        if let pendingInteractionData {
            restoreRecoveredInteraction(pendingInteractionData)
        }
        refreshHeldCardStateSilently()
    }

    private func restoreRecoveredInteraction(_ data: [String: Any]) {
        guard let request = try? InteractionRequestParser.parse(data) else { return }
        clearInteractionPresentationGates()
        activeInteraction = request
        interactionResponseSubmitted = false
        turnActionStarted = true
        if request.interactionType == "select_destination" {
            // 서버에서 이미 진행 중인 world-travel request다. presentation
            // activate를 다시 보내지 않고 현재 request를 활성 상태로만 복원한다.
            activatedInteractionRequestIDs.insert(request.requestID)
        }
    }

    private func resumeTurnAfterRecovery(_ lifecycle: RecoveryCompletionTurnLifecycle) {
        turnDeadlineWarning.stop(preserveZeroSFX: false)
        guard gameIsActive, !gameFinished,
              lifecycle.currentPlayerID == myPlayerID,
              lifecycle.humanControlled,
              let generation = lifecycle.turnGeneration else {
            turnCommandWindowOpen = false
            return
        }

        if lifecycle.turnDeadlineAt != nil || lifecycle.turnRemainingSeconds != nil {
            turnCommandWindowOpen = true
            _ = turnDeadlineWarning.startForTurn(
                playerID: lifecycle.currentPlayerID,
                localPlayerID: myPlayerID,
                turnGeneration: generation,
                turnDeadlineAt: lifecycle.turnDeadlineAt,
                turnRemainingSeconds: lifecycle.turnRemainingSeconds
            )
            return
        }

        // PENDING 자기 턴은 PC판과 같이 reconnect 안내가 큐에서 끝난 뒤
        // turn_ready를 보내 새 deadline을 시작한다.
        output.enqueueBarrier { [weak self] in
            guard let self,
                  self.entryPhase == .active,
                  self.currentPlayerID == self.myPlayerID,
                  self.currentTurnGeneration == generation else { return }
            self.socket.send(WireMessages.turnReady(turnGeneration: generation))
            self.turnCommandWindowOpen = true
        }
    }

    private func enterGameRoom(_ snapshot: RoomEntrySnapshot) {
        output.stopAll()
        isRoomEntryRecoveryPending = false
        roomEntry = snapshot
        roomUpdate = nil
        roomMessages = []
        boardCatalog = nil
        staticInformationCatalog = nil
        boardCursor.reset()
        gameRotor.reset()
        clearGameplayState()
        teamNameDraft = session?.identity.nickname ?? ""
        chatDraft = ""
        isTeamCreationPending = false
        isLeaveRoomPending = false
        screen = .gameRoom
    }

    private func handleBoardCells(_ data: [String: Any]) {
        if let registration = spectatorRegistration {
            guard spectatorPhase == .bootstrapping || spectatorPhase == .active else { return }
            do {
                let snapshot = try BoardBootstrapParser.parse(data)
                // 기존 게임 종료 뒤 새 게임 bootstrap의 첫 정적 보드라면
                // 이전 게임의 동적 상태를 먼저 비운다. 같은 live game의 중복
                // board_cells는 멱등 적용한다.
                if gameFinished {
                    clearGameplayState()
                    spectatorSceneBootstrapPending = true
                }
                boardCatalog = snapshot.boardCatalog
                staticInformationCatalog = snapshot.staticInformation
                if snapshot.boardCatalog.cell(at: boardCursor.index) == nil {
                    boardCursor.reset()
                }
                gameRotor.resetBoardCellSelections()
                spectatorBootstrapBoardApplied = true
                if let pending = pendingSpectatorRoomUpdate, pending.roomID == registration.roomID {
                    pendingSpectatorRoomUpdate = nil
                    applySpectatorRoomUpdate(pending)
                }
                activateSpectatorRoomIfReady()
            } catch {
                abortSpectatorBootstrap(message: "관중석 보드 정보를 적용할 수 없습니다.")
            }
            return
        }

        guard roomEntry != nil else { return }
        do {
            let snapshot = try BoardBootstrapParser.parse(data)
            boardCatalog = snapshot.boardCatalog
            staticInformationCatalog = snapshot.staticInformation
            if snapshot.boardCatalog.cell(at: boardCursor.index) == nil {
                boardCursor.reset()
            }
            gameRotor.resetBoardCellSelections()
        } catch {
            // PC 일반 room 경로와 같이 malformed 정적 보드는 기존 정상 상태를
            // 임의 데이터로 덮어쓰지 않고 무시한다.
            return
        }
    }

    private func handleRoomUpdate(_ data: [String: Any]) {
        if let registration = spectatorRegistration {
            guard spectatorPhase == .bootstrapping || spectatorPhase == .active else { return }
            do {
                let snapshot = try RoomUpdateParser.parse(data)
                guard snapshot.roomID == registration.roomID else { return }
                if !spectatorBootstrapBoardApplied {
                    pendingSpectatorRoomUpdate = snapshot
                    return
                }
                applySpectatorRoomUpdate(snapshot)
                activateSpectatorRoomIfReady()
            } catch {
                abortSpectatorBootstrap(message: "관중석 방 정보를 적용할 수 없습니다.")
            }
            return
        }

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

    private func applySpectatorRoomUpdate(_ snapshot: RoomUpdateSnapshot) {
        roomUpdate = snapshot
        isTeamCreationPending = false
        teamNameDraft = ""
    }

    private func handleRoomLeft(_ data: [String: Any]) {
        // malformed room_created / room_joined 뒤의 보상 leave_room ACK는
        // roomEntry를 만들지 않은 상태에서 도착한다. 이 경우에도 복구 완료로
        // 인정하고 인증/웹소켓 세션은 그대로 유지한다.
        if isRoomEntryRecoveryPending {
            isRoomEntryRecoveryPending = false
            clearRoomState()
            screen = .lobby
            return
        }

        guard let currentRoomID = roomEntry?.roomID,
              let roomID = data["room_id"] as? Int,
              roomID == currentRoomID
        else { return }
        clearRoomState()
        screen = .lobby
    }

    private func clearGameplayState() {
        turnDeadlineWarning.stop(preserveZeroSFX: false)
        clearAISelection()
        clearInteractionPresentationGates()
        activeInteraction = nil
        interactionResponseSubmitted = false
        activatedInteractionRequestIDs = []
        gamePlayers = []
        gameCities = []
        gameIsActive = false
        gameFinished = false
        myPlayerID = nil
        currentPlayerID = nil
        currentTurnGeneration = nil
        nextTurnCommand = "roll_dice"
        turnCommandWindowOpen = false
        turnActionStarted = false
        isGameStartPending = false
        resetPrivateTurnPreparationState()
        gameRotor.reset()
        pendingRotorDirections = [:]
        pendingPlayerPositionTargetIDs = []
        resetAIRemainderOutputMode()
    }

    private func clearRoomPresentationState() {
        output.stopAll()
        roomEntry = nil
        roomUpdate = nil
        roomMessages = []
        boardCatalog = nil
        staticInformationCatalog = nil
        boardCursor.reset()
        gameRotor.reset()
        clearGameplayState()
        teamNameDraft = ""
        chatDraft = ""
        isTeamCreationPending = false
        isLeaveRoomPending = false
    }

    private func clearRoomState() {
        clearSpectatorState()
        clearRoomPresentationState()
    }

    private func handleDisconnect(_ message: String) {
        guard screen != .login, session != nil else { return }

        // 초대 capability는 실시간 일시 상태다. 재접속 시 서버가 목록을 재전송하는
        // 계약이 없으므로 끊긴 연결의 로컬 알림 목록을 복구 대상으로 취급하지 않는다.
        clearInvitationState()

        // 관중석은 서버 계약상 복구 대상이 아니다. 연결이 끊기면 서버 등록도
        // 제거되므로 참가자 recovery 상태를 보존하지 않고 로컬 관람만 정리한다.
        if spectatorRegistration != nil || spectatorPhase != .idle {
            clearSpectatorState()
            clearRoomPresentationState()
            screen = .lobby
        }

        if reconnectNeeded {
            if appSceneActive, reconnectTask == nil, !socket.hasActiveConnection {
                scheduleReconnect()
            }
            return
        }

        // iOS background/network interruption is not logout. Keep the authenticated
        // session and the existing room/game presentation intact, close input gates,
        // and re-enter through the server's authoritative session_entry contract.
        reconnectNeeded = true
        entryPhase = .connecting
        turnCommandWindowOpen = false
        turnDeadlineWarning.stop(preserveZeroSFX: false)
        recoveryEntry = nil
        recoverySnapshotApplied = false
        recoveryCompletedSent = false

        if appSceneActive {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard reconnectNeeded, appSceneActive, session != nil, screen != .login else { return }
        reconnectTask?.cancel()
        let attempt = reconnectAttempt
        reconnectAttempt += 1
        let delaySeconds = min(8, attempt == 0 ? 0 : (1 << min(attempt - 1, 3)))

        reconnectTask = Task { @MainActor [weak self] in
            if delaySeconds > 0 {
                try? await Task.sleep(for: .seconds(delaySeconds))
            }
            guard let self, !Task.isCancelled,
                  self.reconnectNeeded, self.appSceneActive,
                  var currentSession = self.session else { return }

            do {
                currentSession.tokens = try await self.api.refreshSession(tokens: currentSession.tokens)
                guard !Task.isCancelled, self.reconnectNeeded, self.appSceneActive else { return }
                self.session = currentSession
                self.entryPhase = .connecting
                self.socket.connect(accessToken: currentSession.tokens.accessToken)
                self.entryPhase = .awaitingSessionEntry
                self.reconnectTask = nil
            } catch let error as APIAuthenticationLostError {
                self.reconnectTask = nil
                self.returnToLogin(message: error.localizedDescription)
            } catch {
                self.reconnectTask = nil
                if self.reconnectNeeded, self.appSceneActive {
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func resetReconnectState() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectNeeded = false
        reconnectAttempt = 0
        recoverySnapshotApplied = false
        recoveryCompletedSent = false
    }

    private func returnToLogin(message: String) {
        socket.disconnect()
        clearAuthenticatedState()
        screen = .login
        if !message.isEmpty { alertMessage = message }
    }

    private func clearAuthenticatedState() {
        resetReconnectState()
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
        isRoomEntryRecoveryPending = false
        clearInvitationState()
        clearReceiveCommunicationState()
        clearRoomState()
    }

    private func clearReceiveCommunicationState() {
        privateConversations.removeAll()
        unseenPrivateMessageUserIDs.removeAll()
        notes.removeAll()
        notifiedNoteIDs.removeAll()
        notifiedFriendRequestIDs.removeAll()
        pendingFriendRequestReadIDs.removeAll()
        pendingNoteReadIDs.removeAll()
        utilitySheet = nil
        activePrivateMessageUserID = nil
        preferredPrivateMessageUserID = nil
        preferredNoteUserID = nil
        preferredFriendRequestID = nil
        noteRecipientSearchResults.removeAll()
        userPresenceLoaded = false
        socialStateLoaded = false
        friendPresenceBaselined = false
        friendPresenceSnapshot.removeAll()
    }

    private func roomSoundClip(for event: String?) -> String? {
        switch event {
        case "room_enter": return "room_enter.wav"
        case "spectator_enter": return "spectator_enter.wav"
        case "spectator_to_room": return "spectator_to_room.wav"
        case "leave": return "leave.wav"
        default: return nil
        }
    }

    func announce(_ message: String) {
        output.emit(.systemTTS(message, queuePolicy: .userInputInterrupt))
    }
}
