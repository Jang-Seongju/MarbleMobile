import Foundation
import SwiftUI
import MarbleMobileCore

struct GameInteractionSheet: View {
    @EnvironmentObject private var model: AppModel
    let request: InteractionRequestSnapshot

    @State private var selectedOne: String?
    @State private var selectedMultiple: Set<String> = []
    @State private var selectedByGroup: [String: String] = [:]
    @State private var selectedBuildCityID: Int?
    @State private var selectedBuildIDs: Set<String> = []
    @State private var isBoardInspection = false
    @State private var boardInspectionFocusRequest = 0
    @AccessibilityFocusState private var primaryFocus: Bool
    @AccessibilityFocusState private var returnToInteractionFocus: Bool
    @AccessibilityFocusState private var boardLookupAccessibilityFocus: Bool
    @Namespace private var boardInspectionRotorNamespace

    var body: some View {
        NavigationStack {
            Group {
                if isBoardInspection {
                    boardInspectionContent
                } else {
                    interactionForm
                }
            }
            .interactiveDismissDisabled()
            .onAppear {
                if request.interactionType == "select_one", selectedOne == nil {
                    selectedOne = request.items.first(where: { !$0.disabled })?.id
                }
                if request.interactionType == "select_city_and_buildings", selectedBuildCityID == nil {
                    selectedBuildCityID = request.startBuildCities.first?.cityID
                }
                DispatchQueue.main.async { primaryFocus = true }
            }
        }
    }

