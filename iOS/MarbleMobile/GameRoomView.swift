import SwiftUI
import MarbleMobileCore

struct GameRoomView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLeaveConfirmation = false
    @AccessibilityFocusState private var teamNameAccessibilityFocus: Bool
    @AccessibilityFocusState private var boardAccessibilityFocus: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                topControls

                teamArea

                GameBoardShell(messages: model.roomMessages)
                    .accessibilityFocused($boardAccessibilityFocus)

                chatArea
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .navigationTitle(roomTitle)
            .navigationBarTitleDisplayMode(.inline)
            .alert("알림", isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )) {
                Button("확인", role: .cancel) { model.alertMessage = nil }
            } message: {
                Text(model.alertMessage ?? "")
            }
            .confirmationDialog(
                "게임방 나가기",
                isPresented: $showLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("나가기", role: .destructive) { model.requestLeaveRoom() }
                    .disabled(model.isLeaveRoomPending || model.isTeamCreationPending)
                Button("취소", role: .cancel) {}
            } message: {
                Text("게임방에서 나가시겠습니까?")
            }
            .onAppear {
                if !model.hasJoinedTeam {
                    DispatchQueue.main.async { teamNameAccessibilityFocus = true }
                }
            }
            .onChange(of: model.hasJoinedTeam) { wasJoined, isJoined in
                guard !wasJoined, isJoined else { return }
                DispatchQueue.main.async { boardAccessibilityFocus = true }
            }
        }
    }

    private var roomTitle: String {
        guard let room = model.roomEntry else { return "게임방" }
        return "\(room.roomID): \(room.title)"
    }

    private var topControls: some View {
        HStack(spacing: 8) {
            primaryAction

            Button("대기실 보기") { model.showLobbyFromGameRoom() }

            Menu("메뉴") {
                if let room = model.roomEntry {
                    Text("방 번호: \(room.roomID)")
                    Text("최대 인원: \(room.maxPlayers)명")
                    Text(room.isPrivate ? "비공개 방" : "공개 방")
                }
            }

            Button("나가기", role: .destructive) {
                showLeaveConfirmation = true
            }
            .disabled(model.isLeaveRoomPending || model.isTeamCreationPending)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if !model.hasJoinedTeam {
            Button(model.isTeamCreationPending ? "팀 만드는 중" : "팀 만들기") {
                model.createTeamFromDraft()
            }
            .disabled(model.isTeamCreationPending)
        } else {
            // 게임 시작 이후 프로토콜은 실제 보드/Interaction 입력 계층과 함께 연결한다.
            // unsupported game_started 상태에 먼저 진입하지 않도록 이 단계에서는 명시적으로 잠근다.
            Button("게임 시작") {}
                .disabled(true)
        }
    }

    @ViewBuilder
    private var teamArea: some View {
        if model.hasJoinedTeam {
            Text("팀: \(model.currentTeamName ?? model.teamNameDraft)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("팀 이름")
                .accessibilityValue(model.currentTeamName ?? model.teamNameDraft)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("팀 이름")
                    .font(.caption)
                TextField("팀 이름", text: $model.teamNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { model.createTeamFromDraft() }
                    .disabled(model.isTeamCreationPending)
                    .accessibilityFocused($teamNameAccessibilityFocus)
                    .accessibilityHint("수정하지 않고 팀 만들기를 실행하면 현재 닉네임을 팀 이름으로 사용합니다.")
            }
        }
    }

    private var chatArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("채팅")
                .font(.caption)
            TextField("메시지 입력", text: $model.chatDraft)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { model.sendRoomChatFromDraft() }
                .accessibilityHint("Return을 누르면 게임방에 메시지를 보냅니다.")
        }
    }
}

private struct GameBoardShell: View {
    let messages: [String]

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let cell = side / 9

            ZStack {
                ForEach(0..<81, id: \.self) { index in
                    let row = index / 9
                    let column = index % 9
                    if row == 0 || row == 8 || column == 0 || column == 8 {
                        Rectangle()
                            .strokeBorder(.secondary, lineWidth: 0.5)
                            .frame(width: cell, height: cell)
                            .position(
                                x: (CGFloat(column) + 0.5) * cell,
                                y: (CGFloat(row) + 0.5) * cell
                            )
                            .accessibilityHidden(true)
                    }
                }

                messageArea
                    .frame(width: cell * 7, height: cell * 7)
                    .position(x: side / 2, y: side / 2)
            }
            .frame(width: side, height: side, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("게임 보드")
    }

    private var messageArea: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if messages.isEmpty {
                    Text("게임 메시지가 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(8)
        }
        .background(.thinMaterial)
        .accessibilityLabel("게임 메시지")
    }
}
