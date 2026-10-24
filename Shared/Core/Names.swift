import Foundation

// Nettoyage et regroupement des noms : portage fidèle de Data.kt (appli Android 0.14).

enum Names {
    static let junk = #"(?:19|20)\d{2}|MULTI|VF|VFF|VFQ|VFI|VF2|VOSTFR|VOST|VO|FRENCH|TRUEFRENCH|SUBFRENCH|4K|UHD|FHD|HD|SD|HDR|HDR10|HEVC|H265|X265"#

    static let tagRe = Rx(#"^\s*(?:\|\s*([A-Za-z0-9+\- ]{1,8}?)\s*\||([A-Za-z0-9+\- ]{1,8}?)\s*\||\[\s*([A-Za-z]{2,5}|4K)\s*\])\s*"#)
    static let qualRe = Rx(#"\b(4K|UHD|FHD|HD|SD)\b"#, [.caseInsensitive])
    static let yearRe = Rx(#"\s*[\[(]\s*(?:19|20)\d{2}\s*[\])]"#)
    static let trailRe = Rx(#"\s*(?:[\[(]|\|)\s*([^\])|]*?)\s*(?:[\])]|\|)?\s*$"#)
    static let junkRe = Rx("(?i)\\b(?:\(junk))\\b")
    /// Groupe entre parenthèses ou crochets dont tout le contenu est technique : « (MULTI) », « [4K HDR] », « (VF - 2024) ».
    static let junkGroupRe = Rx("(?i)\\s*[\\[(]\\s*(?:(?:\(junk))[\\s,/+.\\-]*)+[\\])]")
    /// « MULTI » / « MULTi » isolé, n'importe où dans le titre.
    static let multiRe = Rx(#"\s*(?:[-–|]\s*)?\bMULT[Ii]\b"#)
    /// Mention technique sans parenthèses en fin de titre : « Titre MULTI », « Titre - VOSTFR », « Titre 4K ».
    static let bareTailRe = Rx(#"(?i)(?:\s*[-–|:]\s*|\s+)(MULTI|VOSTFR|TRUEFRENCH|SUBFRENCH|VFF|VFQ|VFI|VF2|UHD|FHD|4K|HD|SD)\s*$"#)
    /// Qualité en tête sans barres : « HD - Titre », « SD: Titre ».
    static let headQualRe = Rx(#"(?i)^\s*(4K|UHD|FHD|HD|SD)\s*[-–:|]\s*"#)
    static let emptyGroupRe = Rx(#"\s*(?:\(\s*\)|\[\s*\])"#)
    static let tailSepRe = Rx(#"\s*[-–|:(\[]\s*$"#)
    static let onlyJunkRe = Rx("(?i)^(?:\(junk))$")
    static let spacesRe = Rx(#"\s{2,}"#)
    /// Langue en fin de titre derrière une barre : « Épisode 3 |FR », « Titre | VF ».
    static let pipeLangRe = Rx(#"(?i)\s*\|\s*(?:FR|EN|VF|VO|VOSTFR|MULTI|FRENCH)\s*\|?\s*$"#)
    static let yearInRe = Rx(#"[\[(]\s*((?:19|20)\d{2})\s*[\])\s]"#)

    /// Ordre de préférence des qualités : FHD, HD, 4K, SD, inconnue.
    static let qRank = ["FHD", "HD", "4K", "SD", "?"]
    static func rank(_ q: String) -> Int { qRank.firstIndex(of: q) ?? 99 }

    /// « |SD| Titre (2026 MULTI) » -> (« Titre », « SD »).
    static func clean(_ raw: String) -> (name: String, q: String) {
        let a = clean(raw, tags: true)
        var r = a
        // « Titre | MULTI » : le titre, court et suivi d'une barre, a été pris pour une étiquette -> on recommence sans les étiquettes
        if a.name.trimmed.isEmpty || onlyJunkRe.matches(a.name) {
            let b = clean(raw, tags: false)
            r = b.name.trimmed.isEmpty ? a : b
        }
        return (r.name.trimmed.isEmpty ? raw.trimmed : r.name, r.q)
    }

    private static func upperQual(_ s: String) -> String? {
        qualRe.first(s).flatMap { $0.group(0, in: s) }?.uppercased()
    }

    private static func clean(_ raw: String, tags: Bool) -> (name: String, q: String) {
        var t = raw.trimmed
        var q: String? = nil
        if tags {
            for _ in 0..<4 {
                guard let m = tagRe.first(t) else { break }
                let tag = (1...3).lazy.compactMap { m.group($0, in: t) }.first ?? ""
                if q == nil { q = upperQual(tag) }
                t = t.substring(fromUTF16: m.range.location + m.range.length)
            }
        }
        if let m = headQualRe.first(t), m.range.location + m.range.length < (t as NSString).length {
            if q == nil { q = upperQual(m.group(1, in: t) ?? "") }
            t = t.substring(fromUTF16: m.range.location + m.range.length)
        }
        t = yearRe.replace(t)
        if q == nil {
            for m in junkGroupRe.all(t) {
                if let v = m.group(0, in: t), let u = upperQual(v) { q = u; break }
            }
        }
        t = junkGroupRe.replace(t)
        for _ in 0..<6 {
            if let bare = bareTailRe.first(t), bare.range.location > 0 {     // jamais si c'est tout le titre
                if q == nil { q = upperQual(bare.group(1, in: t) ?? "") }
                t = t.removing(bare.range).trimmed
                continue
            }
            guard let m = trailRe.first(t) else { break }
            let inner = m.group(1, in: t) ?? ""
            if !junkRe.contains(inner) { break }
            if q == nil { q = upperQual(inner) }
            t = t.removing(m.range).trimmed
        }
        t = pipeLangRe.replace(t)
        t = multiRe.replace(t)
        t = emptyGroupRe.replace(t)
        t = tailSepRe.replace(t)
        t = spacesRe.replace(t, " ")
        if q == "UHD" { q = "4K" }
        return (t.trimmed, q ?? "?")
    }

    // ---------- épisodes et catégories ----------
    static let epRe = Rx(#"(?i)\bS\d{1,2}\s?E\d{1,3}\s*[-–:]\s*(.+)$"#)

    /// « Série S01E03 - Le titre » -> « Le titre » (nettoyé) ; sinon le titre nettoyé.
    static func cleanEpisode(_ raw: String) -> String {
        if let m = epRe.first(raw), let t = m.group(1, in: raw)?.trimmed, !t.isEmpty { return clean(t).name }
        return clean(raw).name
    }

    static let catTagRe = Rx(#"^\s*\|\s*([^|]{1,12}?)\s*\|\s*(.+)$"#)
    static let langTags: Set<String> = ["FR", "EN", "VF", "VO", "VOST", "VOSTFR", "MULTI", "FRENCH", "UK", "US"]

    /// Nom de catégorie lisible : « |FR| Action » -> « Action », « |2026| Nouveauté » -> « Nouveauté 2026 ».
    static func cleanCategory(_ raw: String) -> String {
        var t = raw.trimmed
        for _ in 0..<3 {
            guard let m = catTagRe.first(t), let tag = m.group(1, in: t), let rest = m.group(2, in: t) else { break }
            t = langTags.contains(tag.uppercased()) ? rest.trimmed : "\(rest.trimmed) \(tag)"
        }
        return t.isEmpty ? raw.trimmed : t
    }

    // ---------- clé de regroupement ----------
    static let keyParenRe = Rx(#"\([^)]*\)|\[[^\]]*\]"#)
    static let keyCountryRe = Rx(#"\s+-\s+\p{L}{2}$"#)
    static let keyNonWordRe = Rx(#"[^\p{L}\p{N}]+"#)
    /// Préfixe de langue ou de pays en majuscules (« FR: Titre », « VOSTFR | Titre »).
    static let keyHeadRe = Rx(#"^\s*(?:FR|EN|US|UK|VF|VO|VOST|VOSTFR|MULTI|DE|ES|IT|PT|AR|TR|BE|CH|CA|QC)\s*[:|]\s*"#)
    static let keyTailRe = Rx(#"(?:\s+(?:vf|vff|vfq|vfi|vo|vost|vostfr|multi|french|truefrench|subfrench|hd|fhd|sd|uhd|4k|hdr|hdr10|hevc|x265|h265|1080p|720p))+$"#)

    /// Clé de regroupement : minuscules, sans accents ni ponctuation, sans parenthèses ni suffixe « - FR ».
    /// « L'Été », « L’été », « L'été - FR », « FR: L'été » et « L'été VF » donnent la même clé.
    static func mergeKey(_ name: String, live: Bool = false) -> String {
        // chaînes : le préfixe de pays est gardé (« UK: Eurosport » et « FR: Eurosport » ne sont pas la même chaîne)
        var t = (live ? name : keyHeadRe.replace(name)).lowercased()
        t = keyParenRe.replace(t, " ").trimmed
        t = keyCountryRe.replace(t)
        var k = keyNonWordRe.replace(t.folding(options: [.diacriticInsensitive], locale: nil), " ").trimmed
        k = keyTailRe.replace(k).trimmed
        return k.isEmpty ? name.lowercased().trimmed : k
    }

    /// Texte comparable pour la recherche : minuscules et sans accents.
    static func searchKey(_ s: String) -> String { s.folded }

    /// Regroupe les versions d'un même titre en une seule affiche. Deux homonymes dont l'identifiant TMDB (ou l'année,
    /// à plus d'un an d'écart) diffère restent séparés, avec l'année ajoutée au nom.
    static func mergeItems(_ list: [Item]) -> [Item] {
        var order: [String] = []
        var groups: [String: [Item]] = [:]
        for i in list {
            let k = mergeKey(i.name)
            if groups[k] == nil { order.append(k); groups[k] = [i] } else { groups[k]!.append(i) }
        }
        var out: [Item] = []
        out.reserveCapacity(list.count)
        for k in order {
            let g0 = groups[k]!
            var parts: [[Item]] = [g0]
            if g0.count > 1 {
                let ids = uniq(g0.map(\.tmdb).filter { $0 > 0 })
                let years = uniq(g0.map(\.year).filter { $0 > 0 })
                // identifiants TMDB différents : homonymes seulement si les années diffèrent aussi
                // (les fournisseurs se trompent souvent d'identifiant entre la version HD et la version SD)
                if ids.count > 1, years.count > 1, years.max()! - years.min()! > 1 {
                    parts = orderedGroups(g0) { $0.tmdb > 0 ? $0.tmdb : ids[0] }
                } else if ids.isEmpty, years.count > 1, years.max()! - years.min()! > 1 {
                    parts = orderedGroups(g0) { $0.year > 0 ? $0.year : years[0] }
                }
            }
            let split = parts.count > 1
            for g in parts {
                var base = g[0]
                if g.count > 1 {
                    var seen = Set<Int>()
                    let vs = g.flatMap(\.variants).filter { seen.insert($0.id).inserted }
                        .enumerated().sorted { (rank($0.element.q), $0.offset) < (rank($1.element.q), $1.offset) }.map(\.element)
                    let p = vs[0]
                    base.id = p.id
                    base.ext = p.ext
                    base.poster = g.lazy.compactMap(\.poster).first
                    base.rating = g.map(\.rating).max() ?? 0
                    base.people = g.first { !$0.people.trimmed.isEmpty }?.people ?? ""
                    base.variants = vs
                    base.tmdb = g.first { $0.tmdb > 0 }?.tmdb ?? 0
                    base.year = g.first { $0.year > 0 }?.year ?? 0
                }
                if split && base.year > 0 { base.name = "\(base.name) (\(base.year))" }
                out.append(base)
            }
        }
        return out
    }

    private static func uniq<T: Hashable>(_ a: [T]) -> [T] { var s = Set<T>(); return a.filter { s.insert($0).inserted } }

    private static func orderedGroups<K: Hashable>(_ a: [Item], by key: (Item) -> K) -> [[Item]] {
        var order: [K] = []
        var d: [K: [Item]] = [:]
        for i in a {
            let k = key(i)
            if d[k] == nil { order.append(k); d[k] = [i] } else { d[k]!.append(i) }
        }
        return order.map { d[$0]! }
    }

    // ---------- chaînes en plusieurs qualités ----------
    static let liveTokRe = Rx(#"(?i)(^|[\s|\[(_\-])(UHD|4K|FHD|HD|SD|HEVC|H\.?265|1080P?|720P?|50\s?FPS|60\s?FPS|HQ|LQ|BACKUP)(?=$|[\s|\])_\-])"#)
    static let liveTailRe = Rx(#"[\s|_\-]+$"#)

    /// « FR: TF1 FHD (backup) » -> (« FR: TF1 », « FHD Secours »). Sans mention de qualité : « ? ».
    static func cleanLive(_ raw: String) -> (name: String, q: String) {
        var toks: [String] = []
        let ns = raw as NSString
        var t = ""
        var last = 0
        for m in liveTokRe.all(raw) {
            t += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            t += m.group(1, in: raw) ?? ""
            toks.append(m.group(2, in: raw) ?? "")
            last = m.range.location + m.range.length
        }
        t += ns.substring(from: last)
        t = emptyGroupRe.replace(t)
        t = liveTailRe.replace(t)
        t = spacesRe.replace(t, " ").trimmed
        if t.isEmpty || toks.isEmpty { return (raw.trimmed, "?") }
        var labels: [String] = []
        for tok in toks {
            let u = tok.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
            let l: String
            if u == "UHD" || u == "4K" { l = "4K" }
            else if u == "FHD" || u.hasPrefix("1080") { l = "FHD" }
            else if u == "HD" || u.hasPrefix("720") { l = "HD" }
            else if u == "H265" { l = "HEVC" }
            else if u == "BACKUP" { l = "Secours" }
            else { l = u }
            if !labels.contains(l) { labels.append(l) }
        }
        let main: Set<String> = ["FHD", "HD", "4K", "SD"]
        labels = labels.enumerated().sorted { (main.contains($0.element) ? 0 : 1, $0.offset) < (main.contains($1.element) ? 0 : 1, $1.offset) }.map(\.element)
        return (t, labels.joined(separator: " "))
    }

    /// Ordre de préférence des qualités d'une chaîne : FHD, HD, sans mention, 4K, SD, puis le reste.
    static func liveRank(_ q: String) -> Int {
        let head = q.split(separator: " ").first.map(String.init) ?? q
        let base: Int
        switch head { case "FHD": base = 0; case "HD": base = 1; case "?": base = 2; case "4K": base = 3; case "SD": base = 4; default: base = 5 }
        return base * 2 + (q.contains(" ") ? 1 : 0)
    }

    /// Regroupe « TF1 FHD », « TF1 HD », « TF1 SD »… en une chaîne à plusieurs qualités.
    static func mergeLive(_ list: [Item]) -> [Item] {
        var order: [String] = []
        var groups: [String: [Item]] = [:]
        for i in list {
            let k = mergeKey(i.name, live: true)
            if groups[k] == nil { order.append(k); groups[k] = [i] } else { groups[k]!.append(i) }
        }
        var out: [Item] = []
        for k in order {
            let g = groups[k]!
            if g.count == 1 { out.append(g[0]); continue }
            let sorted = g.enumerated().sorted {
                (liveRank($0.element.variants.first?.q ?? "?"), $0.offset) < (liveRank($1.element.variants.first?.q ?? "?"), $1.offset)
            }.map(\.element)
            var vs: [Variant] = []
            var extra: [Item] = []
            // une même qualité en double (même chaîne dans deux catégories) : la seconde reste une chaîne à part
            for i in sorted {
                guard let v = i.variants.first else { continue }
                if vs.contains(where: { $0.q == v.q }) { extra.append(i) } else { vs.append(v) }
            }
            var first = sorted[0]
            first.variants = vs
            first.poster = sorted.lazy.compactMap(\.poster).first
            first.epg = sorted.first { !$0.epg.trimmed.isEmpty }?.epg ?? ""
            out.append(first)
            out += extra
        }
        return out
    }

    // ---------- genres des chaînes ----------
    static let genres = ["Généralistes", "Infos", "Sport", "Cinéma", "Séries", "Enfants", "Documentaires", "Musique", "Divertissement"]
    static let genreRules: [(String, Rx)] = [
        ("Sport", Rx(#"(?i)sport|bein|eurosport|\bfoot|dazn|golf|\bufc\b|\bnba\b|tennis|rugby|multiplex|l'?[eé]quipe|automoto|\bf1\b|racing"#)),
        ("Enfants", Rx(#"(?i)gulli|disney|nick(?:elodeon)?\b|nick\s?jr|cartoon|boomerang|tiji|canal\s?j\b|piwi|t[eé]l[eé]toon|boing|\bkids?\b|junior|enfant|jeunesse|\bbaby|toonami|mangas?\b"#)),
        ("Infos", Rx(#"(?i)\bbfm|cnews|\blci\b|france\s?info|franceinfo|euronews|france\s?24|\bi24|\bnews\b|\binfos?\b|\bcnn\b|bbc\s?world|sky\s?news|al\s?jazeera|\blcp\b|public\s?s[eé]nat|\brt\s?france"#)),
        ("Documentaires", Rx(#"(?i)discovery|national\s?geo|nat\s?geo|plan[eè]te|histoire|ushua[iï]a|science|animaux|animal|voyage|\btrek\b|museum|crime|investigation|d[eé]couverte|chasse|p[eê]che|\bdocs?\b|documentaire"#)),
        ("Musique", Rx(#"(?i)\bmtv\b|\bmcm\b|\btrace\b|mezzo|music|musique|melody|nrj\s?hits|clubbing|rfm\s?tv|stingray"#)),
        ("Cinéma", Rx(#"(?i)cin[eé]|\bocs\b|\btcm\b|paramount|\bfilms?\b|\bmovies?\b|warner|sundance|\baction\b"#)),
        ("Séries", Rx(#"(?i)s[eé]ries?\b|serie\s?club|syfy|13\s?(?:e|[eè]me)\s?rue|polar|com[eé]die|\bab1\b|novelas?|rtl\s?9"#)),
        ("Divertissement", Rx(#"(?i)game\s?one|\bj-?one\b|t[eé]va|paris\s?premi[eè]re|c\s?star|\bcomedy\b|\be!"#)),
        ("Généralistes", Rx(#"(?i)\btf1\b|france\s?[2-5]\b|\bm6\b|\bc8\b|\bw9\b|\btmc\b|\btfx\b|\bnrj\s?12|6ter|ch[eé]rie\s?25|rmc\s?story|canal\s?\+|\bcanal\b|\barte\b|\bla\s?1\b|\brtl\b|\brts\b|\bfrance\s?[oô]\b|\bl'?[eé]quipe\s?21"#)),
    ]

    /// Genre d'une chaîne, ou nil si son nom et sa catégorie ne disent rien.
    static func liveGenre(_ i: Item) -> String? {
        let s = i.name + " " + i.cat
        return genreRules.first { $0.1.contains(s) }?.0
    }
}
