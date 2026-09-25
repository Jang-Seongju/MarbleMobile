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
    @Published var staticInformationCatalog: StaticInformationCatalogSnapshot?
    @Published var boardCursor = BoardCursorState()
    @Published var boardAccessibilityMode: BoardAccessibilityMode = .directTouch
    @Published var boardCostCycle = CityCostCycleState()
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
    private var isRoomEntryRecoveryPending = false
    private var aiSelectionHistory: [String] = []
    private var activatedInteractionRequestIDs: Set<String> = []
    private var pendingRotorDirections: [String: [Bool]] = [:]

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
        output.noticeSink = { [weak self] message in self?.roomMessages.append(message) }
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

    var isWorldTravelDestinationSelectionActive: Bool {
        guard let request = activeInteraction else { return false }
        return request.interactionType == "select_destination"
            && request.missionType == "world_travel_destination"
    }

    var isBoardDirectTouchEnabled: Bool {
        isBoardReady
            && boardAccessibilityMode == .directTouch
            && aiSelectionRequest == nil
            && (activeInteraction == nil || isWorldTravelDestinationSelectionActive)
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

    var currentBoardAccessibilityDescription: String {
        guard let cell = currentBoardCell else { return "보드 정보가 아직 준비되지 않았습니다." }
        guard (gameIsActive || gameFinished), cell.isCity, let cityID = cell.cityID,
              let info = gameCities.first(where: { $0.cityID == cityID })
        else { return cell.shortDescription }
        let text = InformationCityPresenter.format(
            info,
            spec: InformationDisplaySpecs.cityInfo,
            myPlayerID: myPlayerID
        )
        return text.isEmpty ? cell.shortDescription : text
    }

    func moveBoardCursorForward() {
        guard boardCatalog != nil else {
            announce("보드 정보가 아직 준비되지 않았습니다.")
            return
        }
        boardCursor.moveNext()
        boardCostCycle.reset()
        gameRotor.resetUnitBuildingSelection()
        announceCurrentBoardCell()
    }

    func moveBoardCursorBackward() {
        guard boardCatalog != nil else {
            announce("보드 정보가 아직 준비되지 않았습니다.")
            return
        }
        boardCursor.movePrevious()
        boardCostCycle.reset()
        gameRotor.resetUnitBuildingSelection()
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
        boardCostCycle.reset()
        gameRotor.resetUnitBuildingSelection()
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
        case .playerInformation:
            guard let target = gameRotor.movePlayerTarget(
                forward: forward,
                myPlayerID: myPlayerID,
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
        }
    }

    private func moveGameRotorDetail(forward: Bool) {
        switch gameRotor.category {
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
        }
    }

    func requestSelectedPlayerInfo() {
        guard gameIsActive || gameFinished else {
            announce("게임이 시작되지 않았습니다.")
            return
        }
        gameRotor.synchronizePlayers(myPlayerID: myPlayerID, players: gamePlayers)
        guard let target = gameRotor.playerTarget else {
            announce("플레이어 정보 없음")
            return
        }
        switch target {
        case .unowned:
            announce("플레이어 정보 없음")
        case .player(let playerID):
            if playerID == myPlayerID {
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

    private func requestRotorPlayerCity(forward: Bool) {
        guard gameIsActive || gameFinished else {
            announce("게임이 시작되지 않았습니다.")
            return
        }
        gameRotor.synchronizePlayers(myPlayerID: myPlayerID, players: gamePlayers)
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
            if playerID == myPlayerID {
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
            myPlayerID: myPlayerID,
            valueField: valueKind.valueField
        ) ?? "건물 정보를 찾을 수 없습니다."
        announce(text)
    }

    private func announceCurrentBoardCell() {
        announce(currentBoardAccessibilityDescription)
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

    func interactionEntryAnnouncement(_ request: InteractionRequestSnapshot) -> String {
        let cityInformation: [Int: InformationInfo] = Dictionary(uniqueKeysWithValues: gameCities.compactMap { info in
            guard let cityID = info.cityID else { return nil }
            return (cityID, info)
        })
        let playerNicknames = Dictionary(uniqueKeysWithValues: gamePlayers.map { ($0.playerID, $0.nickname) })
        return InteractionRequestPresenter.entryText(
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
            if let userID = WireScalarParser.exactInt(data["user_id"]), userID == session?.identity.userID {
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
        roomMessages.append(message)
        switch event {
        case "preparing":
            output.emit(PresentationPlan(
                root: .voice(clip: "dice_order.wav", fallbackTTS: message),
                category: .gameplay,
                queuePolicy: .enqueue,
                interruptRetention: .preservePending
            ))
        case "first_player":
            let isLocalFirst = WireScalarParser.exactInt(data["user_id"]) == session?.identity.userID
            if isLocalFirst {
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
        do {
            let snapshot = try GameplayParser.gameStarted(data)
            gamePlayers = snapshot.players
            gameCities = snapshot.cities
            gameIsActive = true
            gameFinished = false
            myPlayerID = snapshot.yourPlayerID
            currentPlayerID = snapshot.currentPlayerID
            staticInformationCatalog = snapshot.staticInformation
            gameRotor.reset()
            gameRotor.synchronizePlayers(myPlayerID: snapshot.yourPlayerID, players: snapshot.players)
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
            let message = "게임을 시작합니다."
            output.emit(.gameEvent(message, root: .sequence([
                .voice(clip: "game_start.wav", fallbackTTS: message)
            ])))
        } catch {
            return
        }
    }

    private func handleGameState(_ data: [String: Any]) {
        guard gameIsActive || gameFinished else { return }
        do {
            let snapshot = try GameplayParser.gameState(data)
            gamePlayers = snapshot.players
            gameCities = snapshot.cities
            gameRotor.synchronizePlayers(myPlayerID: myPlayerID, players: snapshot.players)
            if let current = snapshot.currentPlayerID { currentPlayerID = current }
        } catch {
            return
        }
    }

    private func handleNotification(_ data: [String: Any]) {
        guard let type = GameplayParser.notificationType(data),
              let payload = GameplayParser.notificationPayload(data) else { return }

        if type == "turn_started" {
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
            if playerID == myPlayerID, generation == currentTurnGeneration {
                let remaining = WireScalarParser.nonBooleanNumber(payload["turn_remaining_seconds"])?.doubleValue
                let deadline = payload["turn_deadline_at"] as? String
                _ = turnDeadlineWarning.startForTurn(
                    playerID: playerID,
                    localPlayerID: myPlayerID,
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
            activeInteraction = nil
            interactionResponseSubmitted = false
            boardAccessibilityMode = .directTouch
        } else if type == "roll_dice_rejected" {
            if let playerID = WireScalarParser.exactInt(payload["player_id"]),
               myPlayerID != nil, playerID != myPlayerID { return }
            turnActionStarted = false
        } else if type == "arrived",
                  let playerID = WireScalarParser.exactInt(payload["player_id"]),
                  let index = WireScalarParser.exactInt(payload["to_index"]), (1...32).contains(index),
                  playerID == myPlayerID {
            boardCursor.jump(to: index)
            boardCostCycle.reset()
            gameRotor.resetUnitBuildingSelection()
        }

        let context = GamePresentationContext(
            localPlayerID: myPlayerID,
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
        }
    }

    private func handleInteractionRequest(_ data: [String: Any]) {
        guard gameIsActive else { return }
        do {
            let request = try InteractionRequestParser.parse(data)
            if activeInteraction?.requestID == request.requestID { return }
            activeInteraction = request
            interactionResponseSubmitted = false
            turnActionStarted = true
            if request.interactionType == "select_destination" {
                boardAccessibilityMode = .directTouch
                if activatedInteractionRequestIDs.insert(request.requestID).inserted {
                    socket.send(WireMessages.interactionPresentationActivate(requestID: request.requestID))
                }
            } else if request.interactionType != "acknowledge" {
                let announcement = interactionEntryAnnouncement(request)
                if !announcement.isEmpty {
                    output.emit(PresentationPlan(
                        root: .tts(announcement),
                        category: .gameplay,
                        queuePolicy: .enqueue,
                        interruptRetention: .dropPending
                    ))
                }
            }
        } catch {
            return
        }
    }

    private func handleInteractionFlowCompleted(_ data: [String: Any]) {
        guard let flowID = data["interaction_flow_id"] as? String,
              !flowID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard activeInteraction == nil || activeInteraction?.flowID == flowID else { return }
        if activeInteraction?.interactionType == "select_destination" {
            output.stopBGM()
        }
        activeInteraction = nil
        interactionResponseSubmitted = false
        activatedInteractionRequestIDs.removeAll()
        boardAccessibilityMode = .directTouch
    }

    private func dequeuePendingRotorDirection(for queryType: String) -> Bool? {
        guard var queue = pendingRotorDirections[queryType], !queue.isEmpty else { return nil }
        let value = queue.removeFirst()
        if queue.isEmpty { pendingRotorDirections.removeValue(forKey: queryType) }
        else { pendingRotorDirections[queryType] = queue }
        return value
    }

    private func formatInformationResponse(_ data: [String: Any]) -> String? {
        guard let queryType = data["query_type"] as? String,
              let payload = data["payload"] as? [String: Any],
              let result = InformationParser.result(payload["result"])
        else { return nil }

        if queryType == "city_info", let filter = payload["filter"] as? String {
            if let correctedIndex = result.index {
                gameRotor.updateFilteredCityIndex(filter: filter, correctedIndex: correctedIndex)
            }
            if let info = result.info { jumpBoardToInformationCity(info) }
        }

        if queryType == "achieved_monopoly_status" || queryType == "ending_monopoly_alerts" {
            let forward = dequeuePendingRotorDirection(for: queryType) ?? true
            let kind: GameRotorMonopolyKind = queryType == "achieved_monopoly_status" ? .achieved : .endingAlert
            let index = gameRotor.nextMonopolyItemIndex(kind: kind, forward: forward, count: result.items.count)
            return InformationResultPresenter.format(
                queryType: queryType,
                result: result,
                myPlayerID: myPlayerID,
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
            myPlayerID: myPlayerID,
            valueField: payload["value_field"] as? String,
            filterType: payload["filter"] as? String,
            asBuildingStatus: asBuildingStatus
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
                    queryType: queryType, result: result, myPlayerID: myPlayerID
                )
            }
            let index = gameRotor.nextCityStatusIndex(kind: .festival, forward: forward, count: result.items.count)
            selectedInfo = result.items[index]
        case "active_city_effects":
            guard !result.items.isEmpty else {
                return InformationResultPresenter.format(
                    queryType: queryType, result: result, myPlayerID: myPlayerID
                )
            }
            let index = gameRotor.nextCityStatusIndex(kind: .activeEffect, forward: forward, count: result.items.count)
            selectedInfo = result.items[index]
        case "olympic_city":
            selectedInfo = result.info
            if selectedInfo == nil {
                return InformationResultPresenter.format(
                    queryType: queryType, result: result, myPlayerID: myPlayerID
                )
            }
        default:
            return nil
        }

        guard let selectedInfo else { return nil }
        jumpBoardToInformationCity(selectedInfo)
        guard let cityID = selectedInfo.cityID else {
            return InformationResultPresenter.format(
                queryType: queryType, result: result, myPlayerID: myPlayerID
            )
        }
        if let fullInfo = gameCities.first(where: { $0.cityID == cityID }) {
            let text = InformationCityPresenter.format(
                fullInfo,
                spec: InformationDisplaySpecs.cityInfo,
                myPlayerID: myPlayerID
            )
            if !text.isEmpty { return text }
        }
        return InformationResultPresenter.format(
            queryType: queryType, result: result, myPlayerID: myPlayerID
        )
    }

    private func jumpBoardToInformationCity(_ info: InformationInfo) {
        guard let cityID = info.cityID,
              let index = boardCatalog?.cells.first(where: { $0.cityID == cityID })?.index
        else { return }
        boardCursor.jump(to: index)
        boardCostCycle.reset()
        gameRotor.resetUnitBuildingSelection()
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
                roomMessages.append(message)
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
        case "room_chat":
            if let chat = try? RoomChatParser.parse(data) {
                roomMessages.append("\(chat.fromNickname): \(chat.message)")
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
        output.stopAll()
        isRoomEntryRecoveryPending = false
        roomEntry = snapshot
        roomUpdate = nil
        roomMessages = []
        boardCatalog = nil
        staticInformationCatalog = nil
        boardCursor.reset()
        boardAccessibilityMode = .directTouch
        boardCostCycle.reset()
        gameRotor.reset()
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
            let snapshot = try BoardBootstrapParser.parse(data)
            boardCatalog = snapshot.boardCatalog
            staticInformationCatalog = snapshot.staticInformation
            if snapshot.boardCatalog.cell(at: boardCursor.index) == nil {
                boardCursor.reset()
            }
            boardCostCycle.reset()
            gameRotor.resetUnitBuildingSelection()
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
        turnDeadlineWarning.stop(preserveZeroSFX: false)
        clearAISelection()
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
        gameRotor.reset()
        pendingRotorDirections = [:]
    }

    private func clearRoomState() {
        output.stopAll()
        roomEntry = nil
        roomUpdate = nil
        roomMessages = []
        boardCatalog = nil
        staticInformationCatalog = nil
        boardCursor.reset()
        boardAccessibilityMode = .directTouch
        boardCostCycle.reset()
        gameRotor.reset()
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
