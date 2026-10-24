#if os(iOS)
import Foundation
import UIKit

/// Un téléchargement (film ou épisode). Les adresses ne sont pas enregistrées (elles contiennent les identifiants) :
/// elles sont recalculées au moment de télécharger.
struct DLEntry: Codable, Equatable {
    enum State: String, Codable { case queued, downloading, paused, done, failed }

    var key: String              // « vod:123 » ou « ep:456 » : même clé que la lecture en ligne (reprise partagée)
    var kind: String             // "vod" ou "series"
    var id: Int                  // identifiant du flux (film) ou de l'épisode
    var ext: String
    var title: String
    var subtitle: String = ""
    var poster: String?
    var seriesId: Int?
    var seriesName: String?
    var season: Int = 0
    var num: Int = 0
    var state: State = .queued
    var bytes: Int64 = 0
    var total: Int64 = 0
    var file: String?
    var error: String?
    var added = Date()

    var progress: Double { total > 0 ? min(1, Double(bytes) / Double(total)) : 0 }
}

/// Téléchargements sur iPhone : un à la fois (l'abonnement n'autorise qu'une connexion), en arrière-plan,
/// mis en pause pendant une lecture en ligne puis repris.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var entries: [DLEntry] = []
    /// Adresses possibles d'un téléchargement (fournies par l'appli : serveur, extensions de repli).
    var urlsFor: ((DLEntry) -> [URL])?
    /// Fin des événements d'arrière-plan (à appeler pour iOS).
    var backgroundCompletion: (() -> Void)?

    private var current: String?
    private var candidates: [URL] = []
    private var candidateIndex = 0
    private var task: URLSessionDownloadTask?
    private var pausedForStreaming = false
    private var lastPublish = Date.distantPast

    static let dir: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IptvTV-Telechargements", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        var uu = u
        try? uu.setResourceValues(v)
        return u
    }()
    private var indexFile: URL { Self.dir.appendingPathComponent("telechargements.json") }

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: "com.rubenmfp.iptvapple.telechargements")
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        c.allowsCellularAccess = true
        c.timeoutIntervalForRequest = 60
        return URLSession(configuration: c, delegate: self, delegateQueue: .main)
    }()

    private override init() {
        super.init()
        if let d = try? Data(contentsOf: indexFile), let l = try? JSONDecoder().decode([DLEntry].self, from: d) {
            entries = l.map { e in
                var e = e
                if e.state == .downloading { e.state = .queued }      // reprise après un redémarrage de l'appli
                return e
            }
        }
        // téléchargement encore en cours dans la session d'arrière-plan : on le reprend en main
        session.getAllTasks { tasks in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DownloadManager.shared.reattach(tasks) }
            }
        }
    }

    private func reattach(_ tasks: [URLSessionTask]) {
        if let t = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(where: { $0.state == .running }),
           let k = t.taskDescription, let i = entries.firstIndex(where: { $0.key == k }) {
            task = t
            current = k
            entries[i].state = .downloading
        } else {
            tasks.forEach { $0.cancel() }
        }
        next()
    }

    // MARK: - Consultation

    func entry(_ key: String) -> DLEntry? { entries.first { $0.key == key } }

    /// Fichier local d'un contenu téléchargé.
    func localURL(_ key: String) -> URL? {
        guard let e = entry(key), e.state == .done, let f = e.file else { return nil }
        let u = Self.dir.appendingPathComponent(f)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    var usedBytes: Int64 {
        entries.filter { $0.state == .done }.reduce(0) { $0 + $1.total }
    }

    var freeBytes: Int64 {
        let v = try? Self.dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: - Actions

    func add(_ e: DLEntry) {
        guard entry(e.key) == nil else { return }
        entries.append(e)
        save()
        next()
    }

    func pause(_ key: String) {
        guard let i = entries.firstIndex(where: { $0.key == key }) else { return }
        if current == key { stopCurrent(keepResume: true) }
        entries[i].state = .paused
        save()
        next()
    }

    func resume(_ key: String) {
        guard let i = entries.firstIndex(where: { $0.key == key }), entries[i].state != .done else { return }
        entries[i].state = .queued
        entries[i].error = nil
        save()
        next()
    }

    func remove(_ key: String) {
        if current == key { stopCurrent(keepResume: false) }
        if let e = entry(key) {
            if let f = e.file { try? FileManager.default.removeItem(at: Self.dir.appendingPathComponent(f)) }
            try? FileManager.default.removeItem(at: resumeFile(e.key))
        }
        entries.removeAll { $0.key == key }
        save()
        next()
    }

    /// Lecture en ligne : le téléchargement en cours s'arrête (une seule connexion), il reprendra après.
    func suspendForStreaming() {
        pausedForStreaming = true
        if let k = current, let i = entries.firstIndex(where: { $0.key == k }) {
            stopCurrent(keepResume: true)
            entries[i].state = .queued
            save()
        }
    }

    func resumeAfterStreaming() {
        pausedForStreaming = false
        next()
    }

    // MARK: - File d'attente

    private func next() {
        guard current == nil, !pausedForStreaming, let i = entries.firstIndex(where: { $0.state == .queued }) else { return }
        let e = entries[i]
        candidates = urlsFor?(e) ?? []
        candidateIndex = 0
        guard !candidates.isEmpty else { return }       // compte pas encore prêt : on réessaiera
        current = e.key
        entries[i].state = .downloading
        save()
        start(e)
    }

    private func start(_ e: DLEntry) {
        let t: URLSessionDownloadTask
        if let rd = try? Data(contentsOf: resumeFile(e.key)) {
            t = session.downloadTask(withResumeData: rd)
            try? FileManager.default.removeItem(at: resumeFile(e.key))
        } else {
            t = session.downloadTask(with: candidates[candidateIndex])
        }
        t.taskDescription = e.key
        task = t
        t.resume()
    }

    private func stopCurrent(keepResume: Bool) {
        guard let t = task, let k = current else { return }
        let rf = resumeFile(k)
        task = nil
        current = nil
        if keepResume {
            t.cancel(byProducingResumeData: { data in if let data { try? data.write(to: rf) } })
        } else {
            t.cancel()
        }
    }

    private func resumeFile(_ key: String) -> URL {
        Self.dir.appendingPathComponent(key.replacingOccurrences(of: ":", with: "_") + ".reprise")
    }

    private func save() {
        if let d = try? JSONEncoder().encode(entries) { try? d.write(to: indexFile, options: .atomic) }
    }

    fileprivate func update(_ key: String, _ f: (inout DLEntry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.key == key }) else { return }
        f(&entries[i])
    }

    /// Adresse refusée (mauvaise extension…) : on passe à la suivante, sinon échec.
    fileprivate func tryNextCandidate(_ key: String, reason: String) {
        candidateIndex += 1
        if candidateIndex < candidates.count, let e = entry(key) {
            try? FileManager.default.removeItem(at: resumeFile(key))
            update(key) { $0.bytes = 0; $0.total = 0 }
            start(e)
        } else {
            update(key) { $0.state = .failed; $0.error = reason }
            current = nil
            task = nil
            save()
            next()
        }
    }

    fileprivate func finished(_ key: String, file: URL, response: URLResponse?) {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 200
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        guard (200..<300).contains(code), size > 1_000_000, let e = entry(key) else {
            tryNextCandidate(key, reason: code >= 300 ? "erreur \(code) du serveur" : "fichier vide")
            return
        }
        let ext = candidates.indices.contains(candidateIndex) ? candidates[candidateIndex].pathExtension : e.ext
        let name = key.replacingOccurrences(of: ":", with: "_") + "." + (ext.isEmpty ? "mkv" : ext)
        let dest = Self.dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: file, to: dest)
            update(key) { $0.state = .done; $0.file = name; $0.bytes = size; $0.total = size; $0.error = nil }
        } catch {
            update(key) { $0.state = .failed; $0.error = "enregistrement impossible (espace disque ?)" }
        }
        current = nil
        task = nil
        save()
        next()
    }

    fileprivate func progress(_ key: String, written: Int64, total: Int64) {
        guard Date().timeIntervalSince(lastPublish) > 0.5 else { return }
        lastPublish = Date()
        update(key) { $0.bytes = written; if total > 0 { $0.total = total } }
    }

    fileprivate func failed(_ key: String, error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }            // arrêt voulu (pause, suppression, lecture en ligne)
        if let rd = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data { try? rd.write(to: resumeFile(key)) }
        if (entry(key)?.bytes ?? 0) == 0 {
            tryNextCandidate(key, reason: error.localizedDescription)
        } else {
            update(key) { $0.state = .failed; $0.error = "interrompu : \(error.localizedDescription)" }
            current = nil
            task = nil
            save()
            next()
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // le fichier temporaire disparaît au retour de cette méthode : on le déplace tout de suite
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: tmp)
        let key = downloadTask.taskDescription ?? ""
        let resp = downloadTask.response
        MainActor.assumeIsolated { self.finished(key, file: tmp, response: resp) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let key = downloadTask.taskDescription ?? ""
        MainActor.assumeIsolated { self.progress(key, written: totalBytesWritten, total: totalBytesExpectedToWrite) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let key = task.taskDescription ?? ""
        MainActor.assumeIsolated { self.failed(key, error: error) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}

func fmtBytes(_ b: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useMB, .useGB]
    return f.string(fromByteCount: b)
}
#endif
