import SwiftUI

@main
struct IptvApp: App {
    @StateObject private var model = AppModel()
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active { model.refreshIfStale() }
            // synchronisation Wi-Fi : seulement quand l'appli est au premier plan
            model.updateSync(active: p != .background)
        }
        .onChange(of: model.phase) { _, _ in model.updateSync(active: scenePhase != .background) }
    }
}
