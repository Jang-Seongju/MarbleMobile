import SwiftUI

/// A stable toolbar item. Count changes never request accessibility focus.
struct ReceiveNotificationButton: View {
    @EnvironmentObject private var model: AppModel
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    var body: some View {
        Button {
            isAccessibilityFocused = false
            model.presentReceiveNotifications(returnToButton: true)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bell")
                Text("\(model.receiveNotificationTotalCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 24)
            }
            .frame(width: 60, height: 44)
            .contentShape(Rectangle())
        }
        .disabled(!model.canOpenReceiveNotifications)
        .accessibilityLabel("수신 알림")
        .accessibilityValue(model.hasReceiveNotifications ? "\(model.receiveNotificationTotalCount)" : "없음")
        .accessibilityFocused($isAccessibilityFocused)
        .onChange(of: model.receiveNotificationFocusReturnID) { _, _ in
            guard model.canOpenReceiveNotifications else { return }
            isAccessibilityFocused = true
        }
    }
}
