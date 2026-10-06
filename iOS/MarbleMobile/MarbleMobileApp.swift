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
            MobileDiagnosticLog.shared.record("SCENE", "onAppear phase=\(phaseName(scenePhase))")
            model.setApplicationSceneActive(scenePhase == .active)
            updateIdleTimer(for: scenePhase)
        }
        .onChange(of: scenePhase) { _, newPhase in
            MobileDiagnosticLog.shared.record("SCENE", "phase=\(phaseName(newPhase))")
            model.setApplicationSceneActive(newPhase == .active)
            updateIdleTimer(for: newPhase)
        }
        .sheet(item: $model.utilitySheet) { sheet in
            Group {
                switch sheet {
                case .mediaManagement:
                    MediaManagementView()
                case .receiveSettings:
                    ReceiveSettingsView()
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
        .sheet(item: $model.informationDocument) { document in
            InformationDocumentView(
                title: document.title,
                lines: document.lines,
                onClose: { model.informationDocument = nil }
            )
        }
    }

    private func updateIdleTimer(for phase: ScenePhase) {
        UIApplication.shared.isIdleTimerDisabled = phase != .background
    }

    private func phaseName(_ phase: ScenePhase) -> String {
        switch phase {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
}
