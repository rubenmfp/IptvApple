// Tests du code commun (noms, regroupement, lecture JSON, lien M3U). Lancés par GitHub sur macOS :
//   swiftc Shared/Core/{Models,Regex,Names,JSONScan,Xtream}.swift Tests/main.swift -o /tmp/core-tests && /tmp/core-tests
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String, line: Int = #line) {
    if got != want {
        failures += 1
        print("ÉCHEC l.\(line) \(label) : obtenu « \(got) », attendu « \(want) »")
    }
}

// ---------- nettoyage des noms ----------
func clean(_ s: String) -> String { Names.clean(s).name }
func qual(_ s: String) -> String { Names.clean(s).q }

check(clean("|SD| Titre (2026 MULTI)"), "Titre", "étiquette + année + MULTI")
check(qual("|SD| Titre (2026 MULTI)"), "SD", "qualité depuis l'étiquette")
check(clean("Le Film (2019) [4K HDR]"), "Le Film", "année + groupe technique")
check(qual("Le Film (2019) [4K HDR]"), "4K", "qualité depuis le groupe")
check(clean("Titre MULTI"), "Titre", "MULTI final")
check(clean("Titre - VOSTFR"), "Titre", "VOSTFR final")
check(clean("Titre | MULTI"), "Titre", "titre court suivi d'une barre")
check(clean("FR| Avatar (2009) FHD"), "Avatar", "préfixe FR| + FHD")
check(qual("FR| Avatar (2009) FHD"), "FHD", "FHD final")
check(clean("Dune: Part Two (2024) (VF - 2024)"), "Dune: Part Two", "groupe (VF - 2024)")
check(clean("MULTI"), "MULTI", "titre entièrement technique : gardé")
check(clean("Les Misérables UHD"), "Les Misérables", "UHD final")
check(qual("Les Misérables UHD"), "4K", "UHD = 4K")
check(clean("  Épisode 3 |FR"), "Épisode 3", "langue derrière une barre")

check(clean("Titre HD"), "Titre", "HD final")
check(qual("Titre HD"), "HD", "qualité HD finale")
check(clean("Titre - SD"), "Titre", "SD final")
check(clean("HD - Titre"), "Titre", "HD en tête")
check(qual("SD: Titre"), "SD", "SD en tête")
check(clean("SD"), "SD", "titre réduit à SD : gardé")
check(clean("Titre HD MULTI"), "Titre", "HD puis MULTI")

// ---------- clé de regroupement ----------
let k = Names.mergeKey("L'Été")
check(Names.mergeKey("L’été"), k, "apostrophe typographique")
check(Names.mergeKey("L'été - FR"), k, "suffixe pays")
check(Names.mergeKey("FR: L'été"), k, "préfixe FR:")
check(Names.mergeKey("L'été VF"), k, "suffixe VF")
check(Names.mergeKey("UK: Eurosport", live: true) == Names.mergeKey("FR: Eurosport", live: true), false, "chaînes de pays différents")
check(Names.searchKey("Élève ÇA"), "eleve ca", "recherche sans accents")

// ---------- regroupement des versions ----------
func film(_ id: Int, _ raw: String, tmdb: Int = 0, year: Int = 0, poster: String? = nil) -> Item {
    let (n, q) = Names.clean(raw)
    return Item(type: "vod", id: id, name: n, poster: poster, cat: "Action", ext: "mkv", variants: [Variant(id: id, ext: "mkv", q: q)], tmdb: tmdb, year: year)
}
let merged = Names.mergeItems([film(1, "|4K| Matrix"), film(2, "|FHD| Matrix", poster: "p"), film(3, "Autre"), film(4, "|SD| Matrix")])
check(merged.count, 2, "Matrix regroupé")
check(merged[0].variants.map(\.q), ["FHD", "4K", "SD"], "ordre des qualités")
check(merged[0].id, 2, "version préférée = FHD")
check(merged[0].poster, "p", "affiche reprise d'une version")
let homonyms = Names.mergeItems([film(10, "Dune", tmdb: 841, year: 1984), film(11, "Dune", tmdb: 438631, year: 2021)])
check(homonyms.map(\.name), ["Dune (1984)", "Dune (2021)"], "homonymes séparés avec l'année")
let wrongIds = Names.mergeItems([film(20, "|HD| Lift", tmdb: 111, year: 2024), film(21, "Lift SD", tmdb: 222, year: 2024)])
check(wrongIds.count, 1, "même année, identifiants TMDB différents : regroupés")
check(wrongIds.first?.variants.map(\.q) ?? [], ["HD", "SD"], "versions HD et SD")
let noYear = Names.mergeItems([film(30, "Lift HD", tmdb: 111), film(31, "Lift SD", tmdb: 222)])
check(noYear.count, 1, "identifiants différents sans année : regroupés")

