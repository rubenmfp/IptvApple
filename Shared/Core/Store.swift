import Foundation
import CryptoKit
import Security

/// Données de visionnage gardées sur l'appareil : reprise de lecture, contenus vus, lectures récentes, extensions qui marchent.
/// Les clés reprennent celles de l'appli Android (« vod:123 », « series:45 », « ep:678 », « live:9 ») pour la synchronisation.
/// Chaque modification est datée (« stamps ») : entre appareils, la plus récente l'emporte (synchronisation Wi-Fi).
enum Store {
    /// Données du profil en cours (le profil principal garde les préférences d'origine : rien ne change pour lui).
    private static var d: UserDefaults { forced ?? Profiles.currentDefaults }
    static var defaults: UserDefaults { d }
    /// La synchronisation Wi-Fi travaille toujours sur le profil principal (l'appli Android n'a pas de profils).
    fileprivate static var forced: UserDefaults?
    /// Prévenu à chaque modification d'une donnée partagée : la synchronisation l'enverra aux autres appareils.
    static let changed = Notification.Name("StoreChanged")

    fileprivate static func stamp(_ syncKey: String) {
        var s = stamps
        s[syncKey] = Int64(Date().timeIntervalSince1970 * 1000)
        stamps = s
        NotificationCenter.default.post(name: changed, object: nil)
    }
    /// Date d'une donnée commune à tous les profils (liste des profils) : rangée avec celles du profil principal.
    fileprivate static func stampMain(_ syncKey: String) {
        let saved = forced
        forced = .standard
        defer { forced = saved }
        stamp(syncKey)
    }
    fileprivate static func mainStamps() -> [String: Int64] {
        let saved = forced
        forced = .standard
        defer { forced = saved }
        return stamps
    }
    fileprivate static func setMainStamp(_ k: String, _ t: Int64) {
        let saved = forced
        forced = .standard
        defer { forced = saved }
        var st = stamps
        st[k] = t
        stamps = st
    }
    /// Clé de donnée partagée -> date de sa dernière modification sur cet appareil (millisecondes).
    fileprivate static var stamps: [String: Int64] {
        get { (d.dictionary(forKey: "stamps") ?? [:]).compactMapValues { ($0 as? NSNumber)?.int64Value } }
        set { d.set(newValue.mapValues { NSNumber(value: $0) }, forKey: "stamps") }
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
        let o = order.filter { m[$0] != nil } + m.keys.filter { !order.contains($0) }.sorted()
        d.set(listsJSON(m, order: o), forKey: "lists")
        d.set(o, forKey: "listOrder")
        stamp("lists")
    }
    /// JSON des listes dans leur ordre (comme sur Android : {"nom":["vod:1",…],…}).
    fileprivate static func listsJSON(_ m: [String: [String]], order: [String]) -> String {
        "{" + order.compactMap { n in m[n].map { jsonText(n) + ":" + jsonText($0) } }.joined(separator: ",") + "}"
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
        get { let v = d.integer(forKey: "accent"); return v == 7 ? 99 : v }      // 7 = ancienne valeur de « Personnalisée »
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

    // ---------- clé TMDB (synchronisée), gardée dans le trousseau ----------
    static var tmdbKey: String {
        get {
            if let old = d.string(forKey: "tmdb") {          // versions 0.7 et 0.8 : la clé était dans les préférences
                Secret.set("tmdb", old)
                d.removeObject(forKey: "tmdb")
            }
            return Secret.get("tmdb")
        }
        set { if newValue != tmdbKey { Secret.set("tmdb", newValue); stamp("tmdb") } }
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

// ======================= Profils =======================

/// Un profil : chacun a ses favoris, listes, reprises, notes, séries suivies, catégories masquées, couleur et réglages du lecteur.
struct Profile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var color: Int
}

enum Profiles {
    static let mainId = "main"
    static let maxCount = 5
    private static let std = UserDefaults.standard
    private static var suites: [String: UserDefaults] = [:]
    private static let lock = NSLock()

    static var all: [Profile] {
        get {
            guard let data = std.data(forKey: "profiles"), let l = try? JSONDecoder().decode([Profile].self, from: data), !l.isEmpty
            else { return [Profile(id: mainId, name: "Moi", color: 0)] }
            return l
        }
        set { if let data = try? JSONEncoder().encode(newValue) { std.set(data, forKey: "profiles") } }
    }

    /// Profil en cours (gardé en mémoire : il est consulté à chaque lecture d'une donnée).
    private(set) static var currentId: String = {
        let id = UserDefaults.standard.string(forKey: "profile") ?? mainId
        return id
    }()
    static var current: Profile { all.first { $0.id == currentId } ?? all[0] }

    static func select(_ id: String) {
        currentId = all.contains { $0.id == id } ? id : mainId
        std.set(currentId, forKey: "profile")
    }

    static var currentDefaults: UserDefaults { defaults(for: currentId) }

    static func defaults(for id: String) -> UserDefaults {
        if id == mainId { return std }
        lock.lock(); defer { lock.unlock() }
        if let d = suites[id] { return d }
        let d = UserDefaults(suiteName: "iptvapple.profile." + id) ?? std
        suites[id] = d
        return d
    }

    @discardableResult
    static func add(name: String, color: Int) -> Profile? {
        var l = all
        guard l.count < maxCount else { return nil }
        let p = Profile(id: String(UUID().uuidString.prefix(8)).lowercased(), name: name.trimmed.isEmpty ? "Profil \(l.count + 1)" : name.trimmed, color: color)
        l.append(p)
        all = l
        Store.stampMain("prof|" + p.id)
        return p
    }

    static func update(_ p: Profile) {
        var l = all
        if let i = l.firstIndex(where: { $0.id == p.id }) { l[i] = p } else { return }
        all = l
        Store.stampMain("prof|" + p.id)
    }

    /// Supprime un profil et ses données (le profil principal ne peut pas l'être). La suppression est datée :
    /// elle est transmise aux autres appareils.
    static func delete(_ id: String) {
        guard id != mainId else { return }
        remove(id)
        Store.stampMain("prof|" + id)
    }

    /// Suppression locale, sans nouvelle date (déconnexion, suppression reçue d'un autre appareil).
    fileprivate static func remove(_ id: String) {
        guard id != mainId else { return }
        all = all.filter { $0.id != id }
        UserDefaults.standard.removePersistentDomain(forName: "iptvapple.profile." + id)
        lock.lock(); suites[id] = nil; lock.unlock()
        if currentId == id { select(mainId) }
    }

    /// Déconnexion : seul le profil principal reste.
    static func removeAll() {
        for p in all where p.id != mainId { remove(p.id) }
        std.removeObject(forKey: "profiles")
        select(mainId)
    }

    // ---------- synchronisation de la liste des profils ----------

    /// Fiche d'un profil échangée entre appareils : {"name":"…","color":0,"order":0}.
    static func entryText(_ p: Profile, order: Int) -> String {
        "{\"name\":" + jsonText(p.name) + ",\"color\":\(p.color),\"order\":\(order)}"
    }

    static func parseEntry(id: String, _ s: String) -> Profile? {
        guard let d = s.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        let name = (o["name"] as? String ?? "").trimmed
        return Profile(id: id, name: name.isEmpty ? "Profil" : name, color: (o["color"] as? NSNumber)?.intValue ?? 0)
    }

    fileprivate static func upsert(_ p: Profile) {
        var l = all
        if let i = l.firstIndex(where: { $0.id == p.id }) { l[i] = p } else { l.append(p) }
        all = l
    }
}

// ======================= Synchronisation entre appareils (format de l'appli Android) =======================

/// Empreinte du compte (comme sur Android) : deux appareils ne se synchronisent que s'ils utilisent le même compte Xtream.
/// 12 premiers octets du SHA-256 de « serveur en minuscules sans / final|utilisateur », en hexadécimal.
func syncAccount(host: String, user: String) -> String {
    var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
    while h.hasSuffix("/") { h.removeLast() }
    let s = h.lowercased() + "|" + user.trimmingCharacters(in: .whitespacesAndNewlines)
    return SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
}

/// Une donnée partagée : clé, date de modification, valeur (nil = supprimée).
struct SyncRec: Equatable {
    var k: String
    var t: Int64
    var v: String?
}

/// Texte JSON d'une valeur simple (chaîne, tableau…), sans retour à la ligne.
func jsonText(_ v: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [v]), let s = String(data: data, encoding: .utf8) else { return "null" }
    return String(s.dropFirst().dropLast())
}

extension Store {
    static let syncFixed = ["accent", "chue", "csat", "tmdb", "recent", "rlive", "prefq", "lists", "hcats"]
    private static let syncPrefixes = ["fav|", "rate|", "pos|", "seen|", "last|", "lq|", "fw|"]
    static func syncable(_ k: String) -> Bool { syncFixed.contains(k) || syncPrefixes.contains { k.hasPrefix($0) } }

