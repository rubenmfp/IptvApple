import Foundation
import SwiftUI

/// Une rangée d'affiches.
struct Row: Identifiable {
    let id: String
    let title: String
    let items: [Item]
}

/// Rangées calculées à partir du catalogue (hors du fil de l'interface).
struct Derived {
    var home: [Row] = []
    var vod: [Row] = []
    var series: [Row] = []
    var heroHome: [Item] = []
    var heroVod: [Item] = []
    var heroSeries: [Item] = []

    /// « En vedette » : les mieux notés (avec affiche), mélangés ; sinon des titres au hasard.
    static func featured(_ pool: [Item]) -> [Item] {
        let rated = pool.filter { $0.poster != nil && $0.rating > 0 }.sorted { $0.rating > $1.rating }.prefix(120).shuffled().prefix(15)
        if !rated.isEmpty { return Array(rated) }
        return Array(pool.filter { $0.poster != nil }.shuffled().prefix(15))
    }

    /// Contenus groupés par catégorie, dans l'ordre du fournisseur (puis les catégories inconnues, ex. « Divers »).
    static func byCategory(_ items: [Item], order: [String]) -> [(String, [Item])] {
        var d: [String: [Item]] = [:]
        var seenKeys: [String: Set<String>] = [:]
        var extra: [String] = []
        for i in items {
            if d[i.cat] == nil { d[i.cat] = []; seenKeys[i.cat] = []; if !order.contains(i.cat) { extra.append(i.cat) } }
            if seenKeys[i.cat]!.insert(i.key).inserted { d[i.cat]!.append(i) }
        }
        return (order + extra).compactMap { c in d[c].flatMap { $0.isEmpty ? nil : (c, $0) } }
    }

    static func make(_ c: Catalog) -> Derived {
        var r = Derived()
        let featV = featured(c.vod), featS = featured(c.series)
        let vodCats = byCategory(c.vod, order: c.vodCats)
        let serCats = byCategory(c.series, order: c.serCats)
        func dedup(_ l: [Item]) -> [Item] { var s = Set<String>(); return l.filter { s.insert($0.key).inserted } }

        r.vod = (featV.isEmpty ? [] : [Row(id: "vod|*vedette", title: "En vedette", items: dedup(featV))])
            + vodCats.map { Row(id: "vod|" + $0.0, title: $0.0, items: $0.1) }
        r.series = (featS.isEmpty ? [] : [Row(id: "series|*vedette", title: "En vedette", items: dedup(featS))])
            + serCats.map { Row(id: "series|" + $0.0, title: $0.0, items: $0.1) }

        var home: [Row] = []
        if !featV.isEmpty { home.append(Row(id: "home|vod*", title: "Films · En vedette", items: dedup(featV))) }
        if !featS.isEmpty { home.append(Row(id: "home|series*", title: "Séries · En vedette", items: dedup(featS))) }
        home += vodCats.prefix(3).map { Row(id: "home|vod|" + $0.0, title: "Films · " + $0.0, items: $0.1) }
        home += serCats.prefix(3).map { Row(id: "home|series|" + $0.0, title: "Séries · " + $0.0, items: $0.1) }
        r.home = home

        r.heroHome = Array((featV.prefix(6) + featS.prefix(6)).filter { $0.poster != nil }.shuffled().prefix(8))
        r.heroVod = Array(featV.filter { $0.poster != nil }.prefix(8))
        r.heroSeries = Array(featS.filter { $0.poster != nil }.prefix(8))
        return r
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum Phase { case starting, login, ready }

    @Published var phase: Phase = .starting
    @Published private(set) var account: XtreamAccount?
    @Published private(set) var status: AccountStatus?
    @Published private(set) var catalog: Catalog?
    @Published private(set) var derived = Derived()
    @Published private(set) var loading = false
    @Published private(set) var progress = ""
    @Published var error: String?

    init() {
        guard let a = Keychain.load() else { phase = .login; return }
        account = a
        status = Files.load(AccountStatus.self, from: Files.status)
        phase = .ready
        Task {
            // démarrage rapide : le catalogue enregistré s'affiche tout de suite, la mise à jour se fait ensuite
            let c = await Task.detached(priority: .userInitiated) { Files.load(Catalog.self, from: Files.catalog) }.value
            if let c { await apply(c) }
            refreshIfStale()
        }
    }

    private func apply(_ c: Catalog) async {
        let d = await Task.detached(priority: .userInitiated) { Derived.make(c) }.value
        catalog = c
        derived = d
    }

    /// Recharge le catalogue s'il est plus vieux que la durée choisie dans les réglages.
    func refreshIfStale() {
        guard phase == .ready, !loading else { return }
        if let c = catalog, Date().timeIntervalSince(c.date) < Double(Prefs.refreshDays) * 86_400 { return }
        refresh()
    }

    func refresh() {
        guard let a = account, !loading else { return }
        loading = true
        error = nil
        Task {
            do {
                let client = XtreamClient(a)
                progress = "Vérification du compte…"
                let st = try await client.status()
                status = st
                Files.save(st, to: Files.status)
                progress = "Chargement des films…"
                let v = try await client.items("vod")
                progress = "Chargement des séries…"
                let s = try await client.items("series")
                progress = "Préparation des rangées…"
                let c = Catalog(vod: v.items, series: s.items, vodCats: v.cats, serCats: s.cats, date: Date())
                await Task.detached(priority: .utility) { Files.save(c, to: Files.catalog) }.value
                await apply(c)
            } catch {
                self.error = Self.message(error)
            }
            loading = false
            progress = ""
        }
    }

    /// Vérifie le compte auprès du fournisseur, l'enregistre dans le trousseau puis charge le catalogue.
    /// Rend un message d'erreur, ou nil si tout va bien.
    func login(_ a: XtreamAccount) async -> String? {
        do {
            let st = try await XtreamClient(a).status()
            guard Keychain.save(a) else { return "Impossible d'enregistrer les identifiants dans le trousseau." }
            account = a
            status = st
            Files.save(st, to: Files.status)
            phase = .ready
            refresh()
            return nil
        } catch {
            return Self.message(error)
        }
    }

    func logout() {
        Keychain.delete()
        Files.removeAll()
        account = nil
        status = nil
        catalog = nil
        derived = Derived()
        error = nil
        phase = .login
    }

    static func message(_ e: Error) -> String {
        if let x = e as? XtreamError { return x.localizedDescription }
        if let u = e as? URLError {
            switch u.code {
            case .notConnectedToInternet: return "Pas de connexion Internet."
            case .timedOut: return "Le serveur ne répond pas (délai dépassé)."
            case .cannotFindHost, .dnsLookupFailed: return "Serveur introuvable : vérifiez l'adresse."
            case .cannotConnectToHost: return "Connexion au serveur refusée : vérifiez l'adresse et le port."
            case .appTransportSecurityRequiresSecureConnection: return "Connexion non sécurisée refusée par le système."
            default: return "Erreur réseau : \(u.localizedDescription)"
            }
        }
        if e is JSONScan.Err { return "Réponse du serveur illisible." }
        return e.localizedDescription
    }
}