// ---------- chaînes ----------
check(Names.cleanLive("FR: TF1 FHD (backup)").name, "FR: TF1", "chaîne nettoyée")
check(Names.cleanLive("FR: TF1 FHD (backup)").q, "FHD Secours", "qualité de chaîne")
check(Names.cleanLive("TF1").q, "?", "chaîne sans qualité")
func chan(_ id: Int, _ raw: String) -> Item {
    let (n, q) = Names.cleanLive(raw)
    return Item(type: "live", id: id, name: n, poster: nil, cat: "TNT", ext: "ts", variants: [Variant(id: id, ext: "ts", q: q)])
}
let live = Names.mergeLive([chan(1, "TF1 SD"), chan(2, "TF1 FHD"), chan(3, "TF1 HD"), chan(4, "M6 HD")])
check(live.count, 2, "TF1 regroupée")
check(live[0].variants.map(\.q), ["FHD", "HD", "SD"], "qualités de chaîne")
check(Names.liveGenre(chan(5, "beIN SPORTS 1")), "Sport", "genre Sport")

// ---------- lecture JSON ----------
let json = #"""
[{"num":1,"name":"|FHD| Léon (1994)","stream_id":"101","stream_icon":"http:\/\/img\/a.jpg","rating":"8.5","category_id":3,"container_extension":"mkv","tmdb":"101","added":null,"extra":{"a":[1,2,{"b":"]"}]}},
 {"num":2,"name":"Emoji 🎬","stream_id":102,"stream_icon":"","rating":null,"category_id":"9","container_extension":null,"year":"2020-05-01"},
 "intrus", 42]
"""#
let items = try XtreamClient.parseStreams(Data(json.utf8), type: "vod", cats: ["3": "Action"])
check(items.count, 2, "deux contenus lus")
check(items[0].name, "Léon", "échappement \\u00e9")
check(items[0].id, 101, "identifiant en texte")
check(items[0].poster, "http://img/a.jpg", "échappement \\/")
check(items[0].rating, 8.5, "note en texte")
check(items[0].year, 1994, "année tirée du nom")
check(items[0].tmdb, 101, "tmdb")
check(items[0].cat, "Action", "catégorie")
check(items[1].name, "Emoji 🎬", "paire de substitution")
check(items[1].cat, "Divers", "catégorie inconnue")
check(items[1].ext, "mp4", "extension par défaut")
check(items[1].year, 2020, "année depuis year")
check(items[1].poster, nil, "affiche vide")
let keyed = #"{"1":{"series_id":7,"name":"Série A","cover":"c.jpg","category_id":"1","cast":"X","director":"Y"},"2":{"series_id":8,"name":"Série B"}}"#
let ser = try XtreamClient.parseStreams(Data(keyed.utf8), type: "series", cats: [:])
check(ser.map(\.id), [7, 8], "liste en objet indexé")
check(ser[0].people, "X, Y", "distribution")
check(ser[0].poster, "c.jpg", "cover")
var threw = false
do { _ = try XtreamClient.parseStreams(Data(#"{"user_info":{"auth":0}}"#.utf8), type: "vod", cats: [:]) } catch { threw = true }
check(threw, true, "objet sans contenu = erreur")

// ---------- lien M3U ----------
let l1 = Xtream.parseLink("http://ex.com:8080/get.php?username=ab%40c&password=p+q&type=m3u_plus&output=ts")
check(l1?.host, "http://ex.com:8080", "serveur du lien")
check(l1?.user, "ab@c", "utilisateur décodé")
check(l1?.pass, "p+q", "« + » gardé")
let l2 = Xtream.parseLink("ex.com:8080/movie/jean/secret/12.mkv")
check(l2?.host, "http://ex.com:8080", "http ajouté")
check(l2?.user, "jean", "utilisateur depuis un flux")
check(l2?.pass, "secret", "mot de passe depuis un flux")
check(Xtream.parseLink("bonjour") == nil, true, "lien non reconnu")
check(Xtream.normalizeHost("ex.com:8080/"), "http://ex.com:8080", "serveur normalisé")
check(Xtream.normalizeHost("https://ex.com/player_api.php?x=1"), "https://ex.com", "player_api retiré")

// ---------- performance : 40 000 titres ----------
var big = "["
for n in 0..<40_000 { big += (n > 0 ? "," : "") + #"{"name":"|FHD| Titre \#(n % 20000) (20\#(10 + n % 10)) MULTI","stream_id":\#(n + 1),"stream_icon":"http://x/\#(n).jpg","category_id":"\#(n % 30)","rating":"7.1"}"# }
big += "]"
let t0 = Date()
let parsed = try XtreamClient.parseStreams(Data(big.utf8), type: "vod", cats: [:])
let t1 = Date()
let m = Names.mergeItems(parsed)
let t2 = Date()
print("40 000 titres : lecture \(Int(t1.timeIntervalSince(t0) * 1000)) ms, regroupement \(Int(t2.timeIntervalSince(t1) * 1000)) ms -> \(m.count) affiches")
check(m.count, 20_000, "regroupement de masse")

if failures > 0 { print("\(failures) échec(s)"); exit(1) }
print("Tous les tests passent.")
