import Foundation
import Network
import UIKit

/// Synchronisation par le Wi-Fi de la maison, sans compte, compatible avec l'appli Android IptvTV.
/// Chaque appareil garde toutes ses données. Quand deux appareils ont l'appli ouverte sur le même réseau (et le même compte
/// Xtream), ils échangent leurs données partagées et gardent, pour chacune, la modification la plus récente
/// (voir Store.syncRecords / Store.applySync).
///
/// Chaque appareil annonce le service « _iptvtv._tcp » (découverte automatique) et écoute sur le port 38472.
/// Échange : une ligne JSON envoyée, une ligne JSON reçue en retour ({"v":1,"acct":…,"dev":…,"recs":[[clé, date, valeur], …]}).
/// Les identifiants du fournisseur ne circulent jamais : « acct » est une empreinte du serveur et de l'utilisateur.
@MainActor
final class LanSync: ObservableObject {
    static let shared = LanSync()
    static let port: UInt16 = 38472
    private static let type = "_iptvtv._tcp"

    /// Appareils trouvés sur le réseau : nom -> adresse.
    @Published private(set) var peers: [String: NWEndpoint] = [:]
    /// Appareils avec lesquels un échange a réussi : adresse ou nom -> modèle.
    @Published private(set) var devices: [String: String] = [:]
    @Published private(set) var info = ""
    @Published private(set) var running = false
    /// Données reçues d'un autre appareil : l'appli relit ce qui est partagé.
    var onApplied: (() -> Void)?

    private var acct = ""
    private var name = ""
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var pushTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var applying = false
    private let queue = DispatchQueue(label: "lansync")


    private var deviceName: String {
        #if os(tvOS)
        return "Apple TV"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    // MARK: - Démarrage, arrêt

    func start(account: XtreamAccount) {
        let a = syncAccount(host: account.host, user: account.user)
        if running && a == acct { return }
        stop()
        acct = a
        name = "IptvTV-" + String(Prefs.deviceId.prefix(6))
        running = true
        observer = NotificationCenter.default.addObserver(forName: Store.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        listen()
        browse()
        let manual = Prefs.syncPeer.trimmed
        if !manual.isEmpty {
            Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await syncWith(manual) }
        }
    }

    func stop() {
        running = false
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
        pushTask?.cancel(); pushTask = nil
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        peers = [:]
    }

    /// Une donnée a changé ici : envoi aux autres appareils peu après (regroupé, au plus toutes les 20 s).
    private func schedule() {
        guard running, !applying, pushTask == nil else { return }
        pushTask = Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            pushTask = nil
            if !Task.isCancelled { syncAll() }
        }
    }

    /// Synchronise avec tous les appareils connus (trouvés sur le réseau ou saisis à la main).
    func syncAll() {
        let manual = Prefs.syncPeer.trimmed
        if peers.isEmpty && manual.isEmpty { info = "Aucun autre appareil trouvé pour le moment."; return }
        for (n, e) in peers { Task { await exchange(e, label: n) } }
        if !manual.isEmpty { Task { await syncWith(manual) } }
    }

