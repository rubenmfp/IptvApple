import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var refreshDays = Prefs.refreshDays
    @State private var confirmLogout = false
    @State private var epgTick = 0
    @State private var tmdbKey = Store.tmdbKey
    @State private var tmdbTest = ""

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
                Section("Recherche par acteur") {
                    Text("Distribution connue pour \(model.indexing ? model.indexDone : model.indexedCount) films sur \(model.filmCount).")
                    Button(model.indexing ? "Arrêter l'indexation" : "Indexer les acteurs des films") { model.toggleIndexing() }
                    Text("Lit la fiche de chaque film, une à la fois (long : plusieurs dizaines de minutes). Les séries sont déjà indexées.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                Section("À propos") {
                    Text("IptvTV pour \(Theme.tv ? "Apple TV" : "iPhone et iPad") · version \(version)")
                    Text("Version 0.7 : Sorties, TMDB, recommandations.").foregroundStyle(Theme.dim)
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
    @State private var hidden = Store.hiddenCats

    var body: some View {
        Form {
            section("Films", type: "vod", cats: model.catalog?.vodCats ?? [])
            section("Séries", type: "series", cats: model.catalog?.serCats ?? [])
            if model.liveCatsOrder.isEmpty {
                Section("Chaînes") { Text("Ouvrez l'onglet Direct une fois pour charger les catégories de chaînes.").foregroundStyle(Theme.dim) }
            } else {
                section("Chaînes", type: "live", cats: model.liveCatsOrder)
            }
        }
        .navigationTitle("Catégories affichées")
    }

    private func section(_ title: String, type: String, cats: [String]) -> some View {
        Section("\(title) · \(cats.filter { !hidden.contains(type + "|" + $0) }.count) sur \(cats.count)") {
            HStack(spacing: 20) {
                Button("Tout afficher") { for c in cats { set(type + "|" + c, false) } }
                Button("Tout masquer") { for c in cats { set(type + "|" + c, true) } }
            }
            ForEach(cats, id: \.self) { c in
                let k = type + "|" + c
                Toggle(c, isOn: Binding(get: { !hidden.contains(k) }, set: { set(k, !$0) }))
            }
        }
    }

    private func set(_ k: String, _ h: Bool) {
        if h { hidden.insert(k) } else { hidden.remove(k) }
        model.setHidden(hidden)
    }
}
