import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .starting: Theme.bg.ignoresSafeArea()
            case .login: LoginView()
            case .ready:
                if model.pickingProfile { ProfilePickerView() } else { MainTabs() }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
        .id(model.appearance)          // couleur d'accent changée : tout est redessiné
    }
}

struct MainTabs: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 1
    @State private var newName = ""

    var body: some View {
        TabView(selection: $tab) {
            #if os(tvOS)
            // Apple TV : la loupe en premier, puis Accueil, Films, Séries, Direct, puis cœur, cloche, molette
            SearchView()
                .tabItem { Image(systemName: "magnifyingglass") }
                .tag(0)
            #endif
            BrowseView(rows: model.rows(for: "home"), hero: model.hero(for: "home"))
                .tabItem { Label("Accueil", systemImage: "house") }
                .tag(1)
            BrowseView(rows: model.rows(for: "vod"), hero: model.hero(for: "vod"))
                .tabItem { Label("Films", systemImage: "film") }
                .tag(2)
            BrowseView(rows: model.rows(for: "series"), hero: model.hero(for: "series"))
                .tabItem { Label("Séries", systemImage: "tv") }
                .tag(3)
            LiveView()
                .tabItem { Label("Direct", systemImage: "dot.radiowaves.left.and.right") }
                .tag(4)
            #if os(tvOS)
            NavigationStack { ListsView() }
                .tabItem { Image(systemName: "heart") }
                .tag(6)
            SortiesView()
                .tabItem { Image(systemName: model.news.isEmpty ? "bell" : "bell.badge") }
                .tag(7)
            NavigationStack { SettingsView() }
                .tabItem { Image(systemName: "gearshape") }
                .tag(5)
            #else
            PlusView()
                .tabItem { Label("Plus", systemImage: "ellipsis") }
                .tag(5)
            #endif
        }
        .alert("Nouvelle liste", isPresented: Binding(get: { model.newListFor != nil }, set: { if !$0 { model.newListFor = nil } })) {
            TextField("Nom de la liste", text: $newName)
            Button("Créer") {
                model.createList(newName, with: model.newListFor)
                newName = ""
                model.newListFor = nil
            }
            Button("Annuler", role: .cancel) { newName = ""; model.newListFor = nil }
        } message: {
            if let i = model.newListFor { Text("« \(i.name) » y sera ajouté.") }
        }
    }
}
