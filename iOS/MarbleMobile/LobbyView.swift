import SwiftUI
import MarbleMobileCore

struct LobbyView: View {
    @EnvironmentObject private var model: AppModel
    @State private var lastUserID: Int?
    @State private var lastRoomID: Int?
    @AccessibilityFocusState private var focusedUserID: Int?
    @AccessibilityFocusState private var focusedRoomID: Int?

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                if model.entryPhase != .active {
                    Text(statusText)
                } else if model.lobbyPage == .users {
                    userList
                } else {
                    roomList
                }

                HStack {
                    Button("접속자 목록") { switchToUsers() }
                        .disabled(model.lobbyPage == .users)
                    Button("게임방 목록") { switchToRooms() }
                        .disabled(model.lobbyPage == .rooms)
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 8)
            }
            .navigationTitle("마블 게임 - 대기실")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if model.canShowGameRoom {
                        Button(model.isSpectating ? "관중석 보기" : "게임방 보기") { model.showGameRoom() }
                    }
                    MobileMainMenu(
                        context: .lobby,
                        selectedLobbyRoom: selectedLobbyRoom
                    )
                    .environmentObject(model)
                }
            }
            .sheet(isPresented: Binding(
                get: { model.isPresentingCreateRoom },
                set: { if !$0 && !model.isRoomCreationPending { model.isPresentingCreateRoom = false } }
            )) {
                RoomCreationView()
                    .environmentObject(model)
            }
            .sheet(isPresented: Binding(
                get: { model.pendingRoomJoin != nil },
                set: { if !$0 { model.cancelPendingRoomJoin() } }
            )) {
                RoomJoinView()
                    .environmentObject(model)
            }
            .sheet(isPresented: Binding(
                get: { model.pendingSpectatorTargetList != nil || model.pendingSpectatorPasswordTarget != nil },
                set: { presented in
                    guard !presented else { return }
                    if model.spectatorPhase == .targetSelection {
                        model.cancelSpectatorTargetSelection()
                    } else if model.spectatorPhase == .passwordEntry {
                        model.cancelSpectatorPassword()
                    }
                }
            )) {
                if let targetList = model.pendingSpectatorTargetList {
                    SpectatorTargetSelectionView(targetList: targetList)
                        .environmentObject(model)
                } else if let target = model.pendingSpectatorPasswordTarget {
                    SpectatorPasswordView(target: target)
                        .environmentObject(model)
                }
            }
            .alert("알림", isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )) {
                Button("확인", role: .cancel) { model.alertMessage = nil }
            } message: {
                Text(model.alertMessage ?? "")
            }
            .confirmationDialog(
                model.pendingSocialConfirmation?.title ?? "확인",
                isPresented: Binding(
                    get: { model.pendingSocialConfirmation != nil },
                    set: { if !$0 { model.pendingSocialConfirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let confirmation = model.pendingSocialConfirmation {
                    Button("예", role: .destructive) { model.confirmSocialAction(confirmation) }
                }
                Button("아니오", role: .cancel) { model.pendingSocialConfirmation = nil }
            } message: {
                Text(model.pendingSocialConfirmation?.message ?? "")
            }
            .sheet(isPresented: Binding(
                get: { model.profileText != nil && model.utilitySheet == nil },
                set: { if !$0 { model.profileText = nil } }
            )) {
                InformationDocumentView(
                    title: "정보",
                    lines: PresentationFormatter.profileLines(model.profileText ?? ""),
                    onClose: { model.profileText = nil }
                )
            }
        }
    }

    private var selectedLobbyRoom: GameRoomSummary? {
        let roomID = focusedRoomID ?? lastRoomID
        guard let roomID else { return nil }
        return model.rooms.first { $0.id == roomID }
    }

    private var statusText: String {
        switch model.entryPhase {
        case .inactive, .connecting: return "서버 연결을 확인하고 있습니다."
        case .awaitingSessionEntry: return "로그인 상태를 확인하고 있습니다."
        case .active: return ""
        case .recoveryRequired: return "재접속이 필요한 진행 중 게임이 있습니다. 게임 복구 화면은 이후 게임 UI 단계에서 연결합니다."
        }
    }

    private var userList: some View {
        List {
            if model.users.isEmpty {
                Text("항목 없음")
            } else {
                ForEach(model.users) { user in
                    userRow(user)
                }
            }
        }
        .accessibilityLabel("접속자")
    }

    @ViewBuilder
    private func userRow(_ user: LobbyUser) -> some View {
        let actions = LobbyActionBuilder.userActions(
            targetUserID: user.id,
            currentUserID: model.session?.identity.userID ?? -1,
            socialState: model.socialState,
            hasGameRoom: model.isInGameRoom,
            isSpectator: model.isSpectating,
            messageImplemented: true,
            noteImplemented: true,
            roomInvitationImplemented: true,
            spectatorInvitationImplemented: true,
            socialInteractionImplemented: true
        )

        Text(PresenceFormatter.label(
            nickname: user.nickname,
            status: user.connectionStatus,
            isSelf: user.id == model.session?.identity.userID,
            isGameInProgress: user.isGameInProgress
        ))
        .accessibilityFocused($focusedUserID, equals: user.id)
        .onChange(of: focusedUserID) { _, value in
            if let value { lastUserID = value }
        }
        .accessibilityActions {
            lobbyAccessibilityActions(
                actions,
                title: \.title,
                isEnabled: \.isEnabled
            ) { action in
                model.performUserAction(action.kind, user: user)
            }
        }
    }

    private var roomList: some View {
        List {
            if model.rooms.isEmpty {
                emptyRoomRow
            } else {
                ForEach(model.rooms) { room in
                    roomRow(room)
                }
            }
        }
        .accessibilityLabel("게임방")
    }

    @ViewBuilder
    private func roomRow(_ room: GameRoomSummary) -> some View {
        let roomActionsAvailable = !model.isInGameRoom
            && model.spectatorPhase == .idle
            && !model.isRoomCreationPending
            && !model.isRoomJoinPending
        let spectatorActionAvailable = !model.isRoomCreationPending
            && !model.isRoomJoinPending
            && (
                (!model.isInGameRoom && model.spectatorPhase == .idle)
                || (model.isSpectating && model.spectatorPhase == .active)
            )
        let actions = LobbyActionBuilder.roomActions(
            roomCreationImplemented: roomActionsAvailable,
            roomJoinImplemented: roomActionsAvailable,
            spectatorInteractionImplemented: spectatorActionAvailable
        )

        Text(PresenceFormatter.roomLabel(room))
            .accessibilityFocused($focusedRoomID, equals: room.id)
            .onChange(of: focusedRoomID) { _, value in
                if let value { lastRoomID = value }
            }
            .accessibilityAction(.default) {
                if roomActionsAvailable {
                    model.performRoomAction(.join, room: room)
                }
            }
            .accessibilityActions {
                lobbyAccessibilityActions(
                    actions,
                    title: \.title,
                    isEnabled: \.isEnabled
                ) { action in
                    model.performRoomAction(action.kind, room: room)
                }
            }
    }

    private var emptyRoomRow: some View {
        let roomActionsAvailable = !model.isInGameRoom
            && model.spectatorPhase == .idle
            && !model.isRoomCreationPending
            && !model.isRoomJoinPending
        let actions = LobbyActionBuilder.roomActions(
            roomCreationImplemented: roomActionsAvailable,
            roomJoinImplemented: roomActionsAvailable,
            spectatorInteractionImplemented: roomActionsAvailable,
            hasRoomTarget: false
        )

        return Text("항목 없음")
            .accessibilityActions {
                lobbyAccessibilityActions(
                    actions,
                    title: \.title,
                    isEnabled: \.isEnabled
                ) { action in
                    model.performRoomAction(action.kind, room: nil)
                }
            }
    }

    @ViewBuilder
    private func lobbyAccessibilityActions<Action: Identifiable>(
        _ actions: [Action],
        title: KeyPath<Action, String>,
        isEnabled: KeyPath<Action, Bool>,
        perform: @escaping (Action) -> Void
    ) -> some View {
        // LobbyActionBuilder 배열은 메뉴의 canonical 순방향이다.
        // 실기기 VoiceOver는 SwiftUI accessibilityActions를 등록 역순으로 탐색하므로
        // 이 공통 어댑터에서만 한 번 역순 등록해 아래=canonical 순방향, 위=역방향으로 맞춘다.
        ForEach(actions.reversed()) { action in
            Button(action[keyPath: title]) {
                perform(action)
            }
            .disabled(!action[keyPath: isEnabled])
        }
    }

    private func switchToUsers() {
        model.lobbyPage = .users
        DispatchQueue.main.async { focusUserList() }
    }

    private func switchToRooms() {
        model.lobbyPage = .rooms
        DispatchQueue.main.async { focusRoomList() }
    }

    private func focusUserList() {
        focusedUserID = lastUserID.flatMap { id in model.users.contains { $0.id == id } ? id : nil } ?? model.users.first?.id
    }

    private func focusRoomList() {
        focusedRoomID = lastRoomID.flatMap { id in model.rooms.contains { $0.id == id } ? id : nil } ?? model.rooms.first?.id
    }
}
