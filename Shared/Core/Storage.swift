import Foundation
import Security

/// Identifiants Xtream dans le trousseau de l'appareil (jamais dans un fichier ni dans le code).
enum Keychain {
    private static let service = "IptvTV"
    private static let accountKey = "xtream"

    private static func base() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: accountKey]
    }

    static func load() -> XtreamAccount? {
        var q = base()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(XtreamAccount.self, from: d)
    }

    @discardableResult
    static func save(_ a: XtreamAccount) -> Bool {
        guard let d = try? JSONEncoder().encode(a) else { return false }
        SecItemDelete(base() as CFDictionary)
        var q = base()
        q[kSecValueData as String] = d
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() { SecItemDelete(base() as CFDictionary) }
}

/// Fichiers de l'appli : catalogue enregistré (dossier Application Support, conservé entre les lancements).
enum Files {
    static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IptvTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var catalog: URL { dir.appendingPathComponent("catalog.json") }
    static var status: URL { dir.appendingPathComponent("status.json") }
    static var people: URL { dir.appendingPathComponent("people.json") }

    static func save<T: Encodable>(_ v: T, to u: URL) {
        guard let d = try? JSONEncoder().encode(v) else { return }
        try? d.write(to: u, options: .atomic)
    }

    static func load<T: Decodable>(_ t: T.Type, from u: URL) -> T? {
        guard let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(t, from: d)
    }

    static func removeAll() { try? FileManager.default.removeItem(at: dir) }
}

/// Réglages simples (pas d'identifiants ici).
enum Prefs {
    /// Rotation pendant la lecture sur iPhone : 0 = paysage (défaut), 1 = suit le téléphone, 2 = portrait.
    static var rotation: Int {
        get { Store.defaults.integer(forKey: "rotation") }
        set { Store.defaults.set(newValue, forKey: "rotation") }
    }

    /// Format d'image choisi en dernier sur iPhone (vide = « Plein écran »).
    static var aspect: String {
        get { Store.defaults.string(forKey: "aspect") ?? "" }
        set { Store.defaults.set(newValue, forKey: "aspect") }
    }

    /// Guide des programmes : chargé automatiquement à l'ouverture du Direct ; adresse personnalisée (vide = celle du fournisseur).
    static var epgAuto: Bool {
        get { UserDefaults.standard.bool(forKey: "epgAuto") }
        set { UserDefaults.standard.set(newValue, forKey: "epgAuto") }
    }
    static var epgUrl: String {
        get { UserDefaults.standard.string(forKey: "epgUrl") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "epgUrl") }
    }

    /// Synchronisation par le Wi-Fi : active ou non, adresse d'un appareil saisie à la main, identifiant de cet appareil.
    static var syncOn: Bool {
        get { UserDefaults.standard.object(forKey: "syncOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "syncOn") }
    }
    static var syncPeer: String {
        get { UserDefaults.standard.string(forKey: "syncPeer") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "syncPeer") }
    }
    static var deviceId: String {
        if let v = UserDefaults.standard.string(forKey: "devid") { return v }
        let v = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(v, forKey: "devid")
        return v
    }

    /// Rendu sonore du lecteur : 0 = normal, 1 = basses, 2 = dialogues, 3 = cinéma ; + volume amplifié.
    static var fxPreset: Int {
        get { Store.defaults.integer(forKey: "fxp") }
        set { Store.defaults.set(newValue, forKey: "fxp") }
    }
    static var fxBoost: Bool {
        get { Store.defaults.bool(forKey: "fxb") }
        set { Store.defaults.set(newValue, forKey: "fxb") }
    }
    /// Diagnostic du lecteur (en bas des réglages) : dernière lecture réussie, dernière erreur.
    static var playerNote: String {
        get { UserDefaults.standard.string(forKey: "pnote") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "pnote") }
    }
    static var playerErr: String {
        get { UserDefaults.standard.string(forKey: "perr") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "perr") }
    }

    static var refreshDays: Int {
        get { let v = UserDefaults.standard.integer(forKey: "refreshDays"); return (1...5).contains(v) ? v : 1 }
        set { UserDefaults.standard.set(newValue, forKey: "refreshDays") }
    }
}
