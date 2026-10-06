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

                volumeSlider("효과음 및 음성 볼륨", keyPath: \.sfxVolume)

                Toggle("배경음 사용", isOn: Binding(
                    get: { model.mediaSettings.bgmEnabled },
                    set: { value in
                        var next = model.mediaSettings
                        next.bgmEnabled = value
                        model.setMediaSettings(next)
                    }
                ))

                volumeSlider("배경음 볼륨", keyPath: \.bgmVolume)
            }
            .navigationTitle("미디어 관리")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { model.utilitySheet = nil }
                }
            }
        }
    }

    private func volumeSlider(
        _ title: String,
        keyPath: WritableKeyPath<MediaSettings, Int>
    ) -> some View {
        Slider(value: Binding(
            get: { Double(model.mediaSettings[keyPath: keyPath]) },
            set: { value in setVolume(Int(value.rounded()), keyPath: keyPath) }
        ), in: 0...100, step: 1) {
            Text(title)
        }
        .accessibilityValue("\(model.mediaSettings[keyPath: keyPath])퍼센트")
        .accessibilityHint("위로 쓸면 감소하고 아래로 쓸면 증가합니다.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjustVolume(-1, keyPath: keyPath)
            case .decrement: adjustVolume(1, keyPath: keyPath)
            @unknown default: break
            }
        }
    }

    private func setVolume(_ value: Int, keyPath: WritableKeyPath<MediaSettings, Int>) {
        var next = model.mediaSettings
        next[keyPath: keyPath] = min(100, max(0, value))
        if next != model.mediaSettings { model.setMediaSettings(next) }
    }

    private func adjustVolume(_ amount: Int, keyPath: WritableKeyPath<MediaSettings, Int>) {
        setVolume(model.mediaSettings[keyPath: keyPath] + amount, keyPath: keyPath)
    }
}
