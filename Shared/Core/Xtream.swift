import Foundation

enum XtreamError: LocalizedError {
    case badLink
    case badCredentials
    case http(Int)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .badLink: return "Adresse invalide. Vérifiez le serveur (ex. http://exemple.com:8080) ou le lien M3U."
        case .badCredentials: return "Le fournisseur refuse ces identifiants (utilisateur ou mot de passe incorrect, ou abonnement expiré)."
        case .http(let c): return "Le serveur a répondu par une erreur \(c)."
        case .unexpected(let s): return "Réponse inattendue du serveur (\(s))."
        }
    }
}

/// État du compte renvoyé par le fournisseur (user_info / server_info).
struct AccountStatus: Codable, Equatable {
    var status: String
    var expires: Date?
    var active: String
    var max: String
    var streamBase: String?

    var summary: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .long
        let exp = expires.map { f.string(from: $0) } ?? "illimité"
        return "Compte : \(status.isEmpty ? "?" : status) · expire le \(exp) · connexions : \(active.isEmpty ? "?" : active)/\(max.isEmpty ? "?" : max)"
    }
}

enum Xtream {
    // ---------- lien M3U ----------
    /// Serveur, utilisateur et mot de passe tirés d'un lien M3U « get.php?username=…&password=… » ou d'une adresse de flux.
    static func parseLink(_ link: String) -> XtreamAccount? {
        var s = link.trimmed
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard let hm = Rx(#"^(https?://[^/?#\s]+)"#, [.caseInsensitive]).first(s), var host = hm.group(1, in: s) else { return nil }
        while host.hasSuffix("/") { host.removeLast() }
        func dec(_ x: String) -> String {
            x.replacingOccurrences(of: "+", with: "%2B").removingPercentEncoding ?? x
        }
        let user = Rx(#"[?&]username=([^&#\s]*)"#, [.caseInsensitive]).first(s)?.group(1, in: s).map(dec)
        let pass = Rx(#"[?&]password=([^&#\s]*)"#, [.caseInsensitive]).first(s)?.group(1, in: s).map(dec)
        if let u = user, !u.trimmed.isEmpty, let p = pass { return XtreamAccount(host: host, user: u, pass: p) }
        // adresse d'un flux : http://serveur:port/live/<utilisateur>/<mot de passe>/123.ts (ou movie, series)
        let rest = String(s.dropFirst(host.count)).components(separatedBy: "?")[0]
        let path = rest.split(separator: "/").map(String.init)
        if let k = path.firstIndex(where: { $0 == "live" || $0 == "movie" || $0 == "series" }), path.count >= k + 3 {
            return XtreamAccount(host: host, user: dec(path[k + 1]), pass: dec(path[k + 2]))
        }
        return nil
    }

    /// Serveur saisi à la main : ajoute « http:// » si besoin et retire le « / » final.
    static func normalizeHost(_ h: String) -> String {
        var s = h.trimmed
        if !s.isEmpty, !s.lowercased().hasPrefix("http://"), !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        if let r = s.range(of: "/player_api.php") { s = String(s[..<r.lowerBound]) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

/// Accès à l'API Xtream Codes (player_api.php).
final class XtreamClient {
    let account: XtreamAccount
    private let session: URLSession

    init(_ account: XtreamAccount) {
        self.account = account
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 300
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        session = URLSession(configuration: c)
    }

    private static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    func apiURL(_ query: String = "") throws -> URL {
        var s = "\(account.host)/player_api.php?username=\(Self.enc(account.user))&password=\(Self.enc(account.pass))"
        if !query.isEmpty { s += "&" + query }
        guard let u = URL(string: s) else { throw XtreamError.badLink }
        return u
    }

    private func get(_ query: String) async throws -> Data {
        let (data, resp) = try await session.data(from: try apiURL(query))
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw XtreamError.http(h.statusCode) }
        return data
    }

    /// Vérifie les identifiants et lit l'état du compte.
    func status() async throws -> AccountStatus {
        let data = try await get("")
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw XtreamError.unexpected("pas de JSON")
        }
        guard let u = j["user_info"] as? [String: Any] else { throw XtreamError.badCredentials }
        let auth = "\(u["auth"] ?? "")"
        if auth == "0" || auth == "false" { throw XtreamError.badCredentials }
        func str(_ o: [String: Any], _ k: String) -> String {
            guard let v = o[k], !(v is NSNull) else { return "" }
            return "\(v)"
        }
        var st = AccountStatus(status: str(u, "status"), expires: Double(str(u, "exp_date")).map { Date(timeIntervalSince1970: $0) },
                               active: str(u, "active_cons"), max: str(u, "max_connections"), streamBase: nil)
        if let o = j["server_info"] as? [String: Any] {
            let url = str(o, "url")
            if !url.isEmpty {
                let proto = str(o, "server_protocol").isEmpty ? "http" : str(o, "server_protocol")
                var port = proto == "https" ? str(o, "https_port") : str(o, "port")
                if port.isEmpty { port = str(o, "port") }
                st.streamBase = "\(proto)://\(url)" + (!port.isEmpty && port != "80" && port != "443" ? ":\(port)" : "")
            }
        }
        return st
    }

    /// Catégories dans l'ordre du fournisseur : [(id, nom)].
    func categories(_ action: String) async throws -> [(String, String)] {
        let data = try await get("action=\(action)")
        var out: [(String, String)] = []
        try data.withUnsafeBytes { raw in
            var s = JSONScan(raw.bindMemory(to: UInt8.self))
            _ = try s.list { s in
                guard s.peek() == 0x7B else { try s.skip(); return }
                var id = "", name = ""
                try s.object { s, k in
                    switch k {
                    case "category_id": id = try s.scalar()
                    case "category_name": name = try s.scalar()
                    default: try s.skip()
                    }
                }
                out.append((id, name))
            }
        }
        return out
    }

    /// Films, séries ou chaînes, regroupés (versions d'un même titre, qualités d'une même chaîne).
    /// Rend aussi les noms de catégories dans l'ordre du fournisseur.
    func items(_ type: String) async throws -> (cats: [String], items: [Item]) {
        let pair: (String, String)
        switch type {
        case "live": pair = ("get_live_categories", "get_live_streams")
        case "vod": pair = ("get_vod_categories", "get_vod_streams")
        default: pair = ("get_series_categories", "get_series")
        }
        let (catAction, action) = pair
        let cats = try await categories(catAction).map { ($0.0, Names.cleanCategory($0.1)) }
        // grosse liste : téléchargée dans un fichier, puis lue sans tout charger en objets
        let (file, resp) = try await session.download(from: try apiURL("action=\(action)"))
        defer { try? FileManager.default.removeItem(at: file) }
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw XtreamError.http(h.statusCode) }
        let data = try Data(contentsOf: file, options: .alwaysMapped)
        let list = try Self.parseStreams(data, type: type, cats: Dictionary(cats, uniquingKeysWith: { a, _ in a }))
        let merged = type == "live" ? Names.mergeLive(list) : Names.mergeItems(list)
        var names: [String] = []
        var seen = Set<String>()
        for (_, n) in cats where seen.insert(n).inserted { names.append(n) }
        return (names, merged)
    }

    /// Fiche détaillée d'un film ou d'une série (avec ses épisodes).
    func info(type: String, id: Int) async throws -> ItemInfo {
        let ser = type == "series"
        let data = try await get(ser ? "action=get_series_info&series_id=\(id)" : "action=get_vod_info&vod_id=\(id)")
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw XtreamError.unexpected("fiche illisible") }
        return Self.parseInfo(o, series: ser)
    }

    static func parseInfo(_ o: [String: Any], series: Bool) -> ItemInfo {
        func str(_ d: [String: Any]?, _ k: String) -> String {
            guard let v = d?[k], !(v is NSNull) else { return "" }
            if let a = v as? [Any] { return a.first.map { "\($0)" } ?? "" }
            return "\(v)".trimmed
        }
        let n = o["info"] as? [String: Any] ?? [:]
        let md = o["movie_data"] as? [String: Any]
        var info = ItemInfo()
        info.plot = str(n, "plot").isEmpty ? str(n, "description") : str(n, "plot")
        info.cast = str(n, "cast").isEmpty ? str(n, "actors") : str(n, "cast")
        info.director = str(n, "director")
        info.genre = str(n, "genre")
        info.rating = str(n, "rating")
        info.releaseDate = [str(n, "releaseDate"), str(n, "releasedate"), str(n, "release_date")].first { !$0.isEmpty } ?? ""
        let bd = str(n, "backdrop_path")
        info.backdrop = bd.hasPrefix("http") ? bd : nil
        info.tmdb = [str(n, "tmdb_id"), str(n, "tmdb"), str(md, "tmdb_id")].compactMap { Int($0) }.first ?? 0
        info.ext = str(md, "container_extension").lowercased()
        // durée : « 01:52:00 », « 112 min » ou secondes selon les serveurs
        let dur = str(n, "duration")
        if let m = Rx(#"^(\d{1,2}):(\d{2})"#).first(dur), let h = m.group(1, in: dur), let mi = m.group(2, in: dur) {
            info.runtime = (Int(h) ?? 0) * 60 + (Int(mi) ?? 0)
        } else if let s = Int(str(n, "duration_secs")) {
            info.runtime = s / 60
        } else {
            info.runtime = Int(str(n, "episode_run_time")) ?? 0
        }
        if series {
            var eps: [Episode] = []
            var groups: [(String, Any)] = []
            if let e = o["episodes"] as? [String: Any] { groups = e.map { ($0.key, $0.value) } }
            else if let e = o["episodes"] as? [Any] { groups = e.enumerated().map { ("\($0.offset + 1)", $0.element) } }
            for (season, list) in groups {
                for case let x as [String: Any] in (list as? [Any] ?? []) {
                    let ei = x["info"] as? [String: Any]
                    let img = ["movie_image", "cover_big", "cover"].map { str(ei, $0) }.first { $0.hasPrefix("http") }
                    var secs = Int(str(ei, "duration_secs")) ?? 0
                    if secs == 0, let m = Rx(#"^(\d{1,2}):(\d{2}):(\d{2})"#).first(str(ei, "duration")) {
                        let d = str(ei, "duration")
                        secs = (Int(m.group(1, in: d) ?? "") ?? 0) * 3600 + (Int(m.group(2, in: d) ?? "") ?? 0) * 60
                    }
                    let ext = str(x, "container_extension")
                    eps.append(Episode(id: Int(str(x, "id")) ?? 0, title: Names.cleanEpisode(str(x, "title")),
                                       season: Int(str(x, "season")) ?? Int(season) ?? 1, num: Int(str(x, "episode_num")) ?? 0,
                                       ext: ext.isEmpty ? "mp4" : ext, image: img, plot: str(ei, "plot"), runtime: secs / 60))
                }
            }
            info.episodes = eps.filter { $0.id > 0 }.sorted { ($0.season, $0.num) < ($1.season, $1.num) }
        }
        return info
    }

    /// Lecture d'une liste get_vod_streams / get_series / get_live_streams.
    static func parseStreams(_ data: Data, type: String, cats: [String: String]) throws -> [Item] {
        let ser = type == "series", live = type == "live"
        var list: [Item] = []
        var keyed = false
        try data.withUnsafeBytes { raw in
            var s = JSONScan(raw.bindMemory(to: UInt8.self))
            let r = try s.list { s in
                guard s.peek() == 0x7B else { try s.skip(); return }
                var id = 0, rawName = "", icon = "", catId = "", ext = "", rating = "", cast = "", director = "", epg = ""
                var tmdb = 0, year = 0
                try s.object { s, k in
                    switch k {
                    case "stream_id": if ser { try s.skip() } else { let v = try s.scalar(); id = Int(v.trimmed) ?? 0 }
                    case "series_id": if ser { let v = try s.scalar(); id = Int(v.trimmed) ?? 0 } else { try s.skip() }
                    case "name": rawName = try s.scalar()
                    case "stream_icon": if ser { try s.skip() } else { icon = try s.scalar() }
                    case "cover": if ser { icon = try s.scalar() } else { try s.skip() }
                    case "category_id": catId = try s.scalar()
                    case "container_extension": ext = try s.scalar()
                    case "rating": rating = try s.scalar()
                    case "cast": cast = try s.scalar()
                    case "director": director = try s.scalar()
                    case "epg_channel_id": epg = try s.scalar()
                    case "tmdb", "tmdb_id": let v = try s.scalar(); tmdb = Int(v.trimmed) ?? 0
                    case "year": let v = try s.scalar(); year = Int(String(v.trimmed.prefix(4))) ?? year
                    case "releaseDate", "release_date", "releasedate":
                        let v = try s.scalar()
                        if year == 0 { year = Int(String(v.trimmed.prefix(4))) ?? 0 }
                    default: try s.skip()
                    }
                }
                if id == 0 && rawName.trimmed.isEmpty { return }       // pas un contenu (ex. message d'erreur du serveur)
                let e = ext.trimmed.isEmpty ? "mp4" : ext.trimmed
                let (nm, q) = live ? Names.cleanLive(rawName) : Names.clean(rawName)
                let people = ser ? [cast, director].filter { !$0.trimmed.isEmpty }.joined(separator: ", ") : ""
                if year == 0 && !live, let m = Names.yearInRe.first(rawName), let y = m.group(1, in: rawName) { year = Int(y) ?? 0 }
                list.append(Item(type: type, id: id, name: nm, poster: icon.trimmed.isEmpty ? nil : icon.trimmed,
                                 cat: cats[catId] ?? "Divers", ext: e, rating: Double(rating.trimmed) ?? 0, people: people,
                                 variants: [Variant(id: id, ext: e, q: q)], epg: live ? epg : "", tmdb: tmdb, year: year))
            }
            if !r.ok { throw XtreamError.unexpected("liste absente") }
            keyed = r.keyed
        }
        if keyed && list.isEmpty { throw XtreamError.unexpected("objet sans contenu") }
        return list
    }
}
