import SwiftUI
import UIKit
import MarbleMobileCore

@main
struct MarbleMobileApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.screen {
            case .login:
                LoginView()
            case .lobby:
                LobbyView()
            case .gameRoom:
                GameRoomView()
            }
        }
        .onAppear {
            model.setApplicationSceneActive(scenePhase == .active)
            updateIdleTimer(for: scenePhase)
        }
        .onChange(of: scenePhase) { _, newPhase in
            model.setApplicationSceneActive(newPhase == .active)
            updateIdleTimer(for: newPhase)
        }
        .sheet(item: $model.utilitySheet) { sheet in
            Group {
                switch sheet {
                case .receiveNotifications:
                    ReceiveNotificationsView()
                case .invitations:
                    InvitationInboxView()
                case .privateMessages:
                    PrivateMessagesView()
                case .noteMailbox:
                    NoteMailboxView()
                case .friendManagement:
                    FriendManagementView()
                }
            }
            .environmentObject(model)
        }
    }

    private func updateIdleTimer(for phase: ScenePhase) {
        UIApplication.shared.isIdleTimerDisabled = phase != .background
    }
}
