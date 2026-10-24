import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .starting: Theme.bg.ignoresSafeArea()
            case .login: LoginView()
            case .ready: MainTabs()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

struct MainTabs: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 1

    var body: some View {
        TabView(selection: $tab) {
            BrowseView(rows: model.derived.home, hero: model.derived.heroHome)
                .tabItem { Label("Accueil", systemImage: "house") }
                .tag(1)
            BrowseView(rows: model.derived.vod, hero: model.derived.heroVod)
                .tabItem { Label("Films", systemImage: "film") }
                .tag(2)
            BrowseView(rows: model.derived.series, hero: model.derived.heroSeries)
                .tabItem { Label("Séries", systemImage: "tv") }
                .tag(3)
            ComingSoon(title: "Direct", step: "à l'étape 6")
                .tabItem { Label("Direct", systemImage: "dot.radiowaves.left.and.right") }
                .tag(4)
            SettingsView()
                #if os(tvOS)
                .tabItem { Image(systemName: "gearshape") }
                #else
                .tabItem { Label("Plus", systemImage: "ellipsis") }
                #endif
                .tag(5)
        }
    }
}
