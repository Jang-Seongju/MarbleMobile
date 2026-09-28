import SwiftUI
import UIKit
import MarbleMobileCore

struct GameRoomView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLeaveConfirmation = false
    @StateObject private var interactionDraft = InteractionDraftState()
    @State private var interactionBoardInspectionRequestID: String?
    @State private var focusBoardLookupAfterInspection = false
    @AccessibilityFocusState private var teamNameAccessibilityFocus: Bool
    @AccessibilityFocusState private var directTouchExitAccessibilityFocus: Bool
    @AccessibilityFocusState private var returnToInteractionAccessibilityFocus: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 3) {
                topControls
                    .allowsHitTesting(!isInteractionBoardInspectionActive)
                    .accessibilityHidden(isInteractionBoardInspectionActive)

                if !model.hasJoinedTeam {
                    teamSetupArea
                }

                gameActionControls

                GameBoardShell(
                    messages: model.roomMessages,
                    catalog: model.boardCatalog,
                    cursorIndex: model.boardCursor.index,
                    currentCellDescription: model.currentBoardAccessibilityDescription,
                    directTouchAvailable: isInteractionBoardInspectionActive
                        ? model.isBoardReady
                        : model.isBoardDirectTouchAreaAvailable,
                    directTouchHint: isInteractionBoardInspectionActive
                        ? "두 번 탭하여 다이렉트 터치를 활성화합니다. 보드 조회 중에는 읽기 전용 정보 제스처만 사용할 수 있습니다. 한 손가락 두 번 탭하면 표준 VoiceOver로 전환하여 인터렉션으로 돌아가기 버튼으로 이동합니다."
                        : "두 번 탭하여 다이렉트 터치를 활성화할 수 있습니다. 다이렉트 터치 중 한 손가락 두 번 탭하면 표준 VoiceOver로 전환합니다.",
                    onExitDirectTouchOverride: isInteractionBoardInspectionActive
                        ? focusReturnToInteractionAfterDirectTouch
                        : focusPrimaryActionAfterDirectTouch,
                    onMoveLeft: model.moveBoardLeft,
                    onMoveRight: model.moveBoardRight,
                    onMoveUp: model.moveBoardUp,
                    onMoveDown: model.moveBoardDown,
                    onMagicTap: {
                        if isInteractionBoardInspectionActive {
                            model.announceBoardInspectionActionBlocked()
                        } else {
                            model.performBoardMagicTap()
                        }
                    },
                    onEscape: {
                        if isInteractionBoardInspectionActive {
                            model.announceBoardInspectionActionBlocked()
                        } else if !model.performBoardEscape() {
                            if model.canLeaveRoom {
                                showLeaveConfirmation = true
                            } else {
                                model.announce("게임 진행 중에는 방에서 나갈 수 없습니다.")
                            }
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
                .layoutPriority(1)

                chatArea
                    .allowsHitTesting(!isInteractionBoardInspectionActive)
                    .accessibilityHidden(isInteractionBoardInspectionActive)
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
                    .disabled(!model.canLeaveRoom)
                Button("취소", role: .cancel) {}
            } message: {
                Text("게임방에서 나가시겠습니까?")
            }
            .onAppear {
                if !model.hasJoinedTeam {
                    DispatchQueue.main.async { teamNameAccessibilityFocus = true }
                }
            }
            .sheet(item: $model.aiSelectionRequest) { request in
                AIPlayerSelectionSheet(request: request)
                    .environmentObject(model)
            }
            .sheet(item: interactionSheetBinding, onDismiss: interactionSheetDidDismiss) { request in
                GameInteractionSheet(
                    request: request,
                    draft: interactionDraft,
                    focusBoardLookupOnAppear: focusBoardLookupAfterInspection,
                    onBoardLookupFocusConsumed: { focusBoardLookupAfterInspection = false },
                    onBoardInspectionRequested: { beginInteractionBoardInspection(for: request) }
                )
                .id(request.requestID)
                .environmentObject(model)
            }
            .onChange(of: model.activeInteraction?.requestID) { _, requestID in
                guard let inspectionID = interactionBoardInspectionRequestID else { return }
                if requestID != inspectionID {
                    interactionBoardInspectionRequestID = nil
                    focusBoardLookupAfterInspection = false
                    interactionDraft.reset()
                }
            }
        }
    }

    private func interactionSheetDidDismiss() {
        if isInteractionBoardInspectionActive {
            // Diagnostic comparison: do not force VoiceOver back onto the board when
            // the inspection sheet disappears. The Direct Touch surface itself remains.
            return
        }

        // Normal server-driven completion must not force VoiceOver back to the board.
        // That focus jump can interrupt the result presentation that follows the close.
        DispatchQueue.main.async {
            model.interactionSheetDidDismiss()
        }
    }

    private var interactionSheetBinding: Binding<InteractionRequestSnapshot?> {
        Binding(
            get: {
                (model.isWorldTravelDestinationSelectionActive || isInteractionBoardInspectionActive)
                    ? nil
                    : model.activeInteraction
            },
            set: { _ in }
        )
    }

    private var isInteractionBoardInspectionActive: Bool {
        guard let requestID = interactionBoardInspectionRequestID,
              let active = model.activeInteraction
        else { return false }
        return active.requestID == requestID
    }

    private func beginInteractionBoardInspection(for request: InteractionRequestSnapshot) {
        guard model.activeInteraction?.requestID == request.requestID,
              model.isBoardReady,
              !model.interactionResponseSubmitted
        else { return }
        interactionDraft.prepare(for: request)
        interactionBoardInspectionRequestID = request.requestID
        focusBoardLookupAfterInspection = false
        model.announceBoardInspectionStarted()
    }

    private func exitInteractionBoardInspection() {
        guard isInteractionBoardInspectionActive else { return }
        interactionBoardInspectionRequestID = nil
        focusBoardLookupAfterInspection = true
        model.announceBoardInspectionFinished()
    }

    private var roomTitle: String {
        guard let room = model.roomEntry else { return "게임방" }
        return "\(room.roomID): \(room.title)"
    }

    private var topControls: some View {
        HStack(spacing: 8) {
            Menu("메뉴") {
                if let room = model.roomEntry {
                    Text("방 번호: \(room.roomID)")
                    Text("최대 인원: \(room.maxPlayers)명")
                    Text(room.isPrivate ? "비공개 방" : "공개 방")
                }

                Divider()

                Button("메시지 진단 로그 초기화") {
                    GameMessageDiagnosticLog.shared.reset()
                    model.announce("메시지 진단 로그를 초기화했습니다.")
                }

                Button("메시지 진단 로그 복사") {
                    GameMessageDiagnosticLog.shared.record("USER requested diagnostic copy")
                    GameMessageDiagnosticLog.shared.snapshotCurrent("USER_COPY_CURRENT")
                    UIPasteboard.general.string = GameMessageDiagnosticLog.shared.exportText()
                    model.announce("메시지 진단 로그를 클립보드에 복사했습니다.")
                }
            }

            Button("대기실 보기") { model.showLobbyFromGameRoom() }

            Button("나가기", role: .destructive) {
                showLeaveConfirmation = true
            }
            .disabled(!model.canLeaveRoom)

            if model.hasJoinedTeam {
                Spacer(minLength: 0)
                Text("팀: \(model.currentTeamName ?? model.teamNameDraft)")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityLabel("팀 이름")
                    .accessibilityValue(model.currentTeamName ?? model.teamNameDraft)
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private func focusPrimaryActionAfterDirectTouch() {
        directTouchExitAccessibilityFocus = false
        DispatchQueue.main.async { directTouchExitAccessibilityFocus = true }
    }

    private func focusReturnToInteractionAfterDirectTouch() {
        returnToInteractionAccessibilityFocus = false
        DispatchQueue.main.async { returnToInteractionAccessibilityFocus = true }
    }

    @ViewBuilder
    private var gameActionControls: some View {
        if isInteractionBoardInspectionActive {
            Button("인터렉션으로 돌아가기") { exitInteractionBoardInspection() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityFocused($returnToInteractionAccessibilityFocus)
        } else {
            normalGameActionControls
        }
    }

    private var normalGameActionControls: some View {
        HStack(spacing: 8) {
            primaryAction
                .frame(maxWidth: .infinity)

            Group {
                if let action = model.islandContextAction {
                    Button {
                        model.toggleIslandContextAction()
                    } label: {
                        VStack(spacing: 2) {
                            Text(action == .escapeCard ? "무인도 탈출 카드 사용" : "보석금 지불")
                            Text(model.islandContextActionSelected ? "선택" : "해제")
                                .font(.caption)
                        }
                    }
                    .accessibilityLabel(action == .escapeCard ? "무인도 탈출 카드 사용" : "보석금 지불")
                    .accessibilityValue(model.islandContextActionSelected ? "선택" : "해제")
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)

            Group {
                if model.salaryBoosterContextAvailable {
                    Button { model.toggleSalaryBoosterUse() } label: {
                        VStack(spacing: 2) {
                            Text("월급 부스터 사용")
                            Text(model.salaryBoosterSelected ? "선택" : "해제")
                                .font(.caption)
                        }
                    }
                    .accessibilityLabel("월급 부스터 사용")
                    .accessibilityValue(model.salaryBoosterSelected ? "선택" : "해제")
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
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
            .disabled(!model.canCreateTeam)
            .accessibilityFocused($directTouchExitAccessibilityFocus)
        } else if model.gameIsActive {
            Button("주사위 던지기") { model.performRollDice() }
                .disabled(!model.canRollDice)
                .accessibilityFocused($directTouchExitAccessibilityFocus)
        } else {
            Button(model.isGameStartPending ? "게임 시작 중" : "게임 시작") {
                model.requestGameStart()
            }
            .disabled(!model.canRequestGameStart)
            .accessibilityFocused($directTouchExitAccessibilityFocus)
        }
    }

    private var teamSetupArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("팀 이름")
                .font(.caption)
            TextField("팀 이름", text: $model.teamNameDraft)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { model.createTeamFromDraft() }
                .disabled(!model.canCreateTeam)
                .accessibilityFocused($teamNameAccessibilityFocus)
                .accessibilityHint("수정하지 않고 팀 만들기를 실행하면 현재 닉네임을 팀 이름으로 사용합니다.")
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

struct GameBoardShell: View {
    let messages: [GameRoomMessage]
    let catalog: BoardCatalogSnapshot?
    let cursorIndex: Int
    let currentCellDescription: String
    let directTouchAvailable: Bool
    let directTouchHint: String
    let onExitDirectTouchOverride: (() -> Void)?
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
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
                        accessibilityLabel: "게임 보드",
                        accessibilityValue: currentCellDescription,
                        accessibilityHint: directTouchHint,
                        onMoveLeft: onMoveLeft,
                        onMoveRight: onMoveRight,
                        onMoveUp: onMoveUp,
                        onMoveDown: onMoveDown,
                        onExitDirectTouch: {
                            onExitDirectTouchOverride?()
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
        GameMessageLogView(messages: messages)
        .background(.thinMaterial)
    }
}
