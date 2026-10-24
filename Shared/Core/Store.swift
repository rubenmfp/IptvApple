import Foundation

/// Données de visionnage gardées sur l'appareil : reprise de lecture, contenus vus, lectures récentes, extensions qui marchent.
/// Les clés reprennent celles de l'appli Android (« vod:123 », « series:45 », « ep:678 », « live:9 ») pour la synchronisation.
/// Chaque modification est datée (« stamps ») : en cas de conflit entre appareils, la plus récente l'emportera (étape 5).
enum Store {
    private static let d = UserDefaults.standard

    private static func stamp(_ syncKey: String) {
        var s = d.dictionary(forKey: "stamps") as? [String: Int64] ?? [:]
        s[syncKey] = Int64(Date().timeIntervalSince1970 * 1000)
        d.set(s, forKey: "stamps")
    }

    // ---------- reprise de lecture ----------
    static func pos(_ k: String) -> Int { d.integer(forKey: "p_" + k) }
    static func dur(_ k: String) -> Int { d.integer(forKey: "d_" + k) }

    /// Enregistre la position (en millisecondes). Une lecture terminée (au-delà de 95 %) repart du début.
    static func setProgress(_ k: String, pos: Int, dur: Int) {
        guard dur > 0 else { return }
        let p = pos > dur * 95 / 100 ? 0 : max(0, pos)
        if p == self.pos(k) && dur == self.dur(k) { return }
        d.set(p, forKey: "p_" + k)
        d.set(dur, forKey: "d_" + k)
        stamp("pos|" + k)
        if pos >= dur * 90 / 100 { setSeen(k) }
    }

    static func clearProgress(_ k: String) {
        d.removeObject(forKey: "p_" + k)
        stamp("pos|" + k)
    }

    // ---------- vus (90 %) ----------
    static func seen(_ k: String) -> Bool { d.bool(forKey: "s_" + k) }
    static func setSeen(_ k: String) {
        if seen(k) { return }
        d.set(true, forKey: "s_" + k)
        stamp("seen|" + k)
    }

    // ---------- favoris ----------
    static var favs: [String] { d.stringArray(forKey: "favs") ?? [] }
    static func isFav(_ k: String) -> Bool { favs.contains(k) }
    static func toggleFav(_ k: String) {
        if isFav(k) { d.set(favs.filter { $0 != k }, forKey: "favs") } else { d.set([k] + favs, forKey: "favs") }
        stamp("fav|" + k)
    }

    // ---------- listes personnelles : nom -> clés (ordre conservé) ----------
    static var listNames: [String] { (d.array(forKey: "listOrder") as? [String]) ?? Array(lists.keys).sorted() }
    static var lists: [String: [String]] {
        guard let s = d.string(forKey: "lists"), let data = s.data(using: .utf8),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else { return [:] }
        return m
    }
    static func saveLists(_ m: [String: [String]], order: [String]) {
        if let data = try? JSONSerialization.data(withJSONObject: m), let s = String(data: data, encoding: .utf8) { d.set(s, forKey: "lists") }
        d.set(order.filter { m[$0] != nil }, forKey: "listOrder")
        stamp("lists")
    }
    static func inList(_ name: String, _ k: String) -> Bool { lists[name]?.contains(k) ?? false }
    static func toggleInList(_ name: String, _ k: String) {
        var m = lists
        var l = m[name] ?? []
        if l.contains(k) { l.removeAll { $0 == k } } else { l.insert(k, at: 0) }
        m[name] = l
        saveLists(m, order: listNames.contains(name) ? listNames : listNames + [name])
    }
    static func createList(_ name: String) {
        var m = lists
        guard !name.trimmed.isEmpty, m[name] == nil else { return }
        m[name] = []
        saveLists(m, order: listNames + [name])
    }
    static func deleteList(_ name: String) {
        var m = lists
        m[name] = nil
        saveLists(m, order: listNames.filter { $0 != name })
    }

    // ---------- notes : -1 je n'aime pas, 1 j'aime, 2 j'adore ----------
    static func rating(_ k: String) -> Int { d.integer(forKey: "r_" + k) }
    static func setRating(_ k: String, _ v: Int) {
        if v == 0 { d.removeObject(forKey: "r_" + k) } else { d.set(v, forKey: "r_" + k) }
        stamp("rate|" + k)
    }
    static var allRatings: [String: Int] {
        var m: [String: Int] = [:]
        for (k, v) in d.dictionaryRepresentation() where k.hasPrefix("r_") { m[String(k.dropFirst(2))] = v as? Int ?? 0 }
        return m
    }

