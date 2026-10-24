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
    @StateObject private var chrome = ChromeState()
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
        .environment(\.chrome, chrome)
        .onChange(of: tab) { _, _ in chrome.atTop = true }
        #if os(tvOS)
        // comme sur Android : profil en cours, heure et date, à droite de la barre des onglets (masqués quand on descend)
        .overlay(alignment: .topTrailing) {
            TopInfo()
                .padding(.top, 2)
                .opacity(chrome.atTop ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: chrome.atTop)
                .allowsHitTesting(false)
        }
        #endif
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

/// Haut de l'écran visible ou non (Apple TV : le profil et l'heure ne s'affichent qu'avec la barre des onglets).
final class ChromeState: ObservableObject {
    @Published var atTop = true
}

/// Repère placé en tête d'une page qui défile : indique si l'on est en haut.
struct TopMarker: View {
    @Environment(\.chrome) private var chrome
    var body: some View {
        GeometryReader { g in
            let top = g.frame(in: .global).minY > 20
            Color.clear
                .onAppear { set(top) }
                .onChange(of: top) { _, v in set(v) }
        }
        .frame(height: 0)
    }
    private func set(_ v: Bool) { if let c = chrome, c.atTop != v { c.atTop = v } }
}

private struct ChromeKey: EnvironmentKey { static let defaultValue: ChromeState? = nil }
extension EnvironmentValues {
    var chrome: ChromeState? {
        get { self[ChromeKey.self] }
        set { self[ChromeKey.self] = newValue }
    }
}

/// Profil en cours (pastille ronde), heure en couleur d'accent et date en dessous.
struct TopInfo: View {
    @EnvironmentObject var model: AppModel
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    var body: some View {
        HStack(spacing: Theme.tv ? 22 : 10) {
            ProfileAvatar(profile: model.profile, size: Theme.tv ? 58 : 30, circle: true)
            SwiftUI.TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.time.string(from: ctx.date))
                        .font(.system(size: Theme.tv ? 38 : 18, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                    Text(Self.date.string(from: ctx.date))
                        .font(.system(size: Theme.tv ? 20 : 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 6)
    }
}
