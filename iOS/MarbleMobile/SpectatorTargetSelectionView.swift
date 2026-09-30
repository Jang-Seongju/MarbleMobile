import SwiftUI
import MarbleMobileCore

struct SpectatorTargetSelectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let targetList: SpectatorTargetList

    var body: some View {
        NavigationStack {
            List {
                Section("관전할 플레이어") {
                    ForEach(targetList.targets) { target in
                        Button("\(target.nickname)의 관중석") {
                            model.selectSpectatorTarget(target)
                        }
                    }
                }
            }
            .navigationTitle("관중석 입장")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        model.cancelSpectatorTargetSelection()
                        dismiss()
                    }
                }
            }
        }
    }
}
