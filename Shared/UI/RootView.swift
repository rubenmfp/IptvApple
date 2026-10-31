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
    #if os(tvOS)
    @StateObject private var tabGeo = TabBarGeometry()
    #endif
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
        // comme sur Android : pastille du profil à gauche de la loupe (elle se sélectionne et ouvre « Qui regarde ? »),
        // heure et date à droite ; masquées quand on descend dans la page
        .background(TabBarProbe(geo: tabGeo))
        .overlay(alignment: .topLeading) {
            // la pastille se place juste à gauche de la loupe, centrée sur la même ligne (position lue dans la barre)
            GeometryReader { g in
                let o = g.frame(in: .global).origin
                let r = tabGeo.firstItem
                let size: CGFloat = r.map { min(58, max(44, $0.height * 0.8)) } ?? 58
                let x: CGFloat = r.map { $0.minX - 34 - size - o.x } ?? 90
                let y: CGFloat = r.map { $0.midY - size / 2 - o.y } ?? 50
                TopAvatar(size: size)
                    .focusSection()
                    .padding(.leading, max(0, x))
                    .padding(.top, max(0, y))
            }
            .ignoresSafeArea()
            .opacity(chrome.atTop ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: chrome.atTop)
            .disabled(!chrome.atTop)
        }
        .overlay(alignment: .topTrailing) {
            // heure et date : à droite, centrées sur la même ligne que les onglets
            GeometryReader { g in
                let o = g.frame(in: .global).origin
                let y: CGFloat = tabGeo.firstItem.map { $0.midY - 31 - o.y } ?? 50
                HStack {
                    Spacer(minLength: 0)
                    TopClock().frame(height: 62)
                }
                .padding(.trailing, 90)
                .padding(.top, max(0, y))
            }
            .ignoresSafeArea()
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

/// Pastille du profil en cours : sélectionnable, elle ouvre « Qui regarde ? ».
struct TopAvatar: View {
    @EnvironmentObject var model: AppModel
    var size: CGFloat = Theme.tv ? 58 : 30
    var body: some View {
        Button { model.pickingProfile = true } label: {
            ProfileAvatar(profile: model.profile, size: size, circle: true)
        }
        .buttonStyle(TopAvatarStyle(name: model.profile.name))
        .shadow(color: .black.opacity(0.6), radius: 6)
    }
}

/// Heure en couleur d'accent et date en dessous.
struct TopClock: View {
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    var body: some View {
        SwiftUI.TimelineView(.everyMinute) { ctx in
            VStack(alignment: .trailing, spacing: 0) {
                Text(Self.time.string(from: ctx.date))
                    .font(.system(size: Theme.tv ? 38 : 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                Text(Self.date.string(from: ctx.date))
                    .font(.system(size: Theme.tv ? 20 : 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 6)
    }
}

/// Pastille du profil en haut : à la sélection, elle grossit, s'entoure de blanc et affiche « Changer de profil ».
private struct TopAvatarStyle: ButtonStyle {
    let name: String
    func makeBody(configuration: Configuration) -> some View { TopAvatarBody(configuration: configuration, name: name) }
}

private struct TopAvatarBody: View {
    let configuration: ButtonStyleConfiguration
    let name: String
    @Environment(\.isFocused) private var focused
    var body: some View {
        configuration.label
            .overlay(Circle().strokeBorder(.white, lineWidth: focused ? 4 : 0))
            .scaleEffect(focused ? 1.2 : (configuration.isPressed ? 0.92 : 1))
            .shadow(color: .black.opacity(focused ? 0.6 : 0), radius: 10, y: 4)
            .overlay(alignment: .bottom) {
                if focused {
                    // deux lignes, centrées sous la pastille
                    VStack(spacing: 2) {
                        Text(name).font(.caption.weight(.bold))
                        Text("Changer de profil").font(.caption2).opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.78)))
                    .offset(y: Theme.tv ? 74 : 34)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

#if os(tvOS)
/// Position du premier onglet (la loupe) à l'écran, lue dans la barre d'onglets du système.
final class TabBarGeometry: ObservableObject {
    @Published var firstItem: CGRect?
}

/// Vue invisible qui mesure la barre d'onglets (elle se construit après coup, et se déplace quand elle se masque).
struct TabBarProbe: UIViewRepresentable {
    let geo: TabBarGeometry

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.geo = geo
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ v: ProbeView, context: Context) { v.measure() }

    final class ProbeView: UIView {
        weak var geo: TabBarGeometry?
        private var timer: Timer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            timer?.invalidate()
            timer = nil
            guard window != nil else { return }
            measure()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.measure() }
        }

        func measure() {
            guard let w = window, let bar = Self.find(UITabBar.self, in: w) else { return }
            // boutons des onglets : contrôles de taille raisonnable dans la barre
            var items: [CGRect] = []
            Self.controls(in: bar, w, into: &items, barWidth: bar.bounds.width)
            // barre masquée (hors de l'écran) : on garde la dernière position
            guard let first = items.min(by: { $0.minX < $1.minX }), first.maxY > 0 else { return }
            let r = first.integral
            if geo?.firstItem != r { geo?.firstItem = r }
        }

        private static func find<T: UIView>(_ t: T.Type, in v: UIView) -> T? {
            if let x = v as? T { return x }
            for s in v.subviews { if let x = find(t, in: s) { return x } }
            return nil
        }

        private static func controls(in v: UIView, _ w: UIWindow, into out: inout [CGRect], barWidth: CGFloat) {
            for s in v.subviews where !s.isHidden && s.alpha > 0.01 {
                if s is UIControl, s.bounds.width > 30, s.bounds.height > 30, s.bounds.width < barWidth / 2 {
                    out.append(s.convert(s.bounds, to: w))
                } else {
                    controls(in: s, w, into: &out, barWidth: barWidth)
                }
            }
        }
    }
}
#endif