    /// Suivi d'une série au format Android : {"v":…,"k":[…],"n":[{"i":…,"s":…,"e":…,"t":…}]}.
    static func followText(_ f: Follow) -> String {
        let n = f.fresh.map { "{\"i\":\($0.id),\"s\":\($0.season),\"e\":\($0.num),\"t\":" + jsonText($0.title) + "}" }
        return "{\"v\":\(f.vid),\"k\":" + jsonText(f.known.sorted()) + ",\"n\":[" + n.joined(separator: ",") + "]}"
    }
    static func parseFollow(_ s: String) -> Follow? {
        guard let data = s.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let fresh = (o["n"] as? [[String: Any]] ?? []).map {
            NewEp(id: ($0["i"] as? NSNumber)?.intValue ?? 0, season: ($0["s"] as? NSNumber)?.intValue ?? 0,
                  num: ($0["e"] as? NSNumber)?.intValue ?? 0, title: $0["t"] as? String ?? "")
        }
        return Follow(vid: (o["v"] as? NSNumber)?.intValue ?? 0, known: (o["k"] as? [String] ?? []).sorted(), fresh: fresh)
    }

    private static func has(_ key: String) -> Bool { d.object(forKey: key) != nil }

    /// Valeur actuelle d'une donnée partagée, sous forme de texte ; nil = absente.
    static func syncValue(_ k: String, favs: Set<String>, fw: [String: Follow]) -> String? {
        let r = k.firstIndex(of: "|").map { String(k[k.index(after: $0)...]) } ?? ""
        func nonEmpty(_ s: String?) -> String? { (s ?? "").isEmpty ? nil : s }
        switch k {
        case "accent": return has("accent") ? String(accent) : nil
        case "chue": return has("chue") ? String(Float(customHue)) : nil
        case "csat": return has("csat") ? String(Float(customSat)) : nil
        case "tmdb": return nonEmpty(tmdbKey)
        case "prefq": return nonEmpty(d.string(forKey: k))
        case "recent", "rlive": return nonEmpty((d.stringArray(forKey: k) ?? []).joined(separator: ","))
        case "lists": return has("lists") ? listsJSON(lists, order: listNames) : nil
        case "hcats": let h = hiddenCats; return h.isEmpty ? nil : jsonText(h.sorted())
        default: break
        }
        if k.hasPrefix("fav|") { return favs.contains(r) ? "1" : nil }
        if k.hasPrefix("rate|") { return has("r_" + r) ? String(d.integer(forKey: "r_" + r)) : nil }
        if k.hasPrefix("pos|") { return has("p_" + r) || has("d_" + r) ? "\(pos(r));\(dur(r))" : nil }
        if k.hasPrefix("seen|") { return seen(r) ? "1" : nil }
        if k.hasPrefix("last|") { return has("last_" + r) ? String(d.integer(forKey: "last_" + r)) : nil }
        if k.hasPrefix("lq|") { return nonEmpty(d.string(forKey: "lq_" + r)) }
        if k.hasPrefix("fw|") { return fw[r].map(followText) }
        return nil
    }

