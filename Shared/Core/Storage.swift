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
        get { UserDefaults.standard.integer(forKey: "rotation") }
        set { UserDefaults.standard.set(newValue, forKey: "rotation") }
    }

    /// Format d'image choisi en dernier sur iPhone (vide = « Plein écran »).
    static var aspect: String {
        get { UserDefaults.standard.string(forKey: "aspect") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "aspect") }
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

    static var refreshDays: Int {
        get { let v = UserDefaults.standard.integer(forKey: "refreshDays"); return (1...5).contains(v) ? v : 1 }
        set { UserDefaults.standard.set(newValue, forKey: "refreshDays") }
    }
}
