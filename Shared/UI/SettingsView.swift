import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var refreshDays = Prefs.refreshDays
    @State private var confirmLogout = false
    @State private var epgTick = 0
    @State private var tmdbKey = Store.tmdbKey
    @State private var tmdbTest = ""
    @ObservedObject private var sync = LanSync.shared
    @State private var syncOn = Prefs.syncOn
    @State private var syncPeer = Prefs.syncPeer

    private var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }

    private var catalogLine: String {
        guard let c = model.catalog else { return "Pas encore chargé" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        f.timeStyle = .short
        return "\(c.vod.count) films, \(c.series.count) séries · mis à jour le \(f.string(from: c.date))"
    }

    var body: some View {
            Form {
                Section("Profil") {
                    HStack(spacing: 16) {
                        ProfileAvatar(profile: model.profile, size: Theme.tv ? 70 : 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.profile.name).font(.headline)
                            Text("Favoris, listes, reprises, notes, couleur et réglages du lecteur propres à ce profil.")
                                .font(.footnote).foregroundStyle(Theme.dim)
                        }
                    }
                    Button { model.pickingProfile = true } label: {
                        Label(model.profiles.count > 1 ? "Changer de profil" : "Ajouter ou gérer les profils", systemImage: "person.2")
                    }
                }
                Section("Compte") {
                    if let s = model.status { Text(s.summary) }
                    if let a = model.account { Text("Serveur : \(a.host)").foregroundStyle(Theme.dim) }
                    Button("Se déconnecter", role: .destructive) { confirmLogout = true }
                }
                Section("Catalogue") {
                    Text(catalogLine)
                    if model.loading {
                        HStack { ProgressView(); Text(model.progress) }
                    } else {
                        Button("Actualiser maintenant") { model.refresh() }
                    }
                    if let e = model.error { Text(e).foregroundStyle(Theme.accent) }
                    Picker("Actualisation automatique", selection: $refreshDays) {
                        ForEach(1...5, id: \.self) { d in Text(d == 1 ? "Chaque jour" : "Tous les \(d) jours").tag(d) }
                    }
                    .onChange(of: refreshDays) { _, v in Prefs.refreshDays = v }
                }
                Section("Affichage") {
                    NavigationLink { AccentView() } label: {
                        HStack {
                            Text("Couleur d'accent")
                            Spacer()
                            Circle().fill(Theme.accent).frame(width: 18, height: 18)
                        }
                    }
                    NavigationLink("Catégories affichées") { HiddenCategoriesView() }
                    if !Store.prefQuality.isEmpty {
                        Text("Qualité préférée : \(Store.prefQuality) (la dernière choisie, proposée d'office)").foregroundStyle(Theme.dim)
                    }
                }
                Section("TMDB (facultatif)") {
                    TextField("Clé TMDB (themoviedb.org > Paramètres > API)", text: $tmdbKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { model.setTmdbKey(tmdbKey) }
                    HStack(spacing: 20) {
                        Button("Enregistrer") { model.setTmdbKey(tmdbKey) }
                        Button("Tester la clé") {
                            model.setTmdbKey(tmdbKey)
                            Task { tmdbTest = await Tmdb.shared.test() }
                        }
                    }
                    if !tmdbTest.isEmpty { Text(tmdbTest).foregroundStyle(Theme.dim) }
                    Text("Avec une clé gratuite : notes TMDB sur les fiches et les affiches, résumé en français, date, durée, bande-annonce, "
                         + "images des épisodes, photos des acteurs, rangées « Populaires · France ». "
                         + "Ce produit utilise l'API TMDB mais n'est ni approuvé ni certifié par TMDB.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                Section("Guide des programmes") {
                    Toggle("Charger à l'ouverture du Direct", isOn: Binding(get: { Prefs.epgAuto }, set: { Prefs.epgAuto = $0; epgTick += 1 }))
                    TextField("Adresse XMLTV (vide = celle du fournisseur)", text: Binding(get: { Prefs.epgUrl }, set: { Prefs.epgUrl = $0; epgTick += 1 }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Charger le guide maintenant") { model.loadEpg() }
                    if !model.epgStatus.isEmpty { Text(model.epgStatus).foregroundStyle(Theme.dim) }
                }
                Section("Synchronisation par le Wi-Fi") {
                    Toggle("Synchroniser avec mes autres appareils", isOn: $syncOn)
                        .onChange(of: syncOn) { _, v in Prefs.syncOn = v; model.updateSync(active: true) }
                    if syncOn {
                        let found = Array(Set(sync.devices.values)).sorted()
                        Text("Adresse de cet appareil : \(LanSync.localIP())")
                        Text("Appareils trouvés : " + (found.isEmpty ? (sync.peers.isEmpty ? "aucun pour le moment" : sync.peers.keys.sorted().joined(separator: ", "))
                                                        : found.joined(separator: ", ")))
                            .foregroundStyle(Theme.dim)
                        TextField("Adresse d'un autre appareil (si non trouvé), ex. 192.168.1.20", text: $syncPeer)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                            .onSubmit { Prefs.syncPeer = syncPeer.trimmed }
                        Button("Synchroniser maintenant") {
                            Prefs.syncPeer = syncPeer.trimmed
                            sync.syncAll()
                        }
                        if !sync.info.isEmpty { Text(sync.info).font(.footnote).foregroundStyle(Theme.dim) }
                    }
                    Text("Profils, et pour chacun reprise de lecture, vus, favoris, listes, notes, séries suivies, catégories masquées et couleur, "
                         + "plus la clé TMDB, "
                         + "passent d'un appareil à l'autre (TV Android comprise) quand l'appli est ouverte sur le même Wi-Fi, avec le même compte. "
                         + "Pour chaque donnée, la modification la plus récente l'emporte. Les identifiants ne sont jamais envoyés.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                Section("Recherche par acteur") {
                    Text("Distribution connue pour \(model.indexing ? model.indexDone : model.indexedCount) films sur \(model.filmCount).")
                    Button(model.indexing ? "Arrêter l'indexation" : "Indexer les acteurs des films") { model.toggleIndexing() }
                    Text("Lit la fiche de chaque film, une à la fois (long : plusieurs dizaines de minutes). Les séries sont déjà indexées.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                Section("Diagnostic du lecteur") {
                    Text("Dernière lecture : " + (Prefs.playerNote.isEmpty ? "aucune" : Prefs.playerNote))
                    Text("Dernière erreur : " + (Prefs.playerErr.isEmpty ? "aucune" : Prefs.playerErr)).foregroundStyle(Theme.dim)
                    Text("Lecteur VLC. L'appli essaie plusieurs adresses (extension annoncée, .mkv, .mp4, .ts…) et retient celle qui marche.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                Section("À propos") {
                    Text("IptvTV pour \(Theme.tv ? "Apple TV" : "iPhone et iPad") · version \(version)")
                    Text("Version 0.14 : qualités des chaînes regroupées aussi d’après la catégorie.").foregroundStyle(Theme.dim)
                }
            }
            .navigationTitle("Réglages")
        .confirmationDialog("Se déconnecter ? Le catalogue enregistré sera effacé de cet appareil.", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { model.logout() }
            Button("Annuler", role: .cancel) {}
        }
    }
}

/// Onglet à venir.
struct ComingSoon: View {
    let title: String
    let step: String
    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.title2.bold()).foregroundStyle(Theme.light)
            Text("Arrive \(step).").foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}


/// Couleur d'accent : palette d'Android, ou couleur personnalisée (teinte et saturation).
struct AccentView: View {
    @EnvironmentObject var model: AppModel
    @State private var hue = Store.customHue
    @State private var sat = Store.customSat

    var body: some View {
        Form {
            Section("Palette") {
                ForEach(Array(Accent.palette.enumerated()), id: \.offset) { i, c in
                    Button { model.setAccent(i) } label: {
                        HStack {
                            Circle().fill(Accent.rgb(c.1)).frame(width: 22, height: 22)
                            Text(c.0)
                            Spacer()
                            if Store.accent == i { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Section("Personnalisée") {
                HStack {
                    Circle().fill(Color(hue: hue / 360, saturation: sat, brightness: 0.92)).frame(width: 22, height: 22)
                    Text("Teinte \(Int(hue))°, saturation \(Int(sat * 100)) %")
                    Spacer()
                    if Store.accent == Accent.customIndex { Image(systemName: "checkmark") }
                }
                #if os(iOS)
                Slider(value: $hue, in: 0...359) { _ in model.setCustomAccent(hue: hue, sat: sat) }
                Slider(value: $sat, in: 0.2...1) { _ in model.setCustomAccent(hue: hue, sat: sat) }
                #else
                HStack(spacing: 30) {
                    Button("Teinte −") { hue = (hue + 345).truncatingRemainder(dividingBy: 360); model.setCustomAccent(hue: hue, sat: sat) }
                    Button("Teinte +") { hue = (hue + 15).truncatingRemainder(dividingBy: 360); model.setCustomAccent(hue: hue, sat: sat) }
                }
                HStack(spacing: 30) {
                    Button("Saturation −") { sat = max(0.2, sat - 0.1); model.setCustomAccent(hue: hue, sat: sat) }
                    Button("Saturation +") { sat = min(1, sat + 0.1); model.setCustomAccent(hue: hue, sat: sat) }
                }
                #endif
                Button("Utiliser cette couleur") { model.setCustomAccent(hue: hue, sat: sat) }
            }
        }
        .navigationTitle("Couleur d'accent")
    }
}

/// Catégories affichées, par type. Une catégorie masquée disparaît des rangées, des tuiles et de la recherche ;
/// favoris, listes et « Reprendre » ne changent pas.
struct HiddenCategoriesView: View {
    @EnvironmentObject var model: AppModel
    @State private var tick = 0

    var body: some View {
        let hidden = Store.hiddenCats
        let _ = tick
        Form {
            Section {
                link("Films", "film", type: "vod", cats: model.catalog?.vodCats ?? [], hidden: hidden)
                link("Séries", "tv", type: "series", cats: model.catalog?.serCats ?? [], hidden: hidden)
                if model.liveCatsOrder.isEmpty {
                    Label("Direct : ouvrez l'onglet Direct une fois pour charger les catégories.", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(Theme.dim)
                } else {
                    link("Direct", "dot.radiowaves.left.and.right", type: "live", cats: model.liveCatsOrder, hidden: hidden)
                }
            } footer: {
                Text("Une catégorie masquée disparaît des rangées, des tuiles, des recommandations et de la recherche. "
                     + "Favoris, listes et « Reprendre » ne changent pas.")
            }
        }
        .navigationTitle("Catégories affichées")
        .onAppear { tick += 1 }
    }

    private func link(_ title: String, _ icon: String, type: String, cats: [String], hidden: Set<String>) -> some View {
        let shown = cats.filter { !hidden.contains(type + "|" + $0) }.count
        return NavigationLink {
            CategoryToggleList(title: title, type: type, cats: cats)
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text(shown == cats.count ? "Toutes (\(cats.count))" : "\(shown) sur \(cats.count)").foregroundStyle(Theme.dim)
            }
        }
    }
}

/// Catégories d'un type (films, séries ou direct), avec un filtre et « Tout afficher / Tout masquer ».
struct CategoryToggleList: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let type: String
    let cats: [String]
    @State private var hidden = Store.hiddenCats
    @State private var filter = ""

    var body: some View {
        let k = Names.searchKey(filter.trimmed)
        let list = k.isEmpty ? cats : cats.filter { Names.searchKey($0).contains(k) }
        Form {
            Section {
                TextField("Filtrer les catégories", text: $filter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack(spacing: 20) {
                    Button("Tout afficher") { for c in list { set(type + "|" + c, false) } }
                    Button("Tout masquer") { for c in list { set(type + "|" + c, true) } }
                }
            }
            Section("\(list.filter { !hidden.contains(type + "|" + $0) }.count) affichées sur \(list.count)") {
                ForEach(list, id: \.self) { c in
                    let key = type + "|" + c
                    Toggle(c, isOn: Binding(get: { !hidden.contains(key) }, set: { set(key, !$0) }))
                }
            }
        }
        .navigationTitle(title)
    }

    private func set(_ k: String, _ h: Bool) {
        if h { hidden.insert(k) } else { hidden.remove(k) }
        model.setHidden(hidden)
    }
}
