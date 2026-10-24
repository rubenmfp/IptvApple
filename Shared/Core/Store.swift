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
            || ["recent", "rlive", "stamps", "favs"].contains(k) {
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
