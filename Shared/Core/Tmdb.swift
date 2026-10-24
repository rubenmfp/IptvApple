import Foundation

/// Une personne d'une fiche TMDB, avec sa photo si TMDB en a une.
struct TmdbPerson: Codable, Equatable { var name: String; var photo: String? }

/// Fiche TMDB : note sur 10, votes, résumé français, date (AAAA-MM-JJ), durée (minutes), bande-annonce (YouTube),
/// réalisateurs (créateurs pour une série) et acteurs.
struct TmdbInfo: Codable, Equatable {
    var id: Int
    var rating: Double
    var votes: Int
    var overview: String
    var date: String
    var runtime: Int
    var trailer: String?
    var directors: [TmdbPerson]
    var cast: [TmdbPerson]
}

enum TmdbError: LocalizedError {
    case badKey, http(Int)
    var errorDescription: String? {
        switch self {
        case .badKey: return "clé refusée par TMDB"
        case .http(let c): return "erreur \(c) de TMDB"
        }
    }
}

/// Client TMDB (themoviedb.org). Inactif tant qu'aucune clé n'est saisie dans les réglages.
/// Clé v3 (32 caractères, en paramètre) ou jeton v4 (long, en en-tête).
actor Tmdb {
    static let shared = Tmdb()

    nonisolated static var key: String { Store.tmdbKey }
    nonisolated static var enabled: Bool { !key.trimmed.isEmpty }

    private var details: [String: TmdbInfo] = [:]
    private var stills: [String: [Int: String]] = [:]
    private var pops: [String: [PopTitle]] = [:]
    private var faces: [String: String] = [:]
    private var rates: [String: Double] = [:]
    private var loaded = false
    private var dirty = 0
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()

    private var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("tmdb.json")
    }

    private struct Disk: Codable { var faces: [String: String]; var rates: [String: Double] }

    /// Notes et photos déjà trouvées (pour ne pas réinterroger TMDB à chaque lancement).
    private func load() {
        guard !loaded else { return }
        loaded = true
        if let d = try? Data(contentsOf: cacheFile), let disk = try? JSONDecoder().decode(Disk.self, from: d) {
            faces = disk.faces
            rates = disk.rates
        }
    }

    private func touch() {
        dirty += 1
        if dirty % 20 == 0 { flush() }
    }

    func flush() {
        if let d = try? JSONEncoder().encode(Disk(faces: faces, rates: rates)) { try? d.write(to: cacheFile, options: .atomic) }
    }

    private func get(_ path: String) async throws -> [String: Any] {
        let k = Self.key.trimmed
        let bearer = k.count > 40
        let auth = bearer ? "" : (path.contains("?") ? "&" : "?") + "api_key=" + k
        guard let url = URL(string: "https://api.themoviedb.org/3" + path + auth) else { throw TmdbError.http(0) }
        var r = URLRequest(url: url)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if bearer { r.setValue("Bearer " + k, forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
        if code == 401 { throw TmdbError.badKey }
        if !(200..<300).contains(code) { throw TmdbError.http(code) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
    private static func str(_ o: [String: Any], _ k: String) -> String {
        guard let v = o[k], !(v is NSNull) else { return "" }
        return "\(v)"
    }
    private static func img(_ path: String, _ size: String) -> String? { path.hasPrefix("/") ? "https://image.tmdb.org/t/p/\(size)\(path)" : nil }

    func test() async -> String {
        do {
            let o = try await get("/configuration")
            return o["images"] != nil ? "Clé valide : notes, résumés, bandes-annonces, photos et classements activés." : "Réponse inattendue de TMDB."
        } catch {
            return "Échec : \(error.localizedDescription)"
        }
    }

    /// Résultat de recherche d'un titre : celui au nom identique, sinon le premier.
    private func findHit(type: String, title: String, year: Int) async throws -> [String: Any]? {
        let tv = type == "series"
        let q = Rx(#"\s*\((?:19|20)\d{2}\)\s*$"#).replace(title).trimmed
        if q.isEmpty { return nil }
        func search(_ withYear: Bool) async throws -> [[String: Any]] {
            let y = withYear && year > 0 ? (tv ? "&first_air_date_year=\(year)" : "&year=\(year)") : ""
            let o = try await get("/search/\(tv ? "tv" : "movie")?language=fr-FR&include_adult=false&query=\(Self.enc(q))\(y)")
            return o["results"] as? [[String: Any]] ?? []
        }
        var res = try await search(true)
        if res.isEmpty && year > 0 { res = try await search(false) }
        let want = normTitle(q)
        for o in res where ["title", "original_title", "name", "original_name"].contains(where: { normTitle(Self.str(o, $0)) == want }) {
            return o
        }
        return res.first
    }

    /// Fiche TMDB en français, ou nil (pas de clé, titre introuvable, erreur réseau).
    func details(type: String, tmdbId: Int, title: String, year: Int) async -> TmdbInfo? {
        guard Self.enabled else { return nil }
        let tv = type == "series"
        let ck = "\(type)|\(tmdbId)|\(title)"
        if let d = details[ck] { return d }
        var id = tmdbId
        if id <= 0 {
            guard let hit = try? await findHit(type: type, title: title, year: year), let i = hit["id"] as? Int else { return nil }
            id = i
        }
        guard let o = try? await get("/\(tv ? "tv" : "movie")/\(id)?language=fr-FR&append_to_response=videos,credits&include_video_language=fr,en,null")
        else { return nil }
        // bande-annonce YouTube : française de préférence, puis anglaise ; « Trailer » avant « Teaser »
        var trailer: String?
        var best = 99
        for v in ((o["videos"] as? [String: Any])?["results"] as? [[String: Any]] ?? []) where Self.str(v, "site") == "YouTube" {
            let t = Self.str(v, "type"), lang = Self.str(v, "iso_639_1")
            let score = (lang == "fr" ? 0 : lang == "en" ? 2 : 4) + (t == "Trailer" ? 0 : t == "Teaser" ? 1 : 6)
            if score < best, !Self.str(v, "key").isEmpty { best = score; trailer = Self.str(v, "key") }
        }
        let credits = o["credits"] as? [String: Any]
        let cast = (credits?["cast"] as? [[String: Any]] ?? []).prefix(14)
            .map { TmdbPerson(name: Self.str($0, "name"), photo: Self.img(Self.str($0, "profile_path"), "w185")) }
        let crewSrc: [[String: Any]] = tv ? (o["created_by"] as? [[String: Any]] ?? [])
            : (credits?["crew"] as? [[String: Any]] ?? []).filter { Self.str($0, "job") == "Director" }
        var seen = Set<String>()
        let crew = crewSrc.map { TmdbPerson(name: Self.str($0, "name"), photo: Self.img(Self.str($0, "profile_path"), "w185")) }
            .filter { !$0.name.isEmpty && seen.insert($0.name).inserted }
        var runtime = 0
        if tv {
            runtime = (o["episode_run_time"] as? [Int])?.first ?? ((o["last_episode_to_air"] as? [String: Any])?["runtime"] as? Int ?? 0)
        } else {
            runtime = o["runtime"] as? Int ?? 0
        }
        let info = TmdbInfo(id: id, rating: o["vote_average"] as? Double ?? 0, votes: o["vote_count"] as? Int ?? 0,
                            overview: Self.str(o, "overview"), date: Self.str(o, tv ? "first_air_date" : "release_date"),
                            runtime: runtime, trailer: trailer, directors: crew, cast: cast.filter { !$0.name.isEmpty })
        details[ck] = info
        return info
    }

    /// Images des épisodes d'une saison : numéro d'épisode -> adresse.
    func seasonStills(tvId: Int, season: Int) async -> [Int: String] {
        guard Self.enabled, tvId > 0 else { return [:] }
        let ck = "\(tvId)|\(season)"
        if let s = stills[ck] { return s }
        guard let o = try? await get("/tv/\(tvId)/season/\(season)?language=fr-FR") else { return [:] }
        var m: [Int: String] = [:]
        for e in o["episodes"] as? [[String: Any]] ?? [] {
            if let n = e["episode_number"] as? Int, let u = Self.img(Self.str(e, "still_path"), "w300") { m[n] = u }
        }
        stills[ck] = m
        return m
    }

    // ---------- notes des affiches : la même note que sur la fiche ----------
    /// Note connue : note (0 = pas de note, -1 = inconnu de TMDB) ; nil = pas encore cherchée.
    func cachedRate(_ k: String) -> Double? { load(); return rates[k] }

    func rate(_ i: Item) async -> Double? {
        guard Self.enabled else { return nil }
        load()
        if let r = rates[i.key] { return r }
        let r: Double
        do {
            let o: [String: Any]?
            if i.tmdb > 0 { o = try await get("/\(i.type == "series" ? "tv" : "movie")/\(i.tmdb)?language=fr-FR") }
            else { o = try await findHit(type: i.type, title: i.name, year: i.year) }
            r = o.map { $0["vote_average"] as? Double ?? 0 } ?? -1
        } catch TmdbError.http(404) {
            r = -1
        } catch {
            return nil
        }
        rates[i.key] = r
        touch()
        return r
    }

    /// Photo d'une personne : adresse, "" si elle n'en a pas ; nil en cas d'erreur réseau.
    func face(_ name: String) async -> String? {
        let k = name.trimmed.lowercased()
        guard Self.enabled, !k.isEmpty else { return nil }
        load()
        if let f = faces[k] { return f }
        guard let o = try? await get("/search/person?language=fr-FR&include_adult=false&query=\(Self.enc(name.trimmed))") else { return nil }
        let url = (o["results"] as? [[String: Any]] ?? []).compactMap { Self.img(Self.str($0, "profile_path"), "w185") }.first ?? ""
        faces[k] = url
        touch()
        return url
    }

    /// Titres populaires en France (cinéma et plateformes), du plus au moins populaire.
    func popular(_ type: String) async -> [PopTitle] {
        guard Self.enabled else { return [] }
        if let p = pops[type] { return p }
        let stream = "sort_by=popularity.desc&watch_region=FR&with_watch_monetization_types=flatrate"
        let paths = type == "vod"
            ? ["/movie/popular?region=FR&page=1", "/discover/movie?region=FR&\(stream)&page=1", "/movie/popular?region=FR&page=2",
               "/discover/movie?region=FR&\(stream)&page=2", "/movie/popular?region=FR&page=3", "/movie/now_playing?region=FR&page=1",
               "/trending/movie/week?page=1"]
            : ["/discover/tv?\(stream)&page=1", "/trending/tv/week?page=1", "/discover/tv?\(stream)&page=2",
               "/discover/tv?\(stream)&page=3", "/discover/tv?\(stream)&page=4"]
        var order: [Int] = []
        var fr: [Int: (String, String)] = [:]
        var en: [Int: String] = [:]
        for p in paths {
            guard let r = try? await get(p + "&language=fr-FR") else { continue }
            for o in r["results"] as? [[String: Any]] ?? [] {
                guard let id = o["id"] as? Int else { continue }
                let t = Self.str(o, "title").isEmpty ? Self.str(o, "name") : Self.str(o, "title")
                let ot = Self.str(o, "original_title").isEmpty ? Self.str(o, "original_name") : Self.str(o, "original_title")
                if !t.isEmpty && fr[id] == nil { fr[id] = (t, ot); order.append(id) }
            }
            // même page en anglais : beaucoup de catalogues nomment les titres « titre français + titre anglais »
            if let e = try? await get(p + "&language=en-US") {
                for o in e["results"] as? [[String: Any]] ?? [] {
                    if let id = o["id"] as? Int { en[id] = Self.str(o, "title").isEmpty ? Self.str(o, "name") : Self.str(o, "title") }
                }
            }
        }
        let l = order.compactMap { id in fr[id].map { PopTitle(fr: $0.0, orig: $0.1, en: en[id] ?? "") } }
        if !l.isEmpty { pops[type] = l }
        return l
    }
}
