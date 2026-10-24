import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var refreshDays = Prefs.refreshDays
    @State private var confirmLogout = false

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
        NavigationStack {
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
                Section("À propos") {
                    Text("IptvTV pour \(Theme.tv ? "Apple TV" : "iPhone et iPad") · version \(version)")
                    Text("Étape 3 : lecture (moteur VLC). Fiche complète et épisodes à l'étape 4.").foregroundStyle(Theme.dim)
                }
            }
            .navigationTitle("Réglages")
        }
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
