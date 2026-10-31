import Foundation
import UIKit

/// Synchronisation par GitHub, compatible avec l'appli Android IptvTV (format décrit dans docs/SYNC.md).
///
/// Les appareils partagent un fichier dans un dépôt GitHub **privé** de l'utilisateur : `iptvtv/<empreinte du compte>.json`,
/// avec les mêmes enregistrements que la synchronisation Wi-Fi ([clé, date_ms, valeur|null], la plus récente l'emporte).
/// Chaque synchronisation : lecture du fichier, application chez soi, puis, si l'appareil a du plus récent, envoi de la
/// fusion (avec le « sha » lu : si un autre appareil a écrit entre-temps, on recommence). La clé TMDB et les identifiants
/// Xtream ne sont jamais envoyés. Le jeton GitHub reste dans le trousseau de l'appareil.
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    @Published private(set) var info = ""
    @Published private(set) var busy = false
    /// Données reçues : l'appli relit ce qui est partagé.
    var onApplied: (() -> Void)?

    private var acct = ""
    private var observer: NSObjectProtocol?
    private var pushTask: Task<Void, Never>?
    private var loop: Task<Void, Never>?
    private var dirty = false
    private var again = false

    // MARK: - Réglages

    /// « pseudo/depot » (une adresse https://github.com/pseudo/depot est acceptée).
    static var repo: String {
        var r = Prefs.ghRepo.trimmed
        for p in ["https://github.com/", "http://github.com/", "github.com/"] where r.lowercased().hasPrefix(p) { r = String(r.dropFirst(p.count)) }
        if r.hasSuffix(".git") { r = String(r.dropLast(4)) }
        while r.hasSuffix("/") { r.removeLast() }
        return r
    }
    static var token: String { Secret.get("ghtoken").trimmed }
    static var configured: Bool { repo.split(separator: "/").count == 2 && !token.isEmpty }

    func configure(repo: String, token: String?) {
        Prefs.ghRepo = repo.trimmed
        if let t = token, !t.trimmed.isEmpty { Secret.set("ghtoken", t.trimmed) }
        info = ""
        if !acct.isEmpty { syncNow() }
    }

    func forget() {
        Secret.set("ghtoken", "")
        info = "Jeton effacé : synchronisation par GitHub arrêtée."
    }

    // MARK: - Démarrage, arrêt

    /// Appli au premier plan : synchronisation tout de suite, puis toutes les 5 minutes et 1 minute après chaque modification.
    func start(account: XtreamAccount) {
        let a = syncAccount(host: account.host, user: account.user)
        if loop != nil && a == acct { return }
        stop(flush: false)
        acct = a
        observer = NotificationCenter.default.addObserver(forName: Store.changed, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CloudSync.shared.changed() }
        }
        loop = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            while !Task.isCancelled {
                await sync()
                try? await Task.sleep(nanoseconds: 300_000_000_000)
            }
        }
    }

    /// Appli en arrière-plan (`flush`) : les dernières modifications partent avant la mise en veille.
    func stop(flush: Bool) {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
        loop?.cancel(); loop = nil
        pushTask?.cancel(); pushTask = nil
        guard flush, dirty, Self.configured, !acct.isEmpty else { return }
        let app = UIApplication.shared
        var id = UIBackgroundTaskIdentifier.invalid
        id = app.beginBackgroundTask(withName: "synchro") { app.endBackgroundTask(id) }
        let tid = id
        Task {
            await sync()
            app.endBackgroundTask(tid)
        }
    }

    func syncNow() { Task { await sync() } }

    private func changed() {
        dirty = true
        guard Self.configured, pushTask == nil, loop != nil else { return }
        pushTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            pushTask = nil
            if !Task.isCancelled { await sync() }
        }
    }

    // MARK: - Synchronisation

    private struct Remote { var recs: [SyncRec]; var sha: String? }
    private struct Failure: Error { let text: String }
    private struct Conflict: Error {}

    func sync() async {
        guard Self.configured, !acct.isEmpty else { return }
        if busy { again = true; return }
        busy = true
        defer {
            busy = false
            if again { again = false; Task { await sync() } }
        }
        dirty = false
        do {
            for _ in 0..<3 {
                let remote = try await fetch()
                let received = remote.recs.filter { $0.k != "tmdb" }
                let n = received.isEmpty ? 0 : Store.applySync(received)
                if n > 0 { onApplied?() }
                let local = Store.syncRecords().filter { $0.k != "tmdb" }
                let merged = Store.mergeRecords(received, local)
                var sent = false
                if merged != received.sorted(by: { $0.k < $1.k }) {
                    do { try await upload(merged, sha: remote.sha); sent = true } catch is Conflict { continue }
                }
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                info = "Synchronisé à \(f.string(from: Date()))"
                    + (n == 0 ? "" : " · \(n) élément(s) reçu(s)") + (sent ? " · envoyé" : (n == 0 ? " · déjà à jour" : ""))
                return
            }
            info = "Échec : le fichier change trop vite, nouvel essai plus tard."
            dirty = true
        } catch let e as Failure {
            info = "Échec : " + e.text
            dirty = true
        } catch {
            info = "Échec : " + error.localizedDescription
            dirty = true
        }
    }

    private var fileURL: URL? {
        URL(string: "https://api.github.com/repos/\(Self.repo)/contents/iptvtv/\(acct).json")
    }

    private func request(_ url: URL, method: String = "GET", body: Data? = nil,
                         accept: String = "application/vnd.github+json") async throws -> (Data, Int) {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        r.httpMethod = method
        r.setValue("Bearer \(Self.token)", forHTTPHeaderField: "Authorization")
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("IptvApple", forHTTPHeaderField: "User-Agent")
        if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (d, resp) = try await URLSession.shared.data(for: r)
        return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func explain(_ code: Int) -> String {
        switch code {
        case 401: return "jeton refusé (expiré ou mal recopié)."
        case 403: return "le jeton n'a pas le droit d'écrire (permission « Contents : Read and write »)."
        case 404: return "dépôt introuvable, ou le jeton n'y a pas accès."
        default: return "erreur \(code) de GitHub."
        }
    }

    private func fetch() async throws -> Remote {
        guard let url = fileURL else { throw Failure(text: "nom de dépôt invalide.") }
        let (d, code) = try await request(url)
        if code == 404 {
            // fichier pas encore créé… ou dépôt inaccessible : on vérifie le dépôt
            guard let ru = URL(string: "https://api.github.com/repos/\(Self.repo)") else { throw Failure(text: "nom de dépôt invalide.") }
            let (_, rc) = try await request(ru)
            if rc == 200 { return Remote(recs: [], sha: nil) }
            throw Failure(text: Self.explain(rc == 0 ? 404 : rc))
        }
        guard code == 200, let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { throw Failure(text: Self.explain(code)) }
        let sha = o["sha"] as? String
        var file: Data?
        if (o["encoding"] as? String) == "base64", let c = o["content"] as? String, !c.isEmpty {
            file = Data(base64Encoded: c, options: .ignoreUnknownCharacters)
        } else if ((o["size"] as? NSNumber)?.intValue ?? 0) > 0 {
            // fichier de plus de 1 Mo : contenu brut
            let (raw, rc) = try await request(url, accept: "application/vnd.github.raw")
            guard rc == 200 else { throw Failure(text: Self.explain(rc)) }
            file = raw
        }
        guard let fd = file, !fd.isEmpty else { return Remote(recs: [], sha: sha) }
        guard let j = (try? JSONSerialization.jsonObject(with: fd)) as? [String: Any] else { return Remote(recs: [], sha: sha) }
        if let a = j["acct"] as? String, a != acct { throw Failure(text: "le fichier appartient à un autre compte Xtream.") }
        return Remote(recs: Store.parseRecords(j["recs"]), sha: sha)
    }

    private func upload(_ recs: [SyncRec], sha: String?) async throws {
        guard let url = fileURL else { throw Failure(text: "nom de dépôt invalide.") }
        let dev: String = {
            #if os(tvOS)
            return "Apple TV"
            #else
            return "iPhone"
            #endif
        }()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let file: [String: Any] = ["v": 1, "acct": acct, "dev": dev, "updated": NSNumber(value: now), "recs": Store.recordsJSON(recs)]
        let fd = try JSONSerialization.data(withJSONObject: file)
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm"
        var body: [String: Any] = ["message": "Synchro \(dev) \(f.string(from: Date()))", "content": fd.base64EncodedString()]
        if let sha { body["sha"] = sha }
        let (_, code) = try await request(url, method: "PUT", body: try JSONSerialization.data(withJSONObject: body))
        if code == 409 || code == 422 { throw Conflict() }
        guard code == 200 || code == 201 else { throw Failure(text: Self.explain(code)) }
    }

    /// Réglages : vérifie le dépôt et le jeton, puis synchronise.
    func test() async -> String {
        guard Self.configured else { return "Indiquez le dépôt (pseudo/depot) et le jeton." }
        guard let ru = URL(string: "https://api.github.com/repos/\(Self.repo)") else { return "Nom de dépôt invalide." }
        do {
            let (d, rc) = try await request(ru)
            guard rc == 200 else { return "Échec : " + Self.explain(rc) }
            let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            let priv = o?["private"] as? Bool ?? false
            let push = ((o?["permissions"] as? [String: Any])?["push"] as? Bool) ?? true
            if !push { return "Échec : " + Self.explain(403) }
            if acct.isEmpty { return "Dépôt et jeton corrects." + (priv ? "" : " Attention : ce dépôt est public, rendez-le privé.") }
            await sync()
            return (priv ? "" : "Attention : ce dépôt est public, rendez-le privé. ") + info
        } catch {
            return "Échec : " + error.localizedDescription
        }
    }
}
