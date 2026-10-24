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
    /// Contenu par clé, et par la clé de chacune de ses versions (une reprise survit ainsi au regroupement).
    var byKey: [String: Item] = [:]

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
        var bk: [String: Item] = [:]
        bk.reserveCapacity((c.vod.count + c.series.count) * 2)
        for i in c.vod + c.series {
            bk[i.key] = i
            for v in i.variants where bk["\(i.type):\(v.id)"] == nil { bk["\(i.type):\(v.id)"] = i }
        }
        r.byKey = bk
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
    /// Change quand une lecture se termine (rangées « Reprendre », barres de progression).
    @Published private(set) var progressTick = 0

    // chaînes (Direct)
    @Published private(set) var live: [Item] = []
    @Published private(set) var liveRows: [Row] = []
    @Published private(set) var liveLoading = false
    @Published var liveError: String?

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

    // ---------- reprise ----------
    func progressChanged() { progressTick += 1 }

    /// Position enregistrée d'un contenu (sur l'une de ses versions) : (clé, position, durée).
    static func progress(of item: Item) -> (key: String, pos: Int, dur: Int)? {
        for v in item.variants {
            let k = "\(item.type):\(v.id)"
            let p = Store.pos(k)
            if p > 0 { return (k, p, Store.dur(k)) }
        }
        return nil
    }

    /// Rangée « Reprendre » : lectures récentes pas terminées, du type demandé (nil = tous).
    func resumeRow(_ type: String?) -> Row? {
        _ = progressTick
        var seen = Set<String>()
        let items = Store.recent.compactMap { derived.byKey[$0] }
            .filter { (type == nil || $0.type == type) && seen.insert($0.key).inserted }
            .filter { $0.type != "vod" || Self.progress(of: $0) != nil }
        guard !items.isEmpty else { return nil }
        return Row(id: "resume|\(type ?? "*")", title: "Reprendre", items: items)
    }

    /// Rangée « Mes favoris » (films et séries).
    func favoritesRow(_ type: String?) -> Row? {
        _ = progressTick
        var seen = Set<String>()
        let items = Store.favs.compactMap { derived.byKey[$0] }
            .filter { (type == nil || $0.type == type) && seen.insert($0.key).inserted }
        return items.isEmpty ? nil : Row(id: "favs|\(type ?? "*")", title: "Mes favoris", items: items)
    }

    /// Titres de la même catégorie (pour le bas de la fiche).
    func sameCategory(as item: Item) -> [Item] {
        let pool = item.type == "vod" ? catalog?.vod : catalog?.series
        return Array((pool ?? []).filter { $0.cat == item.cat && $0.key != item.key && $0.poster != nil }.shuffled().prefix(20))
    }

    // ---------- fiches ----------
    private var infoCache: [String: ItemInfo] = [:]

    func cachedInfo(_ item: Item) -> ItemInfo? { infoCache[item.key] }

    func info(for item: Item) async throws -> ItemInfo {
        if let i = infoCache[item.key] { return i }
        guard let a = account else { throw XtreamError.badCredentials }
        let i = try await XtreamClient(a).info(type: item.type, id: item.id)
        infoCache[item.key] = i
        return i
    }

    // ---------- épisodes ----------
    /// Lecture d'un épisode, avec l'épisode suivant (pour le bouton « Épisode suivant »).
    func episodeRequest(series: Item, info: ItemInfo, episode e: Episode, fromStart: Bool = false) -> PlayRequest {
        let pos = fromStart ? 0 : Store.pos(e.key)
        var r = PlayRequest(title: "\(series.name) · S\(e.season) É\(e.num) \(e.title)", key: e.key, kind: "series",
                            urls: fileURLs(kind: "series", id: e.id, ext: e.ext), startMs: pos > 10_000 ? pos : 0)
        r.seriesId = series.id
        if let i = info.episodes.firstIndex(of: e), i + 1 < info.episodes.count {
            let n = info.episodes[i + 1]
            r.next = { [weak self] in self?.episodeRequest(series: series, info: info, episode: n, fromStart: true) }
            r.nextTitle = "S\(n.season) É\(n.num) \(n.title)"
        }
        return r
    }

    /// Épisode que « Lecture » doit lancer : celui en cours, ou le suivant s'il est terminé, ou le premier.
    static func episodeToPlay(seriesId: Int, info: ItemInfo) -> (Episode, resume: Bool)? {
        guard let first = info.episodes.first else { return nil }
        let last = Store.lastEp(seriesId)
        guard last > 0, let i = info.episodes.firstIndex(where: { $0.id == last }) else { return (first, false) }
        let e = info.episodes[i]
        if Store.pos(e.key) > 10_000 { return (e, true) }
        if Store.seen(e.key), i + 1 < info.episodes.count { return (info.episodes[i + 1], false) }
        return (e, false)
    }

    // ---------- adresses de lecture ----------
    private static func safe(_ s: String) -> String {
        if s.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil { return s }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Serveur indiqué par le fournisseur (server_info) puis serveur saisi : ils peuvent différer.
    private var bases: [String] {
        var out: [String] = []
        for b in [status?.streamBase, account?.host].compactMap({ $0 }) {
            var x = b
            while x.hasSuffix("/") { x.removeLast() }
            if !out.contains(x) { out.append(x) }
        }
        return out
    }

    /// Film ou épisode : l'extension annoncée est souvent fausse ; on essaie celle qui a marché, l'annoncée, puis mkv, mp4, avi.
    func fileURLs(kind: String, id: Int, ext: String) -> [URL] {
        guard let a = account else { return [] }
        var exts: [String] = []
        for e in [Store.goodExt(kind), ext.lowercased(), "mkv", "mp4", "avi"] where !e.isEmpty && !exts.contains(e) { exts.append(e) }
        let path = kind == "vod" ? "movie" : "series"
        return bases.flatMap { b in exts.compactMap { URL(string: "\(b)/\(path)/\(Self.safe(a.user))/\(Self.safe(a.pass))/\(id).\($0)") } }
    }

    func liveURLs(id: Int) -> [URL] {
        guard let a = account else { return [] }
        let u = Self.safe(a.user), p = Self.safe(a.pass)
        return bases.flatMap { b in
            ["\(b)/live/\(u)/\(p)/\(id).ts", "\(b)/live/\(u)/\(p)/\(id).m3u8", "\(b)/\(u)/\(p)/\(id)"].compactMap(URL.init(string:))
        }
    }

    // ---------- chaînes ----------
    private struct LiveCache: Codable { var items: [Item]; var cats: [String]; var date: Date }

    func loadLive(force: Bool = false) {
        guard let a = account, !liveLoading else { return }
        if !force, !live.isEmpty { return }
        liveLoading = true
        liveError = nil
        Task {
            let url = Files.dir.appendingPathComponent("live.json")
            var cache = await Task.detached { Files.load(LiveCache.self, from: url) }.value
            if let c = cache { await applyLive(c.items, c.cats) }
            let stale = cache.map { Date().timeIntervalSince($0.date) > Double(Prefs.refreshDays) * 86_400 } ?? true
            if force || stale {
                do {
                    let r = try await XtreamClient(a).items("live")
                    cache = LiveCache(items: r.items, cats: r.cats, date: Date())
                    let c = cache!
                    await Task.detached { Files.save(c, to: url) }.value
                    await applyLive(r.items, r.cats)
                } catch {
                    liveError = Self.message(error)
                }
            }
            liveLoading = false
        }
    }

    private func applyLive(_ items: [Item], _ cats: [String]) async {
        let rows = await Task.detached { () -> [Row] in
            Derived.byCategory(items, order: cats).map { Row(id: "live|" + $0.0, title: $0.0, items: $0.1) }
        }.value
        live = items
        liveRows = rows
    }

    func recentLiveRow() -> Row? {
        _ = progressTick
        let byKey = Dictionary(live.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let items = Store.recentLive.compactMap { byKey[$0] }
        return items.isEmpty ? nil : Row(id: "live|*recent", title: "Regardées récemment", items: items)
    }

    func logout() {
        Keychain.delete()
        Store.reset()
        live = []
        liveRows = []
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