    // ---------- qualité préférée (la dernière choisie, proposée d'office) ----------
    static var prefQuality: String {
        get { d.string(forKey: "prefq") ?? "" }
        set { if newValue != prefQuality { d.set(newValue, forKey: "prefq"); stamp("prefq") } }
    }

    // ---------- catégories masquées : « vod|nom », « series|nom », « live|nom » ----------
    static var hiddenCats: Set<String> {
        get { Set(d.stringArray(forKey: "hcats") ?? []) }
        set { d.set(Array(newValue).sorted(), forKey: "hcats"); stamp("hcats") }
    }

    // ---------- couleur d'accent : indice dans la palette, ou la couleur personnalisée (teinte, saturation) ----------
    static var accent: Int {
        get { d.integer(forKey: "accent") }
        set { d.set(newValue, forKey: "accent"); stamp("accent") }
    }
    static var customHue: Double {
        get { d.object(forKey: "chue") as? Double ?? 200 }
        set { d.set(newValue, forKey: "chue"); stamp("chue") }
    }
    static var customSat: Double {
        get { d.object(forKey: "csat") as? Double ?? 0.8 }
        set { d.set(newValue, forKey: "csat"); stamp("csat") }
    }

    // ---------- qualité choisie pour une chaîne ----------
    static func liveQuality(_ k: String) -> String { d.string(forKey: "lq_" + k) ?? "" }
    static func setLiveQuality(_ k: String, _ q: String) {
        if q == liveQuality(k) { return }
        d.set(q, forKey: "lq_" + k)
        stamp("lq|" + k)
    }

    // ---------- clé TMDB (synchronisée) ----------
    static var tmdbKey: String {
        get { d.string(forKey: "tmdb") ?? "" }
        set { if newValue != tmdbKey { d.set(newValue, forKey: "tmdb"); stamp("tmdb") } }
    }

    // ---------- séries suivies (cloche) : clé de la série -> suivi ----------
    static var follows: [String: Follow] {
        guard let data = d.data(forKey: "follows"), let m = try? JSONDecoder().decode([String: Follow].self, from: data) else { return [:] }
        return m
    }
    static func saveFollows(_ m: [String: Follow], changed: [String]) {
        if let data = try? JSONEncoder().encode(m) { d.set(data, forKey: "follows") }
        for k in changed { stamp("fw|" + k) }
    }
    static var followCheck: Date {
        get { d.object(forKey: "fchk") as? Date ?? .distantPast }
        set { d.set(newValue, forKey: "fchk") }
    }

    // ---------- dernier épisode lancé d'une série ----------
    static func lastEp(_ seriesId: Int) -> Int { d.integer(forKey: "last_\(seriesId)") }
    static func setLastEp(_ seriesId: Int, _ epId: Int) {
        if lastEp(seriesId) == epId { return }
        d.set(epId, forKey: "last_\(seriesId)")
        stamp("last|\(seriesId)")
    }

    // ---------- lectures récentes (rangée « Reprendre ») ----------
    static var recent: [String] { d.stringArray(forKey: "recent") ?? [] }
    static func addRecent(_ k: String) {
        let l = [k] + recent.filter { $0 != k }
        d.set(Array(l.prefix(30)), forKey: "recent")
        stamp("recent")
    }
    static func removeRecent(_ k: String) {
        d.set(recent.filter { $0 != k }, forKey: "recent")
        stamp("recent")
    }

    static var recentLive: [String] { d.stringArray(forKey: "rlive") ?? [] }
    static func addRecentLive(_ k: String) {
        let l = [k] + recentLive.filter { $0 != k }
        d.set(Array(l.prefix(20)), forKey: "rlive")
        stamp("rlive")
    }

    // ---------- extension qui a marché (le serveur annonce souvent la mauvaise) ----------
    static func goodExt(_ kind: String) -> String { d.string(forKey: "ext_" + kind) ?? "" }
    static func setGoodExt(_ kind: String, _ e: String) { d.set(e, forKey: "ext_" + kind) }

    /// Efface tout (déconnexion).
    static func reset() {
        for k in d.dictionaryRepresentation().keys where k.hasPrefix("p_") || k.hasPrefix("d_") || k.hasPrefix("s_") || k.hasPrefix("ext_") || k.hasPrefix("last_")
            || k.hasPrefix("r_") || k.hasPrefix("lq_") || ["recent", "rlive", "stamps", "favs", "lists", "listOrder", "hcats", "prefq", "follows", "fchk"].contains(k) {
            d.removeObject(forKey: k)
        }
    }
}

/// Mise en forme d'une durée en millisecondes : « 1:02:03 » ou « 12:34 ».
func fmtTime(_ ms: Int) -> String {
    let s = max(0, ms / 1000)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}