    private var interactionForm: some View {
        Form {
            let description = model.interactionDescription(request)
            if !description.isEmpty {
                Section {
                    Text(description)
                        .accessibilityFocused($primaryFocus)
                }
            }

            Section {
                Button("보드 조회") { enterBoardInspection() }
                    .disabled(model.interactionResponseSubmitted || !model.isBoardReady)
                    .accessibilityRotorEntry(id: "board-inspection", in: boardInspectionRotorNamespace)
                    .accessibilityFocused($boardLookupAccessibilityFocus)
            }

            interactionContent

            if model.interactionResponseSubmitted {
                Section {
                    ProgressView("응답 처리 중")
                }
            }

            if request.cancellable && request.interactionType != "confirm" {
                Section {
                    Button("취소", role: .cancel) { model.cancelActiveInteraction() }
                        .disabled(model.interactionResponseSubmitted)
                }
            }
        }
        .navigationTitle(request.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityRotor("보드 조회") {
            AccessibilityRotorEntry(
                "보드 조회",
                id: "board-inspection",
                in: boardInspectionRotorNamespace
            )
        }
        .accessibilityAction(.escape) {
            if request.cancellable {
                model.cancelActiveInteraction()
            } else {
                model.announce("취소할 수 없습니다.")
            }
        }
    }

    private var boardInspectionContent: some View {
        VStack(spacing: 8) {
            Button("인터렉션으로 돌아가기") { exitBoardInspection() }
                .buttonStyle(.borderedProminent)
                .accessibilityFocused($returnToInteractionFocus)

            GameBoardShell(
                messages: model.roomMessages,
                catalog: model.boardCatalog,
                cursorIndex: model.boardCursor.index,
                currentCellDescription: model.currentBoardAccessibilityDescription,
                directTouchAvailable: model.isBoardReady,
                accessibilityFocusRequest: boardInspectionFocusRequest,
                directTouchHint: "두 번 탭하여 다이렉트 터치를 활성화합니다. 보드 조회 중에는 읽기 전용 정보 제스처만 사용할 수 있습니다. 한 손가락 두 번 탭하면 표준 VoiceOver로 전환하여 인터렉션으로 돌아가기 버튼으로 이동합니다.",
                onExitDirectTouchOverride: focusReturnToInteractionButton,
                onMoveLeft: model.moveBoardLeft,
                onMoveRight: model.moveBoardRight,
                onMoveUp: model.moveBoardUp,
                onMoveDown: model.moveBoardDown,
                onMagicTap: model.announceBoardInspectionActionBlocked,
                onEscape: model.announceBoardInspectionActionBlocked,
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
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .navigationTitle("보드 조회")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityAction(.escape) { exitBoardInspection() }
    }

    private func enterBoardInspection() {
        guard model.isBoardReady, !model.interactionResponseSubmitted else { return }
        isBoardInspection = true
        model.announceBoardInspectionStarted()
        DispatchQueue.main.async { boardInspectionFocusRequest &+= 1 }
    }

    private func exitBoardInspection() {
        guard isBoardInspection else { return }
        isBoardInspection = false
        model.announceBoardInspectionFinished()
        DispatchQueue.main.async { boardLookupAccessibilityFocus = true }
    }

    private func focusReturnToInteractionButton() {
        returnToInteractionFocus = false
        DispatchQueue.main.async { returnToInteractionFocus = true }
    }

    @ViewBuilder
    private var interactionContent: some View {
        switch request.interactionType {
        case "confirm":
            Section {
                Button("확인") { model.respondToInteraction(responseType: "confirmed") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.interactionResponseSubmitted)
                if request.cancellable {
                    Button("취소", role: .cancel) {
                        model.respondToInteraction(responseType: "cancelled")
                    }
                    .disabled(model.interactionResponseSubmitted)
                }
            }

        case "acknowledge":
            Section {
                if let cardName = request.cardName { Text(cardName).font(.headline) }
                if let cardDescription = request.cardDescription { Text(cardDescription) }
                Button("확인") { model.respondToInteraction(responseType: "confirmed") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.interactionResponseSubmitted)
            }

        case "select_one":
            Section("선택 항목") {
                ForEach(request.items) { item in
                    Button {
                        guard !item.disabled else { return }
                        selectedOne = item.id
                    } label: {
                        HStack {
                            Text(model.interactionItemLabel(item, request: request))
                            Spacer()
                            if selectedOne == item.id { Image(systemName: "checkmark") }
                        }
                    }
                    .disabled(item.disabled || model.interactionResponseSubmitted)
                    .accessibilityValue(selectedOne == item.id ? "선택됨" : "")
                }
                Button("확인") {
                    guard let selectedOne else {
                        model.announce("항목을 선택해 주세요.")
                        return
                    }
                    model.respondToInteraction(
                        responseType: "selected",
                        payload: ["selected_ids": [selectedOne]]
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.interactionResponseSubmitted)
            }

        case "select_multiple":
            Section("선택 항목") {
                ForEach(request.items) { item in
                    Toggle(model.interactionItemLabel(item, request: request), isOn: Binding(
                        get: { selectedMultiple.contains(item.id) },
                        set: { newValue in updateMultiple(item, selected: newValue) }
                    ))
                    .disabled(item.disabled || (!selectedMultiple.contains(item.id) && !canAdd(item)) || model.interactionResponseSubmitted)
                }
                if request.missionType == "liquidation" {
                    Text(model.liquidationMarbleInfo(request, selectedSellValue: selectedMultipleCost))
                        .font(.footnote)
                } else if request.ownedMarble > 0 {
                    Text("선택 비용: \(marble(selectedMultipleCost)) / 보유 \(marble(request.ownedMarble))")
                        .font(.footnote)
                }
                Button("확인") { submitMultiple() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.interactionResponseSubmitted)
            }

        case "select_one_per_group":
            ForEach(request.groups) { group in
                Section(groupTitle(group.role)) {
                    ForEach(group.items) { item in
                        Button {
                            guard !item.disabled else { return }
                            selectedByGroup[group.role] = item.id
                        } label: {
                            HStack {
                                Text(model.interactionItemLabel(item, request: request, role: group.role))
                                Spacer()
                                if selectedByGroup[group.role] == item.id { Image(systemName: "checkmark") }
                            }
                        }
                        .disabled(item.disabled || model.interactionResponseSubmitted)
                        .accessibilityValue(selectedByGroup[group.role] == item.id ? "선택됨" : "")
                    }
                }
            }
            Section {
                Button("확인") { submitGroups() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.interactionResponseSubmitted)
            }

        case "select_city_and_buildings":
            ForEach(request.startBuildCities) { city in
                Section(city.label) {
                    Button {
                        selectedBuildCityID = city.cityID
                        selectedBuildIDs = []
                    } label: {
                        HStack {
                            Text("이 도시 선택")
                            Spacer()
                            if selectedBuildCityID == city.cityID { Image(systemName: "checkmark") }
                        }
                    }
                    .disabled(model.interactionResponseSubmitted)
                    .accessibilityValue(selectedBuildCityID == city.cityID ? "선택됨" : "")

                    if selectedBuildCityID == city.cityID {
                        ForEach(city.buildOptions) { item in
                            Toggle(model.interactionItemLabel(item, request: request), isOn: Binding(
                                get: { selectedBuildIDs.contains(item.id) },
                                set: { selected in updateStartBuild(item, selected: selected) }
                            ))
                            .disabled(
                                item.disabled
                                || (!selectedBuildIDs.contains(item.id) && !canAddStartBuild(item))
                                || model.interactionResponseSubmitted
                            )
                        }
                    }
                }
            }
            Section {
                Button("확인") { submitStartBuild() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.interactionResponseSubmitted)
            }

        default:
            Section { Text("지원하지 않는 선택 방식입니다.") }
        }
    }

    private var selectedMultipleCost: Int {
        request.items.filter { selectedMultiple.contains($0.id) }.reduce(0) { $0 + max(0, $1.cost) }
    }

    private func canAdd(_ item: InteractionItemSnapshot) -> Bool {
        guard request.missionType != "liquidation", request.ownedMarble > 0 else { return true }
        return selectedMultipleCost + max(0, item.cost) <= request.ownedMarble
    }

    private func updateMultiple(_ item: InteractionItemSnapshot, selected: Bool) {
        guard !item.disabled else { return }
        if selected {
            guard canAdd(item) else {
                model.announce("보유 마블이 부족합니다.")
                return
            }
            selectedMultiple.insert(item.id)
        } else {
            selectedMultiple.remove(item.id)
        }
        if request.missionType == "liquidation" {
            model.announceLiquidationSelectionChanged(
                request,
                selectedSellValue: selectedMultipleCost
            )
        }
    }

    private func submitMultiple() {
        guard !selectedMultiple.isEmpty else {
            model.announce("항목을 선택해 주세요.")
            return
        }
        if request.missionType == "liquidation",
           let shortage = InteractionRequestPresenter.liquidationShortage(
               request,
               selectedSellValue: selectedMultipleCost
           ) {
            model.announce(shortage)
            return
        }
        let ids = request.items.map(\.id).filter { selectedMultiple.contains($0) }
        model.respondToInteraction(responseType: "selected", payload: ["selected_ids": ids])
    }

    private func submitGroups() {
        guard request.groups.allSatisfy({ selectedByGroup[$0.role] != nil }) else {
            model.announce("각 그룹에서 항목을 하나씩 선택해 주세요.")
            return
        }
        let selections = request.groups.map { group in
            ["role": group.role, "selected_id": selectedByGroup[group.role]!] as [String: Any]
        }
        model.respondToInteraction(responseType: "selected", payload: ["selections": selections])
    }


    private var selectedStartBuildCost: Int {
        guard let cityID = selectedBuildCityID,
              let city = request.startBuildCities.first(where: { $0.cityID == cityID }) else { return 0 }
        return city.buildOptions
            .filter { selectedBuildIDs.contains($0.id) }
            .reduce(0) { $0 + max(0, $1.cost) }
    }

    private func canAddStartBuild(_ item: InteractionItemSnapshot) -> Bool {
        guard request.ownedMarble > 0 else { return true }
        return selectedStartBuildCost + max(0, item.cost) <= request.ownedMarble
    }

    private func updateStartBuild(_ item: InteractionItemSnapshot, selected: Bool) {
        guard !item.disabled else { return }
        if selected {
            guard canAddStartBuild(item) else {
                model.announce("보유 마블이 부족합니다.")
                return
            }
            selectedBuildIDs.insert(item.id)
        } else {
            selectedBuildIDs.remove(item.id)
        }
    }

    private func submitStartBuild() {
        guard let cityID = selectedBuildCityID else {
            model.announce("도시를 선택해 주세요.")
            return
        }
        guard let city = request.startBuildCities.first(where: { $0.cityID == cityID }),
              !selectedBuildIDs.isEmpty else {
            model.announce("건물을 선택해 주세요.")
            return
        }
        let ids = city.buildOptions.map(\.id).filter { selectedBuildIDs.contains($0) }
        model.respondToInteraction(
            responseType: "selected",
            payload: ["selected_city_id": cityID, "selected_ids": ids]
        )
    }

    private func groupTitle(_ role: String) -> String {
        switch role {
        case "owned_city": return "내 도시"
        case "opponent_city": return "상대 도시"
        case "recipient_player": return "기부 대상"
        case "attack_city": return "대상 도시"
        default: return role
        }
    }

    private func marble(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return "\(formatter.string(from: NSNumber(value: value)) ?? String(value))마블"
    }
}
