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
                    if model.isInGameRoom {
                        Button("게임방 보기") { model.showGameRoom() }
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
                get: { model.profileText != nil },
                set: { if !$0 { model.profileText = nil } }
            )) {
                NavigationStack {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(informationLines.indices, id: \.self) { index in
                                Text(informationLines[index])
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("정보")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("닫기") { model.profileText = nil }
                        }
                    }
                }
            }
        }
    }

    private var selectedLobbyRoom: GameRoomSummary? {
        let roomID = focusedRoomID ?? lastRoomID
        guard let roomID else { return nil }
        return model.rooms.first { $0.id == roomID }
    }

    private var informationLines: [String] {
        guard let text = model.profileText else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init)
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
            isSpectator: false,
            messageImplemented: false,
            noteImplemented: false,
            roomInvitationImplemented: false,
            spectatorInvitationImplemented: false,
            socialInteractionImplemented: false
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
            // 접속자 메뉴는 실기기에서 확인된 기존 순서/방향을 그대로 보존한다.
            // 구현되지 않은 액션은 Button 자체를 disabled하여 VoiceOver가 표준
            // 비활성 상태(예: "흐리게 표시됨")를 읽도록 하고, 이름을 변형하지 않는다.
            ForEach(actions.reversed()) { action in
                Button(action.title) {
                    model.performUserAction(action.kind, user: user)
                }
                .disabled(!action.isEnabled)
            }
        }
    }

    private var roomList: some View {
        List {
            if model.rooms.isEmpty {
                Text("항목 없음")
                    .accessibilityActions {
                        Button("방 개설") { model.performRoomAction(.create, room: nil) }
                        Button("방 정렬") { model.performRoomAction(.sort, room: nil) }
                            .disabled(true)
                    }
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
        let roomActionsAvailable = !model.isInGameRoom && !model.isRoomCreationPending && !model.isRoomJoinPending
        let actions = LobbyActionBuilder.roomActions(
            roomCreationImplemented: roomActionsAvailable,
            roomJoinImplemented: roomActionsAvailable,
            spectatorInteractionImplemented: false
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
            // 게임방 custom action은 client(393)의 다섯 항목을 항상 유지한다.
            // VoiceOver custom action이 LIFO로 노출되는 현재 실기기 계약에 맞춰
            // PC 순서의 역순으로 고정 등록하되, 각 항목은 실제 Button.disabled 상태를
            // 사용한다. 따라서 미구현 항목 이름은 바꾸지 않고 시스템이 비활성 상태를 읽는다.
            .accessibilityActions {
                Button(roomActionTitle(.roomInfo, in: actions)) {
                    model.performRoomAction(.roomInfo, room: room)
                }
                .disabled(!roomActionEnabled(.roomInfo, in: actions))

                Button(roomActionTitle(.sort, in: actions)) {
                    model.performRoomAction(.sort, room: room)
                }
                .disabled(!roomActionEnabled(.sort, in: actions))

                Button(roomActionTitle(.spectatorEntry, in: actions)) {
                    model.performRoomAction(.spectatorEntry, room: room)
                }
                .disabled(!roomActionEnabled(.spectatorEntry, in: actions))

                Button(roomActionTitle(.join, in: actions)) {
                    model.performRoomAction(.join, room: room)
                }
                .disabled(!roomActionEnabled(.join, in: actions))

                Button(roomActionTitle(.create, in: actions)) {
                    model.performRoomAction(.create, room: room)
                }
                .disabled(!roomActionEnabled(.create, in: actions))
            }
    }

    private func roomActionTitle(
        _ kind: LobbyRoomActionKind,
        in actions: [LobbyRoomAction]
    ) -> String {
        actions.first(where: { $0.kind == kind })?.title ?? ""
    }

    private func roomActionEnabled(
        _ kind: LobbyRoomActionKind,
        in actions: [LobbyRoomAction]
    ) -> Bool {
        actions.first(where: { $0.kind == kind })?.isEnabled == true
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
