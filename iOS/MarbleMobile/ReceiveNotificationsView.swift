import SwiftUI
import MarbleMobileCore

struct ReceiveNotificationsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.unreadPrivateMessageSenderCount > 0 {
                    Button(ReceiveNotificationKind.messages.title(count: model.unreadPrivateMessageSenderCount)) {
                        model.openPrivateMessagesFromNotifications()
                    }
                }
                if model.unreadNoteCount > 0 {
                    Button(ReceiveNotificationKind.notes.title(count: model.unreadNoteCount)) {
                        model.openNotesFromNotifications()
                    }
                }
                if !model.invitations.isEmpty {
                    Button(ReceiveNotificationKind.invitations.title(count: model.invitations.count)) {
                        model.openInvitationsFromNotifications()
                    }
                }
                if model.unreadFriendRequestCount > 0 {
                    Button(ReceiveNotificationKind.friendRequests.title(count: model.unreadFriendRequestCount)) {
                        model.openFriendRequestsFromNotifications()
                    }
                }
                if !model.hasReceiveNotifications {
                    Text("수신 알림 없음")
                }
            }
            .navigationTitle("수신 알림")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
