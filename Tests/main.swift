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

check(Names.cleanEpisode("Lupin S02E03 - Chapitre 3"), "Chapitre 3", "titre d'épisode")
check(Names.cleanEpisode("Épisode 4 |FR"), "Épisode 4", "épisode sans code")
check(Names.cleanCategory("|FR| Action"), "Action", "catégorie avec langue")
check(Names.cleanCategory("|2026| Nouveauté"), "Nouveauté 2026", "catégorie avec année")
check(Names.cleanCategory("Comédie"), "Comédie", "catégorie simple")

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
check(Names.cleanLive("FR: TF1 ᶠᴴᴰ").name, "FR: TF1", "exposants retirés du nom")
check(Names.cleanLive("FR: TF1 ᶠᴴᴰ").q, "FHD", "qualité en exposants")
check(Names.cleanLive("TF1ᴴᴰ").q, "HD", "exposants collés au nom")
check(Names.cleanLive("TF1 HD+").q, "HD", "HD+")
check(Names.cleanLive("TF1 Full HD").q, "FHD", "Full HD")
check(Names.cleanLive("TF1 2160p").q, "4K", "2160p")
let live2 = Names.mergeLive([chan(11, "FR: TF1 ᴴᴰ"), chan(12, "FR: TF1 ᶠᴴᴰ"), chan(13, "FR: TF1 ᵁᴴᴰ"), chan(14, "FR: TF1")])
check(live2.count, 1, "TF1 en exposants regroupée")
check(live2[0].variants.map(\.q), ["FHD", "HD", "?", "4K"], "qualités en exposants")
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

// ---------- fiche de série ----------
let infoJSON = #"""
{"info":{"plot":"Un résumé.","cast":"A, B","director":"C","genre":"Drame","releaseDate":"2021-01-08","backdrop_path":["http://x/b.jpg"],"episode_run_time":"45","tmdb":"96677"},
 "episodes":{"2":[{"id":"902","episode_num":1,"title":"Lupin S02E01 - Chapitre 6","container_extension":"mkv","season":2,"info":{"movie_image":"http://x/e.jpg","duration_secs":2700}}],
             "1":[{"id":"901","episode_num":"1","title":"Lupin S01E01","container_extension":"","info":{"duration":"00:47:10"}}]}}
