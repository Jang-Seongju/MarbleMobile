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
    @Published var boardCatalog: BoardCatalogSnapshot?
    @Published var boardCursor = BoardCursorState()
    @Published var boardAccessibilityMode: BoardAccessibilityMode = .directTouch
    @Published var boardCostCycle = CityCostCycleState()
    @Published var aiSelectionRequest: AIPlayerSelectionRequest?
    @Published var selectedAIIDs: Set<String> = []
    @Published var activeInteraction: InteractionRequestSnapshot?
    @Published var interactionResponseSubmitted = false
    @Published var gamePlayers: [GamePlayerSnapshot] = []
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
    private var isRoomEntryRecoveryPending = false
    private var aiSelectionHistory: [String] = []
    private var activatedInteractionRequestIDs: Set<String> = []
    private var selectedOpponentTeamIndex = 0
    private var selectedOpponentMemberIndex = -1

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
        guard entryPhase == .active, screen == .lobby, roomEntry == nil, !isRoomCreationPending, !isRoomJoinPending, !isRoomEntryRecoveryPending else { return }
        isRoomCreationPending = true
        roomCreationErrorMessage = nil
        socket.send(WireMessages.createRoom(request))
    }

    func beginJoinRoom(_ room: GameRoomSummary) {
        guard entryPhase == .active, screen == .lobby, roomEntry == nil, !isRoomEntryRecoveryPending else { return }
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

    var isBoardReady: Bool {
        hasJoinedTeam && boardCatalog != nil
    }

    var isBoardDirectTouchEnabled: Bool {
        isBoardReady
            && boardAccessibilityMode == .directTouch
            && aiSelectionRequest == nil
            && activeInteraction == nil
    }

    var canRollDice: Bool {
        gameIsActive
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

    var currentBoardCell: BoardCellSnapshot? {
        boardCatalog?.cell(at: boardCursor.index)
    }

    func moveBoardCursorForward() {
        guard boardCatalog != nil else {
            announce("보드 정보가 아직 준비되지 않았습니다.")
            return
        }
        boardCursor.moveNext()
        boardCostCycle.reset()
        announceCurrentBoardCell()
    }

    func moveBoardCursorBackward() {
        guard boardCatalog != nil else {
            announce("보드 정보가 아직 준비되지 않았습니다.")
            return
        }
        boardCursor.movePrevious()
        boardCostCycle.reset()
        announceCurrentBoardCell()
    }

    func cycleBoardCityCostForward() {
        queryBoardCityCost(boardCostCycle.moveForward())
    }

    func cycleBoardCityCostBackward() {
        queryBoardCityCost(boardCostCycle.moveBackward())
    }

    func enterStandardVoiceOverBoardMode() {
        guard isBoardReady else { return }
        boardAccessibilityMode = .standardVoiceOver
        announce("표준 VoiceOver")
    }

    func enterDirectTouchBoardMode() {
        guard isBoardReady else { return }
        boardAccessibilityMode = .directTouch
        announce("다이렉트 터치")
        announceCurrentBoardCell()
    }

    func performBoardMagicTap() {
        performRollDice()
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
        boardCostCycle.reset()
        announceCurrentBoardCell()
    }

    func requestSelectedPlayerInfo() {
        guard gameIsActive, let myPlayerID else {
            announce("게임이 시작되지 않았습니다.")
            return
        }
        var order: [String] = []
        var grouped: [String: [GamePlayerSnapshot]] = [:]
        for player in gamePlayers where player.playerID != myPlayerID {
            if grouped[player.teamName] == nil {
                order.append(player.teamName)
                grouped[player.teamName] = []
            }
            grouped[player.teamName, default: []].append(player)
        }
        guard !order.isEmpty else {
            announce("상대 플레이어 없음")
            return
        }
        selectedOpponentTeamIndex %= order.count
        let team = grouped[order[selectedOpponentTeamIndex]] ?? []
        guard !team.isEmpty else { announce("상대 플레이어 없음"); return }
        selectedOpponentMemberIndex = (selectedOpponentMemberIndex + 1) % team.count
        let player = team[selectedOpponentMemberIndex]
        socket.send(WireMessages.informationQuery(
            queryType: "player_info",
            payload: ["opponent_player_id": player.playerID]
        ))
    }

    private func announceCurrentBoardCell() {
        announce(currentBoardCell?.shortDescription ?? "현재 칸 정보를 찾을 수 없습니다.")
    }

    private func queryBoardCityCost(_ kind: CityCostQueryKind) {
        guard let cell = currentBoardCell else {
            announce("현재 칸 정보를 찾을 수 없습니다.")
            return
        }
        guard cell.isCity, let cityID = cell.cityID else {
            announce("도시가 아닙니다")
            return
        }
        guard gameIsActive else {
            announce(kind.preGameGuide)
            return
        }
        socket.send(WireMessages.informationQuery(
            queryType: "city_cost",
            cityID: cityID,
            payload: ["cost_type": kind.rawValue]
        ))
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
        let count = selectedAIIDs.count
        guard request.humanPlayerCount + count >= 2 else {
            alertMessage = "AI 플레이어를 선택하세요"
            return
        }
        guard request.allowedAICounts.contains(count) else { return }
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

    func respondToInteraction(responseType: String, payload: [String: Any] = [:]) {
        guard let request = activeInteraction, !interactionResponseSubmitted else { return }
        interactionResponseSubmitted = true
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

    func interactionItemLabel(_ item: InteractionItemSnapshot) -> String {
        if let cityID = item.cityID,
           let name = boardCatalog?.cells.first(where: { $0.cityID == cityID })?.name,
           item.label == String(cityID) || item.label == "항목" {
            return name
        }
        return item.label
    }

    func destinationLabel(_ index: Int) -> String {
        guard let cell = boardCatalog?.cell(at: index) else { return "\(index)번 칸" }
        return "\(index)번, \(cell.shortDescription)"
    }

    private func handleAISelectionRequired(_ data: [String: Any]) {
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
        roomMessages.append(message)
        announce(message)
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
            if let userID = WireScalarParser.exactInt(data["user_id"]), userID == session?.identity.userID {
                message = "당신이 선입니다."
            } else {
                message = "\(subjectWithParticle(nickname.trimmingCharacters(in: .whitespacesAndNewlines))) 선입니다."
            }
        default:
            return
        }
        guard let message else { return }
        roomMessages.append(message)
        announce(message)
    }

    private func subjectWithParticle(_ value: String) -> String {
        guard let scalar = value.unicodeScalars.last else { return value }
        let code = Int(scalar.value)
        let hangulBase = 0xAC00
        let hangulLast = 0xD7A3
        guard code >= hangulBase, code <= hangulLast else { return "\(value)가" }
        let hasFinalConsonant = (code - hangulBase) % 28 != 0
        return "\(value)\(hasFinalConsonant ? "이" : "가")"
    }

    private func handleGameStarted(_ data: [String: Any]) {
        do {
            let snapshot = try GameplayParser.gameStarted(data)
            gamePlayers = snapshot.players
            gameIsActive = true
            gameFinished = false
            myPlayerID = snapshot.yourPlayerID
            currentPlayerID = snapshot.currentPlayerID
            currentTurnGeneration = nil
            nextTurnCommand = "roll_dice"
            turnCommandWindowOpen = false
            turnActionStarted = false
            isGameStartPending = false
            clearAISelection()
            activeInteraction = nil
            interactionResponseSubmitted = false
            activatedInteractionRequestIDs = []
            boardCatalog = snapshot.boardCatalog
            boardCursor.reset()
            boardCostCycle.reset()
            boardAccessibilityMode = .directTouch
            roomMessages.append("게임을 시작합니다.")
            announce("게임을 시작합니다.")
        } catch {
            return
        }
    }

    private func handleGameState(_ data: [String: Any]) {
        guard gameIsActive || gameFinished else { return }
        do {
            let snapshot = try GameplayParser.gameState(data)
            gamePlayers = snapshot.players
            if let current = snapshot.currentPlayerID { currentPlayerID = current }
        } catch {
            return
        }
    }

    private func handleNotification(_ data: [String: Any]) {
        guard let type = GameplayParser.notificationType(data),
              let payload = GameplayParser.notificationPayload(data) else { return }

        if type == "turn_started" {
            turnCommandWindowOpen = false
            turnActionStarted = false
            guard let turn = try? GameplayParser.turnStarted(data) else { return }
            currentPlayerID = turn.playerID
            currentTurnGeneration = turn.turnGeneration
            nextTurnCommand = turn.nextTurnCommand
            let nickname = gamePlayers.first(where: { $0.playerID == turn.playerID })?.nickname
            if turn.playerID == myPlayerID {
                socket.send(WireMessages.turnReady(turnGeneration: turn.turnGeneration))
                turnCommandWindowOpen = true
                announce("당신 차례")
            } else if let nickname {
                announce("\(nickname) 차례")
            }
            return
        }

        if type == "turn_ended" {
            turnCommandWindowOpen = false
            turnActionStarted = false
            currentTurnGeneration = nil
            return
        }
        if type == "game_over" {
            turnCommandWindowOpen = false
            turnActionStarted = false
            currentTurnGeneration = nil
            gameIsActive = false
            gameFinished = true
            activeInteraction = nil
            interactionResponseSubmitted = false
            boardAccessibilityMode = .directTouch
            let message = gameOverMessage(payload)
            roomMessages.append(message)
            announce(message)
            return
        }
        if type == "roll_dice_rejected" {
            if let playerID = WireScalarParser.exactInt(payload["player_id"]),
               myPlayerID != nil, playerID != myPlayerID { return }
            turnActionStarted = false
            let reasonCode = (payload["reason_code"] as? String) ?? ""
            announce(gameReasonText(reasonCode))
            return
        }
        if type == "arrived",
           let playerID = WireScalarParser.exactInt(payload["player_id"]),
           let index = WireScalarParser.exactInt(payload["to_index"]), (1...32).contains(index) {
            if playerID == myPlayerID {
                boardCursor.jump(to: index)
                boardCostCycle.reset()
            }
            let name = playerID == myPlayerID
                ? "당신"
                : (gamePlayers.first(where: { $0.playerID == playerID })?.nickname ?? "플레이어")
            let location = boardCatalog?.cell(at: index)?.name ?? "\(index)번 칸"
            let die1 = WireScalarParser.exactInt(payload["die1"]) ?? 0
            let die2 = WireScalarParser.exactInt(payload["die2"]) ?? 0
            let isDouble = WireScalarParser.exactBool(payload["is_double"]) ?? false
            let dice = die1 > 0 && die2 > 0 ? (isDouble ? "더블 \(die1 + die2)" : "\(die1 + die2)") : ""
            let text = "[\(name)] \(dice) → \(location)".replacingOccurrences(of: "]  →", with: "] →")
            roomMessages.append(text)
            announce("[\(name)] \(location)")
            return
        }

        if let message = payload["message"] as? String, !message.isEmpty {
            roomMessages.append(message)
            announce(message)
        }
    }

    private func gameReasonText(_ code: String) -> String {
        switch code {
        case "not_enough_marble": return "마블이 부족합니다."
        case "not_enough_asset": return "매각 가능한 자산이 부족합니다."
        case "already_owned": return "이미 소유자가 있습니다."
        case "not_owner": return "소유자가 아닙니다."
        case "max_building": return "이미 최대 단계입니다."
        case "landmark_not_acquirable": return "랜드마크 도시는 인수할 수 없습니다."
        case "island_not_acquirable": return "섬 도시는 인수할 수 없습니다."
        case "beach_not_acquirable": return "해변 도시는 인수할 수 없습니다."
        case "invalid_selection": return "선택할 수 없는 항목입니다."
        case "invalid_action": return "잘못된 동작입니다."
        case "invalid_state": return "현재 상태에서는 처리할 수 없습니다."
        case "not_my_turn": return "내 차례가 아닙니다."
        case "already_started": return "이미 시작했습니다."
        case "not_started": return "게임이 아직 시작되지 않았습니다."
        case "turn_timeout", "timeout": return "제한 시간이 지났습니다."
        case "cannot_cancel": return "취소할 수 없습니다."
        case "max_olympic": return "이미 최대 올림픽 개최 상태입니다."
        case "card_not_found": return "사용할 수 있는 카드가 없습니다."
        case "card_not_usable": return "지금 사용할 수 없는 카드입니다."
        case "turn_preparation_unavailable": return "현재는 주사위 실행 준비를 변경할 수 없습니다."
        case "not_stranded": return "무인도 상태가 아닙니다."
        case "bail_marble_shortage": return "보석금 20만 마블을 지급하기에 마블이 부족합니다."
        case "island_escape_not_available": return "무인도 탈출 카드는 무인도에서만 사용할 수 있습니다."
        case "salary_booster_already_active": return "월급 부스터가 이미 활성화되어 있습니다."
        case "held_card_selection_stale": return "선택했던 보관 카드가 현재 보관 카드와 일치하지 않습니다."
        case "turn_preparation_conflict": return "보석금과 무인도 탈출 카드를 동시에 사용할 수 없습니다."
        case "city_not_found": return "도시 정보를 찾을 수 없습니다."
        case "player_not_found": return "플레이어 정보를 찾을 수 없습니다."
        case "not_implemented": return "아직 구현되지 않은 기능입니다."
        case "unknown_error", "": return "주사위를 굴릴 수 없습니다."
        default: return code
        }
    }

    private func gameOverMessage(_ payload: [String: Any]) -> String {
        let winnerID = WireScalarParser.exactInt(payload["winner_player_id"])
        let winner: String
        if let winnerID, let player = gamePlayers.first(where: { $0.playerID == winnerID }) {
            winner = winnerID == myPlayerID ? "당신" : player.nickname
        } else {
            winner = ""
        }

        var labels: [String] = []
        if let achievements = payload["achievements"] as? [[String: Any]] {
            for achievement in achievements {
                switch achievement["ending_monopoly_type"] as? String {
                case "triple_color":
                    labels.append("트리플 컬러독점")
                case "line":
                    if let line = achievement["line_type"] as? String, ["A", "B", "C", "D"].contains(line) {
                        labels.append("\(line)라인독점")
                    }
                case "tourist":
                    labels.append("관광지독점")
                default:
                    break
                }
            }
        }
        if labels.isEmpty, WireScalarParser.exactBool(payload["is_last_survivor"]) == true {
            labels.append("최후의 1인")
        }
        var message = winner.isEmpty ? "승리" : "\(winner) 승리"
        if !labels.isEmpty { message += ": " + labels.joined(separator: "/") }
        return message
    }

    private func handleInteractionRequest(_ data: [String: Any]) {
        guard gameIsActive else { return }
        do {
            let request = try InteractionRequestParser.parse(data)
            if activeInteraction?.requestID == request.requestID { return }
            activeInteraction = request
            interactionResponseSubmitted = false
            turnActionStarted = true
            if request.interactionType == "select_destination",
               activatedInteractionRequestIDs.insert(request.requestID).inserted {
                socket.send(WireMessages.interactionPresentationActivate(requestID: request.requestID))
            }
        } catch {
            return
        }
    }

    private func handleInteractionFlowCompleted(_ data: [String: Any]) {
        guard let flowID = data["interaction_flow_id"] as? String,
              !flowID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard activeInteraction == nil || activeInteraction?.flowID == flowID else { return }
        activeInteraction = nil
        interactionResponseSubmitted = false
        activatedInteractionRequestIDs.removeAll()
        boardAccessibilityMode = .directTouch
    }

    private func formatInformationResponse(_ data: [String: Any]) -> String? {
        guard let queryType = data["query_type"] as? String,
              let payload = data["payload"] as? [String: Any],
              let result = payload["result"] as? [String: Any] else { return nil }
        let info = result["info"] as? [String: Any]
        func groupedMarble(_ value: Any?) -> String {
            guard let amount = WireScalarParser.exactInt(value) else { return "0마블" }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            return "\(formatter.string(from: NSNumber(value: amount)) ?? String(amount))마블"
        }
        if queryType == "city_cost" {
            guard let info else { return "비용 정보를 찾을 수 없습니다." }
            let city = (info["city_name"] as? String) ?? "도시"
            let kind = info["cost_type"] as? String
            if kind == "toll" { return "\(city) 통행료 \(groupedMarble(info["amount"]))" }
            if kind == "acquisition" {
                if info["amount"] == nil || info["amount"] is NSNull { return "\(city) 인수불가" }
                return "\(city) 인수 비용 \(groupedMarble(info["amount"]))"
            }
            if kind == "sale" { return "\(city) 매각 대금 \(groupedMarble(info["amount"]))" }
        }
        if queryType == "player_info" {
            guard let info else { return "플레이어 정보를 찾을 수 없습니다." }
            var parts: [String] = []
            let pid = WireScalarParser.exactInt(info["player_id"])
            if pid != myPlayerID, let nickname = info["nickname"] as? String { parts.append(nickname) }
            parts.append(groupedMarble(info["marble"]))
            let cityCount = WireScalarParser.exactInt(info["owned_city_count"]) ?? 0
            parts.append("소유 도시 \(cityCount)곳")
            if let groups = info["group_names"] as? [String] { parts.append(contentsOf: groups.map { "\($0) 독점" }) }
            if WireScalarParser.exactBool(info["has_olympic"]) == true,
               let count = WireScalarParser.exactInt(info["olympic_count"]), count > 0 { parts.append("올림픽 \(count)회") }
            if pid == myPlayerID, let card = info["held_card_name"] as? String, !card.isEmpty { parts.append("보관 카드 \(card)") }
            if WireScalarParser.exactBool(info["is_bankrupt"]) == true { parts.append("파산") }
            let status = info["connection_status"] as? String
            if status == "recovering" || status == "disconnected" { parts.append("접속 끊김") }
            return parts.isEmpty ? "플레이어 정보를 찾을 수 없습니다." : parts.joined(separator: " ")
        }
        return nil
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
            if let text = formatInformationResponse(data) { announce(text) }
        case "game_notice":
            if let message = data["message"] as? String, !message.isEmpty { roomMessages.append(message); announce(message) }
        case "board_cells":
            handleBoardCells(data)
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
                    if isGameStartPending { isGameStartPending = false }
                    alertMessage = message
                }
            }
        default:
            break
        }
    }


    private func enterGameRoom(_ snapshot: RoomEntrySnapshot) {
        isRoomEntryRecoveryPending = false
        roomEntry = snapshot
        roomUpdate = nil
        roomMessages = []
        boardCatalog = nil
        boardCursor.reset()
        boardAccessibilityMode = .directTouch
        boardCostCycle.reset()
        clearGameplayState()
        teamNameDraft = session?.identity.nickname ?? ""
        chatDraft = ""
        isTeamCreationPending = false
        isLeaveRoomPending = false
        screen = .gameRoom
    }

    private func handleBoardCells(_ data: [String: Any]) {
        guard roomEntry != nil else { return }
        do {
            let snapshot = try BoardCellsParser.parse(data)
            boardCatalog = snapshot
            if snapshot.cell(at: boardCursor.index) == nil {
                boardCursor.reset()
            }
            boardCostCycle.reset()
        } catch {
            // PC 일반 room 경로와 같이 malformed 정적 보드는 기존 정상 상태를
            // 임의 데이터로 덮어쓰지 않고 무시한다.
            return
        }
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
                boardAccessibilityMode = .directTouch
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
        clearAISelection()
        activeInteraction = nil
        interactionResponseSubmitted = false
        activatedInteractionRequestIDs = []
        gamePlayers = []
        gameIsActive = false
        gameFinished = false
        myPlayerID = nil
        currentPlayerID = nil
        currentTurnGeneration = nil
        nextTurnCommand = "roll_dice"
        turnCommandWindowOpen = false
        turnActionStarted = false
        isGameStartPending = false
        selectedOpponentTeamIndex = 0
        selectedOpponentMemberIndex = -1
    }

    private func clearRoomState() {
        roomEntry = nil
        roomUpdate = nil
        roomMessages = []
        boardCatalog = nil
        boardCursor.reset()
        boardAccessibilityMode = .directTouch
        boardCostCycle.reset()
        clearGameplayState()
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
        isRoomEntryRecoveryPending = false
        clearRoomState()
    }

    func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
