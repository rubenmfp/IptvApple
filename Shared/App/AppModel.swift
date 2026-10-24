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
    /// Index de recherche : contenu visible et son titre sans accents ni majuscules.
    var index: [(Item, String)] = []
    /// Contenus visibles (catégories masquées exclues), pour les classements et les recommandations.
    var vodVisible: [Item] = []
    var seriesVisible: [Item] = []

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

    static func make(_ c: Catalog, hidden: Set<String> = []) -> Derived {
        var r = Derived()
        // catégories masquées : absentes des rangées, de « À la une » et de la recherche
        // (favoris, listes et « Reprendre » ne changent pas)
        let vodVis = hidden.isEmpty ? c.vod : c.vod.filter { !hidden.contains("vod|" + $0.cat) }
        let serVis = hidden.isEmpty ? c.series : c.series.filter { !hidden.contains("series|" + $0.cat) }
        let featV = featured(vodVis), featS = featured(serVis)
        let vodCats = byCategory(vodVis, order: c.vodCats)
        let serCats = byCategory(serVis, order: c.serCats)
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
        r.vodVisible = vodVis
        r.seriesVisible = serVis
        var seenIdx = Set<String>()
        r.index = (vodVis + serVis).filter { seenIdx.insert($0.key).inserted }.map { ($0, Names.searchKey($0.name)) }
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

    /// Change quand l'apparence change (couleur d'accent) : l'interface est redessinée.
    @Published private(set) var appearance = 0
    /// Distribution et réalisation des films (fiches ouvertes ou indexation) : identifiant -> noms.
    private(set) var people: [Int: String] = [:]
    @Published private(set) var indexing = false
    @Published private(set) var indexDone = 0
    private var indexTask: Task<Void, Never>?
    /// Contenu pour lequel créer une nouvelle liste (menu de l'appui long).
    @Published var newListFor: Item?

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
        configureDownloads()
        people = Files.load([Int: String].self, from: Files.people) ?? [:]
        Task {
            // démarrage rapide : le catalogue enregistré s'affiche tout de suite, la mise à jour se fait ensuite
            let c = await Task.detached(priority: .userInitiated) { Files.load(Catalog.self, from: Files.catalog) }.value
            if let c { await apply(c) }
            refreshIfStale()
        }
    }

    private func apply(_ c: Catalog) async {
        let hidden = Store.hiddenCats
        hiddenUsed = hidden
        let d = await Task.detached(priority: .userInitiated) { Derived.make(c, hidden: hidden) }.value
        catalog = c
        derived = d
        updateExtras()
        checkFollows(force: false)
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
            configureDownloads()
            refresh()
            return nil
        } catch {
            return Self.message(error)
        }
    }

    // ---------- reprise ----------
    func progressChanged() { progressTick += 1; updateExtras() }

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

    // ---------- classements TMDB, recommandations ----------
    @Published private(set) var popVod: [Item] = []
    @Published private(set) var popSeries: [Item] = []
    @Published private(set) var recoVod: [Item] = []
    @Published private(set) var recoSeries: [Item] = []
    private var recoTask: Task<Void, Never>?

    /// « Populaires · France » (si une clé TMDB est saisie) et « Recommandé pour vous ».
    func updateExtras() {
        let vod = derived.vodVisible, ser = derived.seriesVisible
        recoTask?.cancel()
        recoTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let recent = Store.recent, favs = Store.favs, ratings = Store.allRatings, ppl = people
            let all = vod + ser
            let r = await Task.detached(priority: .utility) { () -> ([Item], [Item]) in
                let p: (Item) -> String = { $0.people.isEmpty ? (ppl[$0.id] ?? "") : $0.people }
                return (recoList(pool: vod, all: all, recent: recent, favs: favs, ratings: ratings, people: p),
                        recoList(pool: ser, all: all, recent: recent, favs: favs, ratings: ratings, people: p))
            }.value
            recoVod = r.0
            recoSeries = r.1
            if Tmdb.enabled && popVod.isEmpty {
                let pv = await Tmdb.shared.popular("vod"), ps = await Tmdb.shared.popular("series")
                let m = await Task.detached(priority: .utility) { (matchPopular(pv, vod), matchPopular(ps, ser)) }.value
                popVod = Array(m.0.prefix(40))
                popSeries = Array(m.1.prefix(40))
            }
        }
    }

    /// Rangées d'un onglet : Reprendre, favoris, recommandations, classement, puis catégories.
    func rows(for tab: String) -> [Row] {
        _ = progressTick
        let useV = popVod.count >= 6, useS = popSeries.count >= 6
        func top(_ r: Row) -> Row {
            if r.id == "home|vod*" && useV { return Row(id: r.id, title: "Films · Populaires · France", items: popVod) }
            if r.id == "home|series*" && useS { return Row(id: r.id, title: "Séries · Populaires · France", items: popSeries) }
            if r.id == "vod|*vedette" && useV { return Row(id: r.id, title: "Populaires · France", items: popVod) }
            if r.id == "series|*vedette" && useS { return Row(id: r.id, title: "Populaires · France", items: popSeries) }
            return r
        }
        switch tab {
        case "vod":
            var out = [resumeRow("vod"), favoritesRow("vod")].compactMap { $0 }
            let base = derived.vod.map(top)
            out += base.prefix(1)
            if !recoVod.isEmpty { out.append(Row(id: "vod|*reco", title: "Pour vous", items: recoVod)) }
            return out + base.dropFirst()
        case "series":
            var out = [resumeRow("series"), favoritesRow("series")].compactMap { $0 }
            let base = derived.series.map(top)
            out += base.prefix(1)
            if !recoSeries.isEmpty { out.append(Row(id: "series|*reco", title: "Pour vous", items: recoSeries)) }
            return out + base.dropFirst()
        default:
            var out = [resumeRow(nil), favoritesRow(nil)].compactMap { $0 }
            let reco = Array(recoVod.prefix(12)) + Array(recoSeries.prefix(12))
            if !reco.isEmpty { out.append(Row(id: "home|*reco", title: "Recommandé pour vous", items: reco)) }
            return out + derived.home.map(top)
        }
    }

    func hero(for tab: String) -> [Item] {
        switch tab {
        case "vod": return popVod.count >= 6 ? Array(popVod.filter { $0.poster != nil }.prefix(8)) : derived.heroVod
        case "series": return popSeries.count >= 6 ? Array(popSeries.filter { $0.poster != nil }.prefix(8)) : derived.heroSeries
        default:
            if popVod.count >= 6 || popSeries.count >= 6 {
                return Array((popVod.prefix(6) + popSeries.prefix(6)).filter { $0.poster != nil }.shuffled().prefix(8))
            }
            return derived.heroHome
        }
    }

    /// Fin d'un film : quelques titres de la même catégorie, puis d'autres.
    func recommendations(after key: String) -> [Item] {
        guard let done = derived.byKey[key] else { return [] }
        let pool = (done.type == "vod" ? derived.vodVisible : derived.seriesVisible)
            .filter { $0.key != done.key && $0.poster != nil && !Store.recent.contains($0.key) }
        let same = Array(pool.filter { $0.cat == done.cat }.shuffled().prefix(4))
        let keys = Set(same.map(\.key))
        return Array((same + pool.shuffled().prefix(20).filter { !keys.contains($0.key) }).prefix(4))
    }

    /// Lecture d'un film : version choisie (sinon la qualité préférée), reprise si déjà commencé (ou position donnée),
    /// et les autres versions en secours si la lecture échoue.
    func filmRequest(_ item: Item, variant: Variant? = nil, at ms: Int? = nil, ext: String? = nil) -> PlayRequest {
        let v = variant ?? item.variants.first { $0.q == Store.prefQuality } ?? item.variants.first
        let id = v?.id ?? item.id
        let key = "vod:\(id)"
        let pos = Store.pos(key), dur = Store.dur(key)
        let start = ms ?? (pos > 0 && !Store.seen(key) && (dur == 0 || pos < dur * 9 / 10) ? pos : 0)
        var r = PlayRequest(title: item.name, key: key, kind: "vod",
                            urls: playURLs(kind: "vod", id: id, ext: ext ?? v?.ext ?? item.ext, key: key), startMs: start)
        r.alts = item.variants.filter { $0.id != id }.map { o in
            AltVersion(label: o.q == "?" ? "Standard" : o.q) { [weak self] in
                self?.filmRequest(item, variant: o, at: start) ?? PlayRequest(title: item.name, key: key, kind: "vod", urls: [])
            }
        }
        return r
    }

    func setTmdbKey(_ k: String) {
        Store.tmdbKey = k.trimmed
        popVod = []
        popSeries = []
        updateExtras()
    }

    // ---------- séries suivies (Sorties) ----------
    @Published private(set) var follows: [String: Follow] = Store.follows
    @Published private(set) var followBusy = false
    @Published private(set) var followInfo = ""

    /// Nouveaux épisodes pas encore vus, par série.
    var news: [String: [NewEp]] {
        _ = progressTick
        return follows.compactMapValues { f in
            let l = f.fresh.filter { !Store.seen("ep:\($0.id)") }
            return l.isEmpty ? nil : l
        }
    }

    func setFollow(_ series: Item, info: ItemInfo?, on: Bool) {
        var m = follows
        if on {
            m[series.key] = Follow(vid: series.id, known: (info?.episodes ?? []).map { epCode($0.season, $0.num) }, fresh: [])
        } else {
            m[series.key] = nil
        }
        follows = m
        Store.saveFollows(m, changed: [series.key])
    }

    func clearNews() {
        let m = follows.mapValues { Follow(vid: $0.vid, known: $0.known, fresh: []) }
        follows = m
        Store.saveFollows(m, changed: Array(m.keys))
    }

    /// Compare la liste des épisodes de chaque série suivie (au lancement, au plus toutes les 6 h, ou à la demande).
    func checkFollows(force: Bool) {
        guard let a = account, !followBusy else { return }
        if follows.isEmpty { if force { followInfo = "Aucune série suivie." }; return }
        if !force && Date().timeIntervalSince(Store.followCheck) < 6 * 3600 { return }
        followBusy = true
        Task {
            let client = XtreamClient(a)
            for k in Array(follows.keys) {
                guard let cur = follows[k] else { continue }
                let vid = derived.byKey[k]?.id ?? cur.vid
                guard let inf = try? await client.info(type: "series", id: vid) else { continue }
                infoCache[k] = inf
                let upd = updateFollow(cur, vid: vid, eps: inf.episodes) { Store.seen("ep:\($0)") }
                if follows[k] != nil && upd != cur {
                    follows[k] = upd
                    Store.saveFollows(follows, changed: [k])
                }
            }
            Store.followCheck = Date()
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            let n = news.values.reduce(0) { $0 + $1.count }
            followInfo = "Vérifié à \(f.string(from: Date())) · " + (n == 0 ? "aucun nouvel épisode" : n == 1 ? "1 nouvel épisode" : "\(n) nouveaux épisodes")
            followBusy = false
        }
    }

    // ---------- « À la une » : résumé et grande image ----------
    struct HeroInfo: Equatable { var plot = ""; var backdrop: String?; var genre = "" }
    private var heroCache: [String: HeroInfo] = [:]

    func heroInfo(_ item: Item) async -> HeroInfo {
        if let h = heroCache[item.key] { return h }
        var h = HeroInfo()
        if let i = try? await info(for: item) { h.plot = i.plot; h.backdrop = i.backdrop; h.genre = i.genre }
        if Tmdb.enabled, let t = await Tmdb.shared.details(type: item.type, tmdbId: item.tmdb, title: item.name, year: item.year) {
            if !t.overview.isEmpty { h.plot = t.overview }
            if let b = t.backdrop, !b.isEmpty { h.backdrop = b }
        }
        heroCache[item.key] = h
        return h
    }

    // ---------- fiches ----------
    private var infoCache: [String: ItemInfo] = [:]

    func cachedInfo(_ item: Item) -> ItemInfo? { infoCache[item.key] }

    func info(for item: Item) async throws -> ItemInfo {
        if let i = infoCache[item.key] { return i }
        guard let a = account else { throw XtreamError.badCredentials }
        let i = try await XtreamClient(a).info(type: item.type, id: item.id)
        infoCache[item.key] = i
        if item.type == "vod", people[item.id] == nil {
            people[item.id] = [i.cast, i.director].filter { !$0.isEmpty }.joined(separator: ", ")
            if people.count % 20 == 0 { savePeople() }
        }
        return i
    }

    // ---------- distribution des films (recherche par acteur) ----------
    func peopleOf(_ i: Item) -> String { i.people.isEmpty ? (people[i.id] ?? "") : i.people }

    private func savePeople() {
        let snap = people
        Task.detached(priority: .utility) { Files.save(snap, to: Files.people) }
    }

    var filmCount: Int { catalog?.vod.count ?? 0 }
    var indexedCount: Int { people.count }

    /// Indexe la distribution de tous les films (une fiche à la fois, sans gêner la lecture).
    func toggleIndexing() {
        if indexing { indexTask?.cancel(); indexing = false; savePeople(); return }
        guard let a = account, let films = catalog?.vod else { return }
        indexing = true
        indexTask = Task {
            let client = XtreamClient(a)
            var n = 0
            for f in films where people[f.id] == nil {
                if Task.isCancelled { break }
                if let i = try? await client.info(type: "vod", id: f.id) {
                    people[f.id] = [i.cast, i.director].filter { !$0.isEmpty }.joined(separator: ", ")
                } else {
                    people[f.id] = ""
                }
                n += 1
                if n % 25 == 0 { indexDone = people.count }
                if n % 200 == 0 { savePeople() }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            savePeople()
            indexDone = people.count
            indexing = false
        }
    }

    // ---------- recherche ----------
    /// Films et séries par titre, puis par acteur ou réalisateur ; sans tenir compte des accents ; calculée à part.
    func search(_ text: String) async -> [Row] {
        let q = Names.searchKey(text).trimmed
        guard q.count >= 2 else { return [] }
        let index = derived.index
        let ppl = people
        return await Task.detached(priority: .userInitiated) { () -> [Row] in
            let byTitle = index.filter { $0.1.contains(q) }
                .sorted { ($0.1.hasPrefix(q) ? 0 : 1) < ($1.1.hasPrefix(q) ? 0 : 1) }
                .map(\.0)
            let keys = Set(byTitle.map(\.key))
            let byPerson = index.filter { e in
                guard !keys.contains(e.0.key) else { return false }
                let p = e.0.people.isEmpty ? (ppl[e.0.id] ?? "") : e.0.people
                return !p.isEmpty && Names.searchKey(p).contains(q)
            }.map(\.0)
            var rows: [Row] = []
            let films = byTitle.filter { $0.type == "vod" }, series = byTitle.filter { $0.type == "series" }
            if !films.isEmpty { rows.append(Row(id: "search|vod", title: "Films", items: films)) }
            if !series.isEmpty { rows.append(Row(id: "search|series", title: "Séries", items: series)) }
            if !byPerson.isEmpty { rows.append(Row(id: "search|people", title: "Avec « \(text.trimmed) »", items: byPerson)) }
            return rows
        }.value
    }

    /// Autres titres d'une personne (nom exact dans la distribution ou la réalisation).
    func titles(with person: String) -> [Item] {
        let nm = person.trimmed.lowercased()
        return derived.index.map(\.0).filter { i in
            peopleOf(i).split(whereSeparator: { ",/;".contains($0) }).contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == nm }
        }
    }

    // ---------- listes, notes, « Reprendre » ----------
    /// Rangées de « Mes listes » : favoris, puis chaque liste.
    func listRows() -> [Row] {
        _ = progressTick
        var rows: [Row] = []
        if let f = favoritesRow(nil) { rows.append(f) }
        let m = Store.lists
        for name in Store.listNames {
            let items = (m[name] ?? []).compactMap { derived.byKey[$0] }
            rows.append(Row(id: "list|" + name, title: name, items: items))
        }
        return rows
    }

    func toggleInList(_ name: String, _ item: Item) { Store.toggleInList(name, item.key); progressChanged() }
    func toggleFav(_ item: Item) { Store.toggleFav(item.key); progressChanged() }
    func createList(_ name: String, with item: Item?) {
        let n = name.trimmed
        guard !n.isEmpty else { return }
        Store.createList(n)
        if let i = item { Store.toggleInList(n, i.key) }
        progressChanged()
    }
    func deleteList(_ name: String) { Store.deleteList(name); progressChanged() }

    /// Retire un titre de la rangée « Reprendre » (il reste dans le catalogue).
    func removeFromResume(_ item: Item) {
        for k in Store.recent where k == item.key || derived.byKey[k]?.key == item.key { Store.removeRecent(k) }
        progressChanged()
    }

    func setRating(_ item: Item, _ v: Int) {
        Store.setRating(item.key, Store.rating(item.key) == v ? 0 : v)
        progressChanged()
    }

    // ---------- catégories masquées, apparence ----------
    func setHidden(_ all: Set<String>, save: Bool = true) {
        if save { Store.hiddenCats = all }
        hiddenTask?.cancel()
        // plusieurs changements de suite : on recalcule une seule fois
        hiddenTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            if let c = catalog { await apply(c) }
            await applyLive(live, liveCatsOrder)
        }
    }
    private var hiddenTask: Task<Void, Never>?

    func setAccent(_ i: Int) { Store.accent = i; appearance += 1; accentUsed = Self.accentSig }
    func setCustomAccent(hue: Double, sat: Double) {
        Store.customHue = hue
        Store.customSat = sat
        Store.accent = Accent.customIndex
        appearance += 1
        accentUsed = Self.accentSig
    }

    // ---------- profils ----------
    /// « Qui regarde ? » au lancement dès qu'il y a plusieurs profils.
    @Published var pickingProfile = Profiles.all.count > 1
    @Published private(set) var profile = Profiles.current
    @Published private(set) var profiles = Profiles.all

    func selectProfile(_ id: String) {
        Profiles.select(id)
        profile = Profiles.current
        pickingProfile = false
        // tout ce qui dépend du profil est relu : séries suivies, couleur, catégories masquées, rangées
        follows = Store.follows
        accentUsed = Self.accentSig
        appearance += 1
        if Store.hiddenCats != hiddenUsed { setHidden(Store.hiddenCats, save: false) }
        progressChanged()
    }

    @discardableResult
    func addProfile(name: String, color: Int) -> Profile? {
        let p = Profiles.add(name: name, color: color)
        profiles = Profiles.all
        return p
    }

    func updateProfile(_ p: Profile) {
        Profiles.update(p)
        profiles = Profiles.all
        if p.id == profile.id { profile = p }
    }

    func deleteProfile(_ id: String) {
        let wasCurrent = id == profile.id
        Profiles.delete(id)
        profiles = Profiles.all
        if wasCurrent { selectProfile(Profiles.mainId) }
    }

    // ---------- synchronisation Wi-Fi (avec la TV Android et les autres appareils Apple) ----------
    private var hiddenUsed: Set<String> = []
    private var accentUsed = AppModel.accentSig
    private static var accentSig: String { "\(Store.accent)|\(Store.customHue)|\(Store.customSat)" }

    /// Active tant que l'appli est au premier plan (et si elle n'est pas désactivée dans les réglages).
    func updateSync(active: Bool) {
        let s = LanSync.shared
        s.onApplied = { [weak self] in self?.syncApplied() }
        if active, Prefs.syncOn, phase == .ready, let a = account { s.start(account: a) } else { s.stop() }
    }

    /// Données reçues d'un autre appareil : l'appli relit tout ce qui est partagé.
    func syncApplied() {
        follows = Store.follows
        if Self.accentSig != accentUsed { accentUsed = Self.accentSig; appearance += 1 }
        if Store.hiddenCats != hiddenUsed { setHidden(Store.hiddenCats, save: false) }
        progressChanged()
    }

    // ---------- épisodes ----------
    /// Lecture d'un épisode, avec l'épisode suivant (pour le bouton « Épisode suivant »).
    func episodeRequest(series: Item, info: ItemInfo, episode e: Episode, fromStart: Bool = false) -> PlayRequest {
        let pos = fromStart ? 0 : Store.pos(e.key)
        var r = PlayRequest(title: "\(series.name) · S\(e.season) É\(e.num) \(e.title)", key: e.key, kind: "series",
                            urls: playURLs(kind: "series", id: e.id, ext: e.ext, key: e.key), startMs: pos > 10_000 ? pos : 0)
        r.seriesId = series.id
        // dernier épisode lancé : la série est suivie d'office (les prochains épisodes arriveront dans Sorties)
        if e == info.episodes.last, follows[series.key] == nil { setFollow(series, info: info, on: true) }
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

    // ---------- téléchargements (iPhone) ----------
    private func configureDownloads() {
        #if os(iOS)
        DownloadManager.shared.urlsFor = { [weak self] e in
            self?.fileURLs(kind: e.kind, id: e.id, ext: e.ext) ?? []
        }
        DownloadManager.shared.resumeAfterStreaming()
        #endif
    }

    /// Adresses de lecture : le fichier téléchargé d'abord (lecture sans connexion), puis le serveur.
    func playURLs(kind: String, id: Int, ext: String, key: String) -> [URL] {
        var l: [URL] = []
        #if os(iOS)
        if let u = DownloadManager.shared.localURL(key) { l.append(u) }
        #endif
        return l + fileURLs(kind: kind, id: id, ext: ext)
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

    private(set) var liveCatsOrder: [String] = []

    private func applyLive(_ items: [Item], _ cats: [String]) async {
        liveCatsOrder = cats
        let hidden = Store.hiddenCats
        let rows = await Task.detached { () -> [Row] in
            Derived.byCategory(items.filter { !hidden.contains("live|" + $0.cat) }, order: cats)
                .map { Row(id: "live|" + $0.0, title: $0.0, items: $0.1) }
        }.value
        live = items
        liveRows = rows
        let visible = items.filter { !hidden.contains("live|" + $0.cat) }
        liveGenres = await Task.detached { () -> [Row] in
            var g: [String: [Item]] = [:]
            var seen = Set<String>()
            for c in visible where seen.insert(c.key).inserted {
                if let n = Names.liveGenre(c) { g[n, default: []].append(c) }
            }
            return Names.genres.compactMap { n in g[n].map { Row(id: "genre|" + n, title: n, items: $0) } }
        }.value
        if Prefs.epgAuto && epg.isEmpty { loadEpg() }
    }

    // ---------- Direct : genres, favoris, qualité par chaîne ----------
    /// Chaînes par genre (déduit du nom et de la catégorie), dans l'ordre d'Android.
    @Published private(set) var liveGenres: [Row] = []

    var visibleLive: [Item] {
        let hidden = Store.hiddenCats
        return live.filter { !hidden.contains("live|" + $0.cat) }
    }

    func favLiveRow() -> Row? {
        _ = progressTick
        let byKey = Dictionary(live.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let items = Store.favs.compactMap { byKey[$0] }
        return items.isEmpty ? nil : Row(id: "live|*favs", title: "Favoris", items: items)
    }

    /// Version d'une chaîne à lire : celle choisie pour cette chaîne, sinon la qualité préférée, sinon la meilleure.
    func liveVariant(_ c: Item) -> Variant? {
        let q = Store.liveQuality(c.key)
        return c.variants.first { $0.q == q } ?? c.variants.first { $0.q.hasPrefix(Store.prefQuality) && !Store.prefQuality.isEmpty }
            ?? c.variants.first
    }

    func searchLive(_ text: String) -> [Item] {
        let q = Names.searchKey(text).trimmed
        guard q.count >= 2 else { return [] }
        return visibleLive.filter { Names.searchKey($0.name).contains(q) }
            .sorted { (Names.searchKey($0.name).hasPrefix(q) ? 0 : 1) < (Names.searchKey($1.name).hasPrefix(q) ? 0 : 1) }
    }

    func liveRequest(_ c: Item, list: [Item], listName: String) -> PlayRequest {
        let v = liveVariant(c)
        var r = PlayRequest(title: c.name, key: c.key, kind: "live", urls: liveURLs(id: v?.id ?? c.id))
        r.channel = c
        r.channels = list
        r.listName = listName
        r.quality = v?.q
        return r
    }

    // ---------- guide des programmes (XMLTV) ----------
    @Published private(set) var epg: [String: [Prog]] = [:]
    @Published private(set) var epgStatus = ""

    func loadEpg() {
        guard let a = account, !epgStatus.hasPrefix("Chargement") else { return }
        let custom = Prefs.epgUrl.trimmed
        let urlString = custom.isEmpty ? (try? XtreamClient(a).apiURL().absoluteString.replacingOccurrences(of: "/player_api.php", with: "/xmltv.php")) ?? "" : custom
        guard let url = URL(string: urlString) else { epgStatus = "Adresse du guide invalide."; return }
        epgStatus = "Chargement du guide… (peut prendre une minute)"
        Task {
            do {
                let c = URLSessionConfiguration.default
                c.timeoutIntervalForRequest = 60
                c.timeoutIntervalForResource = 300
                let (file, resp) = try await URLSession(configuration: c).download(from: url)
                if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw XtreamError.http(h.statusCode) }
                let m = await Task.detached(priority: .utility) { () -> [String: [Prog]] in
                    defer { try? FileManager.default.removeItem(at: file) }
                    return XMLTVParser.parse(contentsOf: file)
                }.value
                epg = m
                let f = DateFormatter(); f.dateFormat = "HH:mm"
                epgStatus = m.isEmpty ? "Guide vide ou illisible." : "\(m.count) chaînes · chargé à \(f.string(from: Date()))"
            } catch {
                epgStatus = "Échec du chargement : \(Self.message(error))"
            }
        }
    }

    /// « Maintenant : titre · 20:45–22:30 » pour une chaîne.
    func epgLine(_ c: Item) -> String? {
        guard !c.epg.isEmpty else { return nil }
        let (cur, next) = XMLTVParser.nowNext(epg[c.epg.lowercased()])
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        if let p = cur { return "\(p.title) · \(f.string(from: p.start))–\(f.string(from: p.stop))" }
        if let n = next { return "Ensuite : \(n.title) à \(f.string(from: n.start))" }
        return nil
    }

    func epgNowNext(_ c: Item) -> (Prog?, Prog?) { XMLTVParser.nowNext(epg[c.epg.lowercased()]) }

    func recentLiveRow() -> Row? {
        _ = progressTick
        let byKey = Dictionary(live.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let items = Store.recentLive.compactMap { byKey[$0] }
        return items.isEmpty ? nil : Row(id: "live|*recent", title: "Regardées récemment", items: items)
    }

    func logout() {
        LanSync.shared.stop()
        Keychain.delete()
        Profiles.removeAll()
        profiles = Profiles.all
        profile = Profiles.current
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
