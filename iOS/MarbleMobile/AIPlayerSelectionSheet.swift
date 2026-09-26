import SwiftUI
import MarbleMobileCore

struct AIPlayerSelectionSheet: View {
    @EnvironmentObject private var model: AppModel
    let request: AIPlayerSelectionRequest

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("함께 플레이할 AI를 선택하세요.")
                    Text("사람 \(request.humanPlayerCount)명, AI \(request.minimumAICount)명부터 \(request.maximumAICount)명까지 선택할 수 있습니다.")
                        .font(.footnote)
                }

                Section("AI 플레이어") {
                    ForEach(request.availableAI) { option in
                        Toggle(option.nickname, isOn: Binding(
                            get: { model.selectedAIIDs.contains(option.aiID) },
                            set: { model.setAISelected(option.aiID, selected: $0) }
                        ))
                    }
                }

                Section {
                    Button("확인") { model.confirmAISelection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canConfirmAISelection(request))
                    Button("취소", role: .cancel) { model.cancelAISelection() }
                }
            }
            .navigationTitle("AI 플레이어 선택")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .accessibilityAction(.escape) { model.cancelAISelection() }
        }
    }
}
