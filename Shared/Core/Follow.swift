import Foundation

// ======================= Séries suivies (cloche) =======================

/// Épisode sorti depuis qu'on suit la série.
struct NewEp: Codable, Equatable {
    var id: Int
    var season: Int
    var num: Int
    var title: String
}

/// Série suivie. `vid` = version consultée, `known` = épisodes déjà connus (« saison:numéro »), `fresh` = sorties non vues.
struct Follow: Codable, Equatable {
    var vid: Int
    var known: [String]
    var fresh: [NewEp]
}

func epCode(_ season: Int, _ num: Int) -> String { "\(season):\(num)" }

/// Compare la liste d'épisodes du serveur à ce qu'on connaissait : tout épisode inconnu devient une sortie.
/// On se repère au couple saison/numéro (et non à l'identifiant, que les fournisseurs changent parfois).
func updateFollow(_ f: Follow, vid: Int, eps: [Episode], seen: (Int) -> Bool) -> Follow {
    if eps.isEmpty { return f }                        // réponse vide : on ne touche à rien
    var byCode: [String: Episode] = [:]
    var order: [String] = []
    for e in eps {
        let c = epCode(e.season, e.num)
        if byCode[c] == nil { byCode[c] = e; order.append(c) }
    }
    let known = Set(f.known)
    let kept = f.fresh.compactMap { byCode[epCode($0.season, $0.num)] }          // toujours présentes (identifiant à jour)
    let added = order.filter { !known.contains($0) }.compactMap { byCode[$0] }
    var seenCodes = Set<String>()
    let fresh = (kept + added).filter { seenCodes.insert(epCode($0.season, $0.num)).inserted }.filter { !seen($0.id) }
        .map { NewEp(id: $0.id, season: $0.season, num: $0.num, title: $0.title) }
    var allKnown = f.known
    for c in order where !known.contains(c) { allKnown.append(c) }
    return Follow(vid: vid, known: allKnown, fresh: fresh)
}

// ======================= Classements TMDB retrouvés dans le catalogue =======================

struct PopTitle: Codable, Equatable {
    var fr: String
    var orig: String
    var en: String
}

private let normParenRe = Rx(#"\([^)]*\)|\[[^\]]*\]"#)
private let normCountryRe = Rx(#"\s+-\s+[a-z]{2}$"#)
private let normNonAlnumRe = Rx(#"[^a-z0-9]+"#)

/// Titre réduit à l'essentiel pour comparer deux sources : minuscules, sans accents, ponctuation, parenthèses ni suffixe « - FR ».
func normTitle(_ s: String) -> String {
    var t = normParenRe.replace(s.lowercased(), " ").trimmed
    t = normCountryRe.replace(t)
    t = t.folding(options: [.diacriticInsensitive], locale: nil)
    return normNonAlnumRe.replace(t, " ").trimmed
}

/// Retrouve dans le catalogue les titres d'un classement, dans l'ordre du classement (titres normalisés identiques).
func matchPopular(_ pop: [PopTitle], _ items: [Item]) -> [Item] {
    if pop.isEmpty || items.isEmpty { return [] }
    var idx: [String: Item] = [:]
    for i in items where i.poster != nil {
        let n = normTitle(i.name)
        if n.count >= 2 && idx[n] == nil { idx[n] = i }
    }
    var out: [Item] = []
    var seen = Set<String>()
    for p in pop {
        let f = normTitle(p.fr), o = normTitle(p.orig), e = normTitle(p.en)
        // le catalogue nomme souvent les titres « titre français + titre original ou anglais »
        let keys = [f, "\(f) \(e)", "\(f) \(o)", e, o, "\(e) \(f)", "\(o) \(f)"].map { $0.trimmed }.filter { $0.count >= 2 }
        guard let hit = keys.lazy.compactMap({ idx[$0] }).first else { continue }
        if seen.insert(hit.key).inserted { out.append(hit) }
    }
    return out
}

// ======================= Recommandations =======================

/// j'aime = +2, j'adore = +4, je n'aime pas = -3 ; vus / favoris = +1. Poids appliqués aux catégories et aux personnes.
func recoList(pool: [Item], all: [Item], recent: [String], favs: [String], ratings: [String: Int],
              people: (Item) -> String) -> [Item] {
    var w: [String: Int] = [:]
    for k in recent + favs { w[k, default: 0] += 1 }
    for (k, v) in ratings { w[k, default: 0] += v > 0 ? 2 * v : 3 * v }
    let seeds = all.filter { w[$0.key] != nil }
    var catW: [String: Int] = [:]
    var actW: [String: Int] = [:]
    for sd in seeds {
        let x = w[sd.key] ?? 0
        catW[sd.cat, default: 0] += x
        for a in people(sd).split(separator: ",").map({ $0.trimmed.lowercased() }) where !a.isEmpty { actW[a, default: 0] += x }
    }
    let seen = Set(recent + favs).union(ratings.keys)
    let cand = pool.filter { $0.poster != nil && !seen.contains($0.key) }
    if seeds.isEmpty { return Array(cand.shuffled().prefix(15)) }
    let scored = cand.map { c -> (Item, Double) in
        let common = actW.isEmpty ? 0 : people(c).split(separator: ",").reduce(0) { $0 + (actW[$1.trimmed.lowercased()] ?? 0) }
        let cw = Double(min(max(catW[c.cat] ?? 0, -6), 6))
        return (c, cw + 1.5 * Double(min(max(common, -8), 8)) + Double.random(in: 0..<1))
    }
    var keys = Set<String>()
    return scored.sorted { $0.1 > $1.1 }.prefix(15).map(\.0).filter { keys.insert($0.key).inserted }
}
