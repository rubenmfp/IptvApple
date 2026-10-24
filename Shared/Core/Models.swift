import Foundation

/// Une version d'un contenu (même titre en 4K, FHD, HD, SD…).
struct Variant: Codable, Hashable {
    var id: Int
    var ext: String
    var q: String
}

/// Un contenu du catalogue (film, série ou chaîne). `tmdb` et `year` servent à ne pas regrouper deux homonymes différents.
struct Item: Codable, Hashable {
    var type: String            // "vod", "series" ou "live"
    var id: Int
    var name: String
    var poster: String?
    var cat: String
    var ext: String
    var rating: Double = 0
    var people: String = ""
    var variants: [Variant] = []
    var epg: String = ""
    var tmdb: Int = 0
    var year: Int = 0

    /// Clé stable, identique à celle de l'appli Android : « vod:123 », « series:45 », « live:678 ».
    var key: String { "\(type):\(id)" }
}

/// Compte Xtream saisi sur l'appareil. Gardé uniquement dans le trousseau.
struct XtreamAccount: Codable, Equatable {
    var host: String
    var user: String
    var pass: String
}

/// Catalogue enregistré sur l'appareil (films et séries), affiché tout de suite au démarrage.
struct Catalog: Codable {
    var vod: [Item]
    var series: [Item]
    var vodCats: [String]
    var serCats: [String]
    var date: Date
}

/// Épisode d'une série.
struct Episode: Codable, Hashable {
    var id: Int
    var title: String
    var season: Int
    var num: Int
    var ext: String
    var image: String?
    var plot: String = ""
    var runtime: Int = 0          // minutes
    var key: String { "ep:\(id)" }
}

/// Fiche détaillée (get_vod_info / get_series_info).
struct ItemInfo: Codable {
    var plot: String = ""
    var cast: String = ""
    var director: String = ""
    var genre: String = ""
    var rating: String = ""
    var releaseDate: String = ""
    var backdrop: String?
    var episodes: [Episode] = []
    var ext: String = ""
    var tmdb: Int = 0
    var runtime: Int = 0          // minutes

    var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }
}