    /// Échange avec un appareil saisi à la main : « 192.168.1.20 » ou « 192.168.1.20:38472 ».
    func syncWith(_ target: String) async {
        let parts = target.trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        guard let host = parts.first, !host.isEmpty else { return }
        let port = parts.count > 1 ? UInt16(parts[1].trimmed) ?? Self.port : Self.port
        await exchange(.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 38472), label: host)
    }

    // MARK: - Messages

    private func message() -> String {
        let recs = Store.recordsJSON(Store.syncRecords())
        let o: [String: Any] = ["v": 1, "acct": acct, "dev": deviceName, "recs": recs]
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    private static func records(_ o: [String: Any]) -> [SyncRec] { Store.parseRecords(o["recs"]) }

    private func receive(_ o: [String: Any]) -> Int {
        applying = true
        let n = Store.applySync(Self.records(o))
        applying = false
        if n > 0 { onApplied?() }
        return n
    }

    private func done(_ dev: String, from: String, received n: Int) {
        devices[from] = dev
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        info = "Synchronisé avec \(dev) à \(f.string(from: Date()))" + (n == 0 ? " · déjà à jour" : " · \(n) élément(s) reçu(s)")
    }

    private static func parse(_ line: String) -> [String: Any]? {
        guard let d = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    // MARK: - Côté client

    private func exchange(_ endpoint: NWEndpoint, label: String) async {
        guard running else { return }
        let c = NWConnection(to: endpoint, using: .tcp)
        defer { c.cancel() }
        do {
            try await LineIO.ready(c, queue: queue, timeout: 5)
            queue.asyncAfter(deadline: .now() + 30) { c.cancel() }
            try await LineIO.send(c, message())
            let reply = try await LineIO.readLine(c)
            guard let o = Self.parse(reply) else { throw LineIO.Failure("réponse illisible") }
            if o["err"] != nil { info = "L'appareil \(label) utilise un autre compte Xtream : pas de synchronisation."; return }
            let n = receive(o)
            done((o["dev"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? label, from: label, received: n)
        } catch {
            info = "Échec avec \(label) : " + String(LineIO.describe(error).prefix(80))
        }
    }

    // MARK: - Côté serveur

    private func listen() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = (try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)) ?? (try? NWListener(using: params))
        guard let l else { info = "Synchronisation indisponible : réseau inaccessible."; return }
        l.service = NWListener.Service(name: name, type: Self.type)
        // (objet unique : on passe par LanSync.shared plutôt que de capturer self dans les rappels réseau)
        l.newConnectionHandler = { c in
            Task { @MainActor in await LanSync.shared.serve(c) }
        }
        l.stateUpdateHandler = { st in
            if case .failed = st {
                Task { @MainActor in
                    let me = LanSync.shared
                    if me.running { me.info = "Synchronisation : le port 38472 n'a pas pu être ouvert." }
                }
            }
        }
        l.start(queue: queue)
        listener = l
    }

    private func serve(_ c: NWConnection) async {
        defer { c.cancel() }
        do {
            try await LineIO.ready(c, queue: queue, timeout: 5)
            queue.asyncAfter(deadline: .now() + 30) { c.cancel() }
            let line = try await LineIO.readLine(c)
            guard running, let o = Self.parse(line) else { return }
            if (o["acct"] as? String) != acct { try await LineIO.send(c, "{\"err\":\"acct\"}"); return }
            let n = receive(o)
            try await LineIO.send(c, message())
            var from = "un appareil"
            if case let .hostPort(h, _) = c.endpoint { from = "\(h)" }
            done((o["dev"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? from, from: from, received: n)
        } catch {}
    }

    // MARK: - Découverte

    private func browse() {
        let b = NWBrowser(for: .bonjour(type: Self.type, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { results, _ in
            var all: [String: NWEndpoint] = [:]
            for r in results {
                if case let .service(n, _, _, _) = r.endpoint, n.hasPrefix("IptvTV-") { all[n] = r.endpoint }
            }
            let snapshot = all
            Task { @MainActor in LanSync.shared.found(snapshot) }
        }
        b.start(queue: queue)
        browser = b
    }

    private func found(_ all: [String: NWEndpoint]) {
        guard running else { return }
        let others = all.filter { $0.key != name }
        let new = others.keys.filter { peers[$0] == nil }
        peers = others
        for n in new { if let e = others[n] { Task { await exchange(e, label: n) } } }
    }

    // MARK: - Adresse de cet appareil (à saisir sur l'autre appareil si la découverte automatique échoue)

    nonisolated static func localIP() -> String {
        var addr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addr) == 0, let first = addr else { return "inconnue" }
        defer { freeifaddrs(addr) }
        var best: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard let sa = i.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), (i.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  (i.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let s = String(cString: host)
                let nameIf = String(cString: i.ifa_name)
                let local = s.hasPrefix("192.168.") || s.hasPrefix("10.") || s.range(of: #"^172\.(1[6-9]|2\d|3[01])\."#, options: .regularExpression) != nil
                if local && (nameIf == "en0" || best == nil) { best = s }
            }
        }
        return best ?? "inconnue"
    }
}

/// Lecture et écriture d'une ligne de texte sur une connexion réseau.
enum LineIO {
    struct Failure: Error { let text: String; init(_ t: String) { text = t } }

    static func describe(_ e: Error) -> String {
        if let f = e as? Failure { return f.text }
        if let n = e as? NWError {
            switch n {
            case .posix(let c) where c == .ECONNREFUSED: return "connexion refusée (appli fermée ?)"
            case .posix(let c) where c == .ECANCELED: return "pas de réponse"
            default: return n.localizedDescription
            }
        }
        return e.localizedDescription
    }

    /// Reprise unique d'une attente (les rappels réseau peuvent arriver plusieurs fois).
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ f: () -> Void) {
            lock.lock(); defer { lock.unlock() }
            if done { return }
            done = true
            f()
        }
    }

    static func ready(_ c: NWConnection, queue: DispatchQueue, timeout: Double) async throws {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            let once = Once()
            c.stateUpdateHandler = { st in
                switch st {
                case .ready: once.run { k.resume() }
                case .failed(let e), .waiting(let e): once.run { k.resume(throwing: e) }
                case .cancelled: once.run { k.resume(throwing: Failure("pas de réponse")) }
                default: break
                }
            }
            c.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { once.run { k.resume(throwing: Failure("appareil injoignable")) } }
        }
    }

    static func send(_ c: NWConnection, _ s: String) async throws {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            c.send(content: Data((s + "\n").utf8), completion: .contentProcessed { e in
                if let e { k.resume(throwing: e) } else { k.resume() }
            })
        }
    }

    private struct Chunk { var data: Data?; var complete: Bool }

    private static func receive(_ c: NWConnection) async throws -> Chunk {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Chunk, Error>) in
            c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, complete, e in
                if let e { k.resume(throwing: e) } else { k.resume(returning: Chunk(data: data, complete: complete)) }
            }
        }
    }

    static func readLine(_ c: NWConnection, limit: Int = 64 << 20) async throws -> String {
        var buf = Data()
        while true {
            let ch = try await receive(c)
            if let d = ch.data { buf.append(d) }
            if let i = buf.firstIndex(of: 10) { return String(decoding: buf[buf.startIndex..<i], as: UTF8.self) }
            if ch.complete {
                if buf.isEmpty { throw Failure("pas de réponse") }
                return String(decoding: buf, as: UTF8.self)
            }
            if buf.count > limit { throw Failure("message trop long") }
        }
    }
}
