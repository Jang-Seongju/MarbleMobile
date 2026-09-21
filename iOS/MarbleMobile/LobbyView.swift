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
                        .accessibilityLabel("진입 상태 안내, \(statusText)")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("메뉴") {
                        Button("로그아웃") { model.logout() }
                    }
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
                get: { model.profileText != nil },
                set: { if !$0 { model.profileText = nil } }
            )) {
                NavigationStack {
                    ScrollView {
                        Text(model.profileText ?? "")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                    .navigationTitle("정보")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("닫기") { model.profileText = nil }
                        }
                    }
                }
            }
            .onChange(of: model.users.map(\.id)) { _, _ in
                guard model.entryPhase == .active, model.lobbyPage == .users else { return }
                DispatchQueue.main.async { focusUserList() }
            }
            .onChange(of: model.rooms.map(\.id)) { _, _ in
                guard model.entryPhase == .active, model.lobbyPage == .rooms else { return }
                DispatchQueue.main.async { focusRoomList() }
            }
            .onChange(of: model.entryPhase) { _, newValue in
                guard newValue == .active else { return }
                model.lobbyPage = .users
                DispatchQueue.main.async { focusUserList() }
            }
        }
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
        .accessibilityLabel("접속자 목록")
        .accessibilityScrollAction { edge in
            if edge == .leading { switchToRooms() }
        }
        .task { focusUserList() }
    }

    @ViewBuilder
    private func userRow(_ user: LobbyUser) -> some View {
        let actions = LobbyActionBuilder.userActions(
            targetUserID: user.id,
            currentUserID: model.session?.identity.userID ?? -1,
            socialState: model.socialState,
            hasGameRoom: false,
            isSpectator: false,
            messageImplemented: false,
            noteImplemented: false
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
            ForEach(actions) { action in
                Button(action.title) { model.performUserAction(action.kind, user: user) }
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
                            .disabled(true)
                        Button("방 정렬") { model.performRoomAction(.sort, room: nil) }
                            .disabled(true)
                    }
            } else {
                ForEach(model.rooms) { room in
                    roomRow(room)
                }
            }
        }
        .accessibilityLabel("게임방 목록")
        .accessibilityScrollAction { edge in
            if edge == .trailing { switchToUsers() }
        }
        .task { focusRoomList() }
    }

    @ViewBuilder
    private func roomRow(_ room: GameRoomSummary) -> some View {
        let actions = LobbyActionBuilder.roomActions(
            roomInteractionImplemented: false,
            spectatorInteractionImplemented: false
        )

        Text(PresenceFormatter.roomLabel(room))
            .accessibilityFocused($focusedRoomID, equals: room.id)
            .onChange(of: focusedRoomID) { _, value in
                if let value { lastRoomID = value }
            }
            .accessibilityActions {
                ForEach(actions) { action in
                    Button(action.title) { model.performRoomAction(action.kind, room: room) }
                        .disabled(!action.isEnabled)
                }
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
