import SwiftUI
import MarbleMobileCore

struct GameRoomView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var showLeaveConfirmation = false
    @AccessibilityFocusState private var teamNameAccessibilityFocus: Bool
    @AccessibilityFocusState private var boardAccessibilityFocus: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                topControls

                teamArea

                GameBoardShell(
                    messages: model.roomMessages,
                    catalog: model.boardCatalog,
                    cursorIndex: model.boardCursor.index,
                    currentCellDescription: model.currentBoardAccessibilityDescription,
                    directTouchAvailable: model.isBoardDirectTouchAreaAvailable && voiceOverEnabled,
                    onPreviousCell: model.moveBoardCursorBackward,
                    onNextCell: model.moveBoardCursorForward,
                    onPreviousCityCost: model.cycleBoardCityCostBackward,
                    onNextCityCost: model.cycleBoardCityCostForward,
                    onMagicTap: model.performBoardMagicTap,
                    onEscape: {
                        if !model.performBoardEscape() {
                            showLeaveConfirmation = true
                        }
                    },
                    onSelectedPlayerInfo: model.requestSelectedPlayerInfo,
                    onRotorForward: model.rotateGameRotorForward,
                    onRotorBackward: model.rotateGameRotorBackward,
                    onPreviousRotorSelection: model.moveGameRotorSelectionBackward,
                    onNextRotorSelection: model.moveGameRotorSelectionForward,
                    onPreviousRotorDetail: model.moveGameRotorDetailBackward,
                    onNextRotorDetail: model.moveGameRotorDetailForward,
                    onLineA: { model.jumpToBoardLine("A") },
                    onLineB: { model.jumpToBoardLine("B") },
                    onLineC: { model.jumpToBoardLine("C") },
                    onLineD: { model.jumpToBoardLine("D") }
                )
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
            .sheet(item: $model.aiSelectionRequest) { request in
                AIPlayerSelectionSheet(request: request)
                    .environmentObject(model)
            }
            .sheet(item: interactionSheetBinding, onDismiss: restoreBoardAccessibilityFocus) { request in
                GameInteractionSheet(request: request)
                    .id(request.requestID)
                    .environmentObject(model)
            }
        }
    }

    private func restoreBoardAccessibilityFocus() {
        guard model.isBoardReady else { return }
        boardAccessibilityFocus = false
        DispatchQueue.main.async { boardAccessibilityFocus = true }
    }

    private var interactionSheetBinding: Binding<InteractionRequestSnapshot?> {
        Binding(
            get: {
                model.isWorldTravelDestinationSelectionActive
                    ? nil
                    : model.activeInteraction
            },
            set: { _ in }
        )
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
        } else if model.gameIsActive {
            Button("주사위 던지기") { model.performRollDice() }
        } else {
            Button(model.isGameStartPending ? "게임 시작 중" : "게임 시작") {
                model.requestGameStart()
            }
            .disabled(model.isGameStartPending)
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
    @AccessibilityFocusState private var messageAccessibilityFocus: Bool

    let messages: [String]
    let catalog: BoardCatalogSnapshot?
    let cursorIndex: Int
    let currentCellDescription: String
    let directTouchAvailable: Bool
    let onPreviousCell: () -> Void
    let onNextCell: () -> Void
    let onPreviousCityCost: () -> Void
    let onNextCityCost: () -> Void
    let onMagicTap: () -> Void
    let onEscape: () -> Void
    let onSelectedPlayerInfo: () -> Void
    let onRotorForward: () -> Void
    let onRotorBackward: () -> Void
    let onPreviousRotorSelection: () -> Void
    let onNextRotorSelection: () -> Void
    let onPreviousRotorDetail: () -> Void
    let onNextRotorDetail: () -> Void
    let onLineA: () -> Void
    let onLineB: () -> Void
    let onLineC: () -> Void
    let onLineD: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let cell = side / 9

            ZStack {
                ForEach(0..<81, id: \.self) { gridIndex in
                    let row = gridIndex / 9
                    let column = gridIndex % 9
                    if row == 0 || row == 8 || column == 0 || column == 8 {
                        boardCell(row: row, column: column, size: cell)
                            .position(
                                x: (CGFloat(column) + 0.5) * cell,
                                y: (CGFloat(row) + 0.5) * cell
                            )
                    }
                }

                messageArea
                    .frame(width: cell * 7, height: cell * 7)
                    .position(x: side / 2, y: side / 2)

                if directTouchAvailable {
                    GameBoardDirectTouchSurface(
                        onPreviousCell: onPreviousCell,
                        onNextCell: onNextCell,
                        onPreviousCityCost: onPreviousCityCost,
                        onNextCityCost: onNextCityCost,
                        onExitDirectTouch: {
                            messageAccessibilityFocus = false
                            DispatchQueue.main.async {
                                messageAccessibilityFocus = true
                            }
                        },
                        onMagicTap: onMagicTap,
                        onEscape: onEscape,
                        onSelectedPlayerInfo: onSelectedPlayerInfo,
                        onRotorForward: onRotorForward,
                        onRotorBackward: onRotorBackward,
                        onPreviousRotorSelection: onPreviousRotorSelection,
                        onNextRotorSelection: onNextRotorSelection,
                        onPreviousRotorDetail: onPreviousRotorDetail,
                        onNextRotorDetail: onNextRotorDetail,
                        onLineA: onLineA,
                        onLineB: onLineB,
                        onLineC: onLineC,
                        onLineD: onLineD
                    )
                    .frame(width: side, height: side)
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("게임 보드")
        .accessibilityValue(currentCellDescription)
        .accessibilityHint(
            directTouchAvailable
                ? "두 번 탭하여 다이렉트 터치를 활성화할 수 있습니다. VoiceOver 로터, 빠른 설정 또는 앱별 다이렉트 터치 설정도 사용할 수 있습니다. 다이렉트 터치 중 한 손가락 두 번 탭하면 게임 메시지로 포커스를 이동합니다."
                : "현재는 다이렉트 터치를 사용할 수 없습니다."
        )
        .accessibilityDirectTouch(
            directTouchAvailable,
            options: [.requiresActivation, .silentOnTouch]
        )
    }

    @ViewBuilder
    private func boardCell(row: Int, column: Int, size: CGFloat) -> some View {
        let snapshot = catalog?.cell(row: row, column: column)
        let isSelected = snapshot?.index == cursorIndex

        ZStack {
            Rectangle()
                .strokeBorder(isSelected ? .primary : .secondary, lineWidth: isSelected ? 2 : 0.5)
            if let snapshot {
                Text(snapshot.name)
                    .font(.system(size: max(7, size * 0.16)))
                    .lineLimit(2)
                    .minimumScaleFactor(0.35)
                    .multilineTextAlignment(.center)
                    .padding(1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
        .accessibilityFocused($messageAccessibilityFocus)
    }
}
