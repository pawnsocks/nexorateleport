import SwiftUI

@main
struct NexoraTeleportApp: App {
    @StateObject private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(appModel.location)
                .environmentObject(appModel.routeEngine)
                .environmentObject(appModel.routineEngine)
                .task { await appModel.bootstrap() }
                .onOpenURL { appModel.handleDeepLink($0) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            appModel.handleScenePhase(newPhase)
        }
    }
}
