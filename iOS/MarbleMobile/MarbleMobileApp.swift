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

    var body: some View {
        switch model.screen {
        case .login:
            LoginView()
        case .lobby:
            LobbyView()
        }
    }
}