    /// Toutes les données partagées de cet appareil, avec leur date (1 = antérieure à la synchronisation).
    /// Toutes les données partagées : celles du profil principal (clés d'origine, comprises par IptvTV 0.14),
    /// la liste des profils (« prof|id ») et les données des autres profils (clés préfixées « @id: »).
    static func syncRecords() -> [SyncRec] {
        let saved = forced
        defer { forced = saved }
        forced = .standard
        var out = profileRecords(global: true)
        let st = mainStamps()
        let list = Profiles.all
        var ids = Set(list.map(\.id))
        for k in st.keys where k.hasPrefix("prof|") { ids.insert(String(k.dropFirst(5))) }
        for id in ids.sorted() {
            let v = list.firstIndex { $0.id == id }.map { Profiles.entryText(list[$0], order: $0) }
            let t = st["prof|" + id] ?? (v != nil ? 1 : 0)
            if t > 0 || v != nil { out.append(SyncRec(k: "prof|" + id, t: t, v: v)) }
        }
        for p in list where p.id != Profiles.mainId {
            forced = Profiles.defaults(for: p.id)
            out += profileRecords(global: false).map { SyncRec(k: "@\(p.id):" + $0.k, t: $0.t, v: $0.v) }
        }
        return out
    }

    /// Données du profil désigné par `forced`. `global` : y compris la clé TMDB (commune, rangée avec le profil principal).
    private static func profileRecords(global: Bool) -> [SyncRec] {
        let fav = Set(favs), fw = follows, st = stamps
        var keys = Set(st.keys.filter(syncable))
        keys.formUnion(syncFixed)
        for f in fav { keys.insert("fav|" + f) }
        for f in fw.keys { keys.insert("fw|" + f) }
        for k in d.dictionaryRepresentation().keys {
            if k.hasPrefix("r_") { keys.insert("rate|" + k.dropFirst(2)) }
            else if k.hasPrefix("p_") { keys.insert("pos|" + k.dropFirst(2)) }
            else if k.hasPrefix("s_") { keys.insert("seen|" + k.dropFirst(2)) }
            else if k.hasPrefix("last_") { keys.insert("last|" + k.dropFirst(5)) }
            else if k.hasPrefix("lq_") { keys.insert("lq|" + k.dropFirst(3)) }
        }
        if !global { keys.remove("tmdb") }
        return keys.sorted().compactMap { k in
            let v = syncValue(k, favs: fav, fw: fw)
            let t = st[k] ?? (v != nil ? 1 : 0)
            return t == 0 && v == nil ? nil : SyncRec(k: k, t: t, v: v)
        }
    }

