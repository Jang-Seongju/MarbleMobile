import SwiftUI
import MarbleMobileCore

struct ReceiveSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ReceiveSettings()

    var body: some View {
        NavigationStack {
            Form {
                Picker("메시지", selection: $draft.message) {
                    ForEach(ReceiveAudience.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("쪽지", selection: $draft.note) {
                    ForEach(ReceiveAudience.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("초대", selection: $draft.invitation) {
                    ForEach(ReceiveAudience.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("친구 요청", selection: $draft.friendRequest) {
                    ForEach(FriendRequestAudience.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            .navigationTitle("수신 설정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { model.utilitySheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("확인") { model.saveReceiveSettings(draft) }
                        .disabled(!model.canOpenReceiveSettings)
                }
            }
            .onAppear { draft = model.socialState.receiveSettings }
        }
    }
}
