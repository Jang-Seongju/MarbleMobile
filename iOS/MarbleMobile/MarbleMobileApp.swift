import SwiftUI
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
        }
        .onChange(of: scenePhase) { _, newPhase in
            model.setApplicationSceneActive(newPhase == .active)
        }
    }
}
