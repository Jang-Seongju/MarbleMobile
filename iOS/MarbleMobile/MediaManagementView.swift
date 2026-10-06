import SwiftUI

struct MediaManagementView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Toggle("효과음 및 음성 사용", isOn: Binding(
                    get: { model.mediaSettings.sfxEnabled },
                    set: { value in
                        var next = model.mediaSettings
                        next.sfxEnabled = value
                        model.setMediaSettings(next)
                    }
                ))

                Stepper(value: Binding(
                    get: { model.mediaSettings.sfxVolume },
                    set: { value in
                        var next = model.mediaSettings
                        next.sfxVolume = value
                        model.setMediaSettings(next)
                    }
                ), in: 0...100) {
                    Text("효과음 및 음성 볼륨: \(model.mediaSettings.sfxVolume)")
                }

                Toggle("배경음 사용", isOn: Binding(
                    get: { model.mediaSettings.bgmEnabled },
                    set: { value in
                        var next = model.mediaSettings
                        next.bgmEnabled = value
                        model.setMediaSettings(next)
                    }
                ))

                Stepper(value: Binding(
                    get: { model.mediaSettings.bgmVolume },
                    set: { value in
                        var next = model.mediaSettings
                        next.bgmVolume = value
                        model.setMediaSettings(next)
                    }
                ), in: 0...100) {
                    Text("배경음 볼륨: \(model.mediaSettings.bgmVolume)")
                }
            }
            .navigationTitle("미디어 관리")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { model.utilitySheet = nil }
                }
            }
        }
    }
}