"""#
let infoObj = try JSONSerialization.jsonObject(with: Data(infoJSON.utf8)) as! [String: Any]
let sinfo = XtreamClient.parseInfo(infoObj, series: true)
check(sinfo.episodes.map(\.id), [901, 902], "épisodes triés par saison")
check(sinfo.seasons, [1, 2], "saisons")
check(sinfo.episodes[1].title, "Chapitre 6", "titre d'épisode nettoyé")
check(sinfo.episodes[0].ext, "mp4", "extension par défaut")
check(sinfo.episodes[1].runtime, 45, "durée d'épisode")
check(sinfo.episodes[0].runtime, 47, "durée hh:mm:ss")
check(sinfo.backdrop, "http://x/b.jpg", "image de fond en tableau")
check(sinfo.tmdb, 96677, "tmdb de la série")
check(sinfo.runtime, 45, "durée moyenne")

// ---------- guide des programmes ----------
let xml = """
<?xml version="1.0" encoding="UTF-8"?>
<tv><channel id="TF1.fr"><display-name>TF1</display-name></channel>
<programme start="20261024200000 +0200" stop="20261024210000 +0200" channel="TF1.fr"><title lang="fr">Journal &amp; météo</title><desc>Infos</desc></programme>
<programme start="20261024210000 +0200" stop="20261024230000 +0200" channel="TF1.fr"><title>Film</title></programme>
<programme start="20261024180000 +0200" stop="20261024190000 +0200" channel="TF1.fr"><title>Passé</title></programme>
</tv>
"""
let at = XMLTVParser.date("20261024203000 +0200")!
let guide = XMLTVParser.parse(Data(xml.utf8), now: at)
check(guide["tf1.fr"]?.count ?? 0, 2, "programmes passés écartés")
let (cur, nxt) = XMLTVParser.nowNext(guide["tf1.fr"], at: at)
check(cur?.title, "Journal & météo", "programme en cours")
check(nxt?.title, "Film", "programme suivant")
check(cur?.desc, "Infos", "description")

// ---------- séries suivies ----------
func ep(_ id: Int, _ s: Int, _ n: Int) -> Episode { Episode(id: id, title: "É\(n)", season: s, num: n, ext: "mkv", image: nil) }
let f0 = Follow(vid: 1, known: ["1:1", "1:2"], fresh: [])
let f1 = updateFollow(f0, vid: 1, eps: [ep(11, 1, 1), ep(12, 1, 2), ep(13, 1, 3), ep(21, 2, 1)]) { _ in false }
check(f1.fresh.map(\.id), [13, 21], "nouveaux épisodes")
check(f1.known.count, 4, "épisodes connus")
let f2 = updateFollow(f1, vid: 1, eps: [ep(11, 1, 1), ep(12, 1, 2), ep(99, 1, 3), ep(21, 2, 1)]) { $0 == 21 }
check(f2.fresh.map(\.id), [99], "identifiant changé suivi, épisode vu retiré")
check(updateFollow(f1, vid: 1, eps: []) { _ in false }, f1, "réponse vide : rien ne change")

// ---------- classements ----------
check(normTitle("L'Été (2023) - FR"), "l ete", "titre normalisé")
let catalogue = [film(1, "Dune : Deuxième partie", poster: "p"), film(2, "Oppenheimer", poster: "p"), film(3, "Sans affiche")]
let pops = matchPopular([PopTitle(fr: "Oppenheimer", orig: "Oppenheimer", en: "Oppenheimer"),
                         PopTitle(fr: "Dune : Deuxième partie", orig: "Dune: Part Two", en: "Dune: Part Two"),
                         PopTitle(fr: "Sans affiche", orig: "", en: "")], catalogue)
check(pops.map(\.id), [2, 1], "classement retrouvé dans l'ordre, sans titre sans affiche")

// ---------- recommandations ----------
var pool: [Item] = []
for n in 0..<40 { var i = film(100 + n, "Film \(n)", poster: "p"); i.cat = n < 10 ? "Action" : "Drame"; pool.append(i) }
let reco = recoList(pool: pool, all: pool, recent: ["vod:100"], favs: [], ratings: ["vod:101": 2], people: { _ in "" })
check(reco.count, 15, "15 recommandations")
check(reco.filter { $0.cat == "Action" }.count >= 8, true, "la catégorie aimée domine")
check(reco.contains { $0.key == "vod:100" || $0.key == "vod:101" }, false, "titres déjà vus ou notés exclus")

// ---------- synchronisation (format Android) ----------
check(syncAccount(host: "http://Exemple.com:8080/", user: " bob "), syncAccount(host: "http://exemple.com:8080", user: "bob"), "empreinte du compte")
check(syncAccount(host: "http://exemple.com:8080", user: "bob").count, 24, "empreinte : 12 octets")
Store.reset()
Store.setProgress("vod:1", pos: 60_000, dur: 600_000)
Store.toggleFav("series:2")
Store.setRating("vod:3", 2)
Store.saveLists(["À voir": ["vod:1"], "Enfants": []], order: ["À voir", "Enfants"])
Store.saveFollows(["series:2": Follow(vid: 2, known: ["1:2", "1:1"], fresh: [NewEp(id: 9, season: 1, num: 3, title: "Trois")])], changed: ["series:2"])
let mine = Store.syncRecords()
func rec(_ k: String) -> SyncRec? { mine.first { $0.k == k } }
check(rec("pos|vod:1")?.v, "60000;600000", "position au format Android")
check(rec("fav|series:2")?.v, "1", "favori")
check(rec("rate|vod:3")?.v, "2", "note")
check(rec("lists")?.v, #"{"À voir":["vod:1"],"Enfants":[]}"#, "listes dans l'ordre")
check(rec("fw|series:2")?.v, #"{"v":2,"k":["1:1","1:2"],"n":[{"i":9,"s":1,"e":3,"t":"Trois"}]}"#, "suivi au format Android")
check((rec("pos|vod:1")?.t ?? 0) > 1, true, "donnée datée")
// un autre appareil : plus récent pour la position, plus ancien pour la note, nouveau favori, liste supprimée
let later = (rec("pos|vod:1")?.t ?? 0) + 1000
let n = Store.applySync([SyncRec(k: "pos|vod:1", t: later, v: "120000;600000"),
                         SyncRec(k: "rate|vod:3", t: 5, v: "-1"),
                         SyncRec(k: "fav|vod:7", t: later, v: "1"),
                         SyncRec(k: "fav|series:2", t: later, v: nil),
                         SyncRec(k: "seen|ep:5", t: 1, v: "1"),
                         SyncRec(k: "hcats", t: later, v: #"["vod|Adultes","live|Radio\/Musique"]"#),
                         SyncRec(k: "fw|series:4", t: later, v: #"{"v":4,"k":["1:1"],"n":[]}"#),
                         SyncRec(k: "inconnue", t: later, v: "x")])
check(n, 6, "changements appliqués")
check(Store.pos("vod:1"), 120_000, "position la plus récente gardée")
check(Store.rating("vod:3"), 2, "note plus ancienne ignorée")
check(Store.favs, ["vod:7"], "favoris fusionnés")
check(Store.seen("ep:5"), true, "donnée d'avant la synchronisation ajoutée")
check(Store.hiddenCats, ["vod|Adultes", "live|Radio/Musique"], "catégories masquées")
check(Store.follows["series:4"]?.vid, 4, "série suivie reçue")
check(Store.applySync(Store.syncRecords()), 0, "renvoyer ses propres données ne change rien")

// ---------- profils ----------
let kid = Profiles.add(name: "Enfants", color: 3)!
Profiles.select(kid.id)
check(Store.pos("vod:1"), 0, "nouveau profil : aucune reprise héritée")
check(Store.favs, [], "nouveau profil : aucun favori hérité")
Store.toggleFav("vod:99")
Store.setProgress("vod:50", pos: 1000, dur: 600_000)
let all1 = Store.syncRecords()
check(all1.contains { $0.k == "fav|vod:99" }, false, "favori d'un profil : pas avec les clés du profil principal")
check(all1.contains { $0.k == "@\(kid.id):fav|vod:99" }, true, "favori d'un profil : clé préfixée « @id: »")
check(all1.first { $0.k == "prof|\(kid.id)" }?.v, #"{"name":"Enfants","color":3,"order":1}"#, "fiche du profil")
check(all1.contains { $0.k == "fav|vod:7" }, true, "profil principal envoyé même depuis un autre profil")
check(all1.contains { $0.k == "@\(kid.id):tmdb" }, false, "clé TMDB seulement avec le profil principal")
Profiles.select(Profiles.mainId)
check(Store.favs, ["vod:7"], "profil principal intact")
check(Store.pos("vod:50"), 0, "reprise propre à chaque profil")
Profiles.delete(kid.id)
check(Profiles.all.count, 1, "profil supprimé")
Profiles.select(kid.id)
check(Profiles.currentId, Profiles.mainId, "profil supprimé : retour au principal")
// la suppression, plus récente, l'emporte sur les anciennes données de ce profil
Store.applySync(all1)
check(Profiles.all.contains { $0.id == kid.id }, false, "profil supprimé : pas recréé par d'anciennes données")
check(Store.syncRecords().contains { $0.k == "prof|\(kid.id)" && $0.v == nil }, true, "suppression transmise")
// un profil créé sur un autre appareil arrive avec ses données
let far: Int64 = 9_999_999_999_999
check(Store.applySync([SyncRec(k: "prof|ab12cd34", t: far, v: #"{"name":"Léa","color":5,"order":1}"#),
                       SyncRec(k: "@ab12cd34:fav|series:8", t: far, v: "1"),
                       SyncRec(k: "@ab12cd34:pos|ep:3", t: far, v: "5000;60000"),
                       SyncRec(k: "@inconnu:fav|vod:1", t: far, v: "1")]), 3, "profil reçu")
check(Profiles.all.first { $0.id == "ab12cd34" }?.name, "Léa", "nom du profil reçu")
check(Store.favs.contains("series:8"), false, "données du profil reçu : pas dans le principal")
Profiles.select("ab12cd34")
check(Store.favs, ["series:8"], "données du profil reçu")
check(Store.pos("ep:3"), 5000, "reprise du profil reçu")
Profiles.select(Profiles.mainId)
Store.applySync([SyncRec(k: "prof|ab12cd34", t: far + 1, v: nil)])
check(Profiles.all.count, 1, "suppression reçue")
check(Profiles.defaults(for: "ab12cd34").stringArray(forKey: "favs") ?? [], [], "données du profil supprimé effacées")
Store.reset()

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