    /// Applique les données d'un autre appareil : pour chaque donnée, la modification la plus récente l'emporte.
    /// À date égale (données d'avant la synchronisation), une donnée absente ici est ajoutée. Renvoie le nombre de changements.
    @discardableResult
    static func applySync(_ recs: [SyncRec]) -> Int {
        let saved = forced
        defer { forced = saved }
        var n = 0
        // 1. liste des profils (ajouts, noms, couleurs, suppressions), chaque profil pour lui-même
        let st = mainStamps()
        for r in recs where r.k.hasPrefix("prof|") {
            let id = String(r.k.dropFirst(5))
            guard !id.isEmpty else { continue }
            let list = Profiles.all
            let cur = list.firstIndex { $0.id == id }.map { Profiles.entryText(list[$0], order: $0) }
            let lt = st[r.k] ?? (cur != nil ? 1 : 0)
            if r.t < lt || (r.t == lt && (r.v == nil || cur != nil)) { continue }
            setMainStamp(r.k, r.t)
            if cur == r.v { continue }
            if let v = r.v, let e = Profiles.parseEntry(id: id, v) { Profiles.upsert(e) } else if r.v == nil { Profiles.remove(id) }
            n += 1
        }
        // 2. profil principal (clés d'origine), 3. autres profils (clés « @id: »)
        forced = .standard
        n += applyProfile(recs.filter { !$0.k.hasPrefix("@") && !$0.k.hasPrefix("prof|") }, global: true)
        for p in Profiles.all where p.id != Profiles.mainId {
            let pre = "@\(p.id):"
            let mine = recs.compactMap { r in r.k.hasPrefix(pre) ? SyncRec(k: String(r.k.dropFirst(pre.count)), t: r.t, v: r.v) : nil }
            if mine.isEmpty { continue }
            forced = Profiles.defaults(for: p.id)
            n += applyProfile(mine, global: false)
        }
        return n
    }

    private static func applyProfile(_ recs: [SyncRec], global: Bool) -> Int {
        let fav0 = Set(favs)
        var favList = favs
        var fw = follows, fwChanged = false
        var st = stamps
        var n = 0
        for r in recs where syncable(r.k) && (global || r.k != "tmdb") {
            let k = r.k
            let cur = syncValue(k, favs: fav0, fw: fw)
            let lt = st[k] ?? (cur != nil ? 1 : 0)
            if r.t < lt || (r.t == lt && (r.v == nil || cur != nil)) { continue }
            st[k] = r.t
            if cur == r.v { continue }
            let v = r.v
            let id = k.firstIndex(of: "|").map { String(k[k.index(after: $0)...]) } ?? ""
            switch k {
            case "accent":
                if let v, let i = Int(v) { d.set(i, forKey: k) } else { d.removeObject(forKey: k) }
            case "chue", "csat":
                if let v, let x = Double(v) { d.set(x, forKey: k) } else { d.removeObject(forKey: k) }
            case "tmdb":
                Secret.set("tmdb", v ?? "")
            case "prefq":
                if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) }
            case "recent", "rlive":
                d.set((v ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }, forKey: k)
            case "hcats":
                let a = v.flatMap { $0.data(using: .utf8) }.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String] } ?? []
                d.set(a.sorted(), forKey: k)
            case "lists":
                if let v, let data = v.data(using: .utf8), let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String]] {
                    // ordre des listes : celui du texte reçu
                    let order = m.keys.sorted { (v.range(of: jsonText($0))?.lowerBound ?? v.endIndex) < (v.range(of: jsonText($1))?.lowerBound ?? v.endIndex) }
                    d.set(listsJSON(m, order: order), forKey: "lists")
                    d.set(order, forKey: "listOrder")
                } else {
                    d.removeObject(forKey: "lists"); d.removeObject(forKey: "listOrder")
                }
            default:
                if k.hasPrefix("fav|") {
                    favList.removeAll { $0 == id }
                    if v != nil { favList.insert(id, at: 0) }
                } else if k.hasPrefix("rate|") {
                    if let v, let i = Int(v) { d.set(i, forKey: "r_" + id) } else { d.removeObject(forKey: "r_" + id) }
                } else if k.hasPrefix("pos|") {
                    let p = (v ?? "").split(separator: ";").map { Int($0) ?? 0 }
                    if v != nil, p.count == 2 { d.set(p[0], forKey: "p_" + id); d.set(p[1], forKey: "d_" + id) }
                    else { d.removeObject(forKey: "p_" + id); d.removeObject(forKey: "d_" + id) }
                } else if k.hasPrefix("seen|") {
                    if v != nil { d.set(true, forKey: "s_" + id) } else { d.removeObject(forKey: "s_" + id) }
                } else if k.hasPrefix("last|") {
                    if let v, let i = Int(v) { d.set(i, forKey: "last_" + id) } else { d.removeObject(forKey: "last_" + id) }
                } else if k.hasPrefix("lq|") {
                    if let v { d.set(v, forKey: "lq_" + id) } else { d.removeObject(forKey: "lq_" + id) }
                } else if k.hasPrefix("fw|") {
                    fw[id] = v.flatMap(parseFollow)
                    fwChanged = true
                }
            }
            n += 1
        }
        if Set(favList) != fav0 { d.set(favList, forKey: "favs") }
        if fwChanged, let data = try? JSONEncoder().encode(fw) { d.set(data, forKey: "follows") }
        stamps = st
        return n
    }
}

