import SwiftUI
import MarbleMobileCore

struct SpectatorPasswordView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let target: SpectatorTarget
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(target.nickname)의 관중석")
                    SecureField("비밀번호", text: $password)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                }

                if let message = model.spectatorErrorMessage, !message.isEmpty {
                    Text(message)
                        .accessibilityLabel("오류")
                        .accessibilityValue(message)
                }
            }
            .navigationTitle("비공개방")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        model.cancelSpectatorPassword()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("입장") { submit() }
                }
            }
        }
    }

    private func submit() {
        model.submitSpectatorPassword(password)
        if model.spectatorPhase == .joinPending {
            password = ""
        }
    }
}