// ======================= Échange des données (Wi-Fi et GitHub) =======================

extension Store {
    /// Enregistrements au format JSON commun : [[clé, date_ms, valeur|null], …].
    static func recordsJSON(_ recs: [SyncRec]) -> [[Any]] {
        recs.map { [$0.k, NSNumber(value: $0.t), $0.v ?? NSNull()] }
    }

    static func parseRecords(_ any: Any?) -> [SyncRec] {
        (any as? [[Any]] ?? []).compactMap { r in
            guard r.count >= 3, let k = r[0] as? String, !k.isEmpty else { return nil }
            let t = (r[1] as? NSNumber)?.int64Value ?? Int64(r[1] as? String ?? "") ?? 0
            let v: String? = r[2] is NSNull ? nil : (r[2] as? String ?? (r[2] as? NSNumber)?.stringValue)
            return SyncRec(k: k, t: t, v: v)
        }
    }

    /// Fusion de deux jeux de données (fichier GitHub et appareil) : pour chaque clé, la date la plus récente ;
    /// à date égale, une valeur l'emporte sur une suppression. Les clés inconnues sont gardées telles quelles ;
    /// les données d'un profil supprimé (« prof|id » = null) sont retirées. Résultat trié par clé.
    static func mergeRecords(_ a: [SyncRec], _ b: [SyncRec]) -> [SyncRec] {
        var m: [String: SyncRec] = [:]
        for r in a + b {
            if let c = m[r.k] {
                if r.t > c.t || (r.t == c.t && c.v == nil && r.v != nil) { m[r.k] = r }
            } else {
                m[r.k] = r
            }
        }
        let gone = Set(m.values.filter { $0.k.hasPrefix("prof|") && $0.v == nil }.map { String($0.k.dropFirst(5)) })
        return m.values.filter { r in
            guard r.k.hasPrefix("@"), let c = r.k.firstIndex(of: ":") else { return true }
            return !gone.contains(String(r.k[r.k.index(after: r.k.startIndex)..<c]))
        }.sorted { $0.k < $1.k }
    }
}

/// Petits secrets saisis sur l'appareil (clé TMDB), gardés dans le trousseau, avec une copie en mémoire
/// (la clé est consultée pour chaque affiche).
enum Secret {
    private static let service = "IptvTV"
    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    private static func base(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
    }

    static func get(_ name: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let v = cache[name] { return v }
        var q = base(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let v = SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "" : ""
        cache[name] = v
        return v
    }

    static func set(_ name: String, _ v: String) {
        lock.lock(); defer { lock.unlock() }
        cache[name] = v
        SecItemDelete(base(name) as CFDictionary)
        guard !v.isEmpty else { return }
        var q = base(name)
        q[kSecValueData as String] = Data(v.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// Mise en forme d'une durée en millisecondes : « 1:02:03 » ou « 12:34 ».
func fmtTime(_ ms: Int) -> String {
    let s = max(0, ms / 1000)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}
