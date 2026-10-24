import Foundation
import UIKit
#if os(tvOS)
import TVVLCKit
#else
import MobileVLCKit
#endif

/// Moteur de lecture (VLCKit) : lit le .mkv, le HEVC 10 bits et le son MP2, que le lecteur d'Apple ne sait pas lire.
/// Essaie une à une les adresses possibles (serveur, extension) et retient celle qui marche.
final class PlayerEngine: ObservableObject {
    enum Phase: Equatable { case opening, playing, paused, ended, failed(String) }

    enum Aspect: String, CaseIterable {
        case original = "Original", fill = "Plein écran", stretch = "Étiré", wide = "16/9", classic = "4/3"
    }

    let player = VLCMediaPlayer()
    let videoView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false
        return v
    }()

    @Published private(set) var phase: Phase = .opening
    @Published private(set) var timeMs = 0
    @Published private(set) var durationMs = 0
    @Published private(set) var attempt = ""
    @Published private(set) var aspect: Aspect = .original
    @Published private(set) var rate: Float = 1

    private var candidates: [URL] = []
    private var index = 0
    private var startAtMs = 0
    private var openedAt = Date()
    private var started = false
    private var timer: Timer?
    private var errors: [String] = []
    /// Appelé une fois, avec l'adresse qui a fonctionné.
    var onStarted: ((URL) -> Void)?

    init() {
        player.drawable = videoView
    }

    deinit {
        timer?.invalidate()
        player.stop()
    }

    var live = false

    func play(_ urls: [URL], startAt: Int = 0, live: Bool = false) {
        candidates = urls
        index = 0
        startAtMs = startAt
        self.live = live
        errors = []
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        open()
    }

    private func open() {
        guard index < candidates.count else {
            phase = .failed("Aucune adresse n'a fonctionné.\n" + errors.joined(separator: "\n"))
            timer?.invalidate()
            return
        }
        let url = candidates[index]
        attempt = candidates.count > 1 ? "Essai \(index + 1) sur \(candidates.count) : .\(url.pathExtension.isEmpty ? "flux" : url.pathExtension)" : ""
        let m = VLCMedia(url: url)
        m.addOptions(["network-caching": live ? 3000 : 2000, "http-reconnect": true])
        player.media = m
        started = false
        openedAt = Date()
        phase = .opening
        player.play()
    }

    /// Passe à l'adresse suivante. L'abonnement n'autorise qu'une connexion : on ferme d'abord, puis on attend un peu.
    private func next(_ why: String) {
        errors.append("· \(candidates[index].pathExtension.isEmpty ? "flux" : "." + candidates[index].pathExtension) : \(why)")
        player.stop()
        index += 1
        phase = .opening
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.open() }
    }

    private func tick() {
        guard index < candidates.count else { return }
        let st = player.state
        let t = Int(player.time.intValue)
        timeMs = max(0, t)
        if let len = player.media?.length.intValue, len > 0 { durationMs = Int(len) }

        if !started {
            if player.isPlaying && (t > 0 || player.hasVideoOut) {
                started = true
                onStarted?(candidates[index])
                if startAtMs > 0 {
                    player.time = VLCTime(int: Int32(clamping: startAtMs))
                    startAtMs = 0
                }
                phase = .playing
                return
            }
            switch st {
            case .error: next("erreur d'ouverture")
            case .ended: next("fin immédiate")
            case .stopped where Date().timeIntervalSince(openedAt) > 3: next("arrêt")
            default:
                if Date().timeIntervalSince(openedAt) > 25 { next("pas de réponse") }
            }
            return
        }
        switch st {
        case .paused: phase = .paused
        case .ended: phase = .ended
        case .error: phase = .failed("La lecture s'est interrompue (erreur réseau ou fichier).")
        case .stopped: if phase != .ended { phase = .ended }
        default: if player.isPlaying { phase = .playing }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
    }

    // ---------- commandes ----------
    func togglePause() {
        if player.isPlaying { player.pause(); phase = .paused } else { player.play(); phase = .playing }
    }

    func seek(by seconds: Int) {
        guard !live, durationMs > 0 else { return }
        let target = min(max(0, timeMs + seconds * 1000), max(0, durationMs - 2000))
        player.time = VLCTime(int: Int32(clamping: target))
        timeMs = target
    }

    func seek(toFraction f: Double) {
        guard !live, durationMs > 0 else { return }
        let target = Int(Double(durationMs) * min(max(f, 0), 0.995))
        player.time = VLCTime(int: Int32(clamping: target))
        timeMs = target
    }

    func setRate(_ r: Float) { player.rate = r; rate = r }

    struct Track: Hashable { let id: Int32; let name: String }

    // pistes : index VLC et nom (-1 = désactivé pour les sous-titres)
    var audioTracks: [Track] { pairs(player.audioTrackIndexes, player.audioTrackNames) }
    var subtitleTracks: [Track] { pairs(player.videoSubTitlesIndexes, player.videoSubTitlesNames) }
    var currentAudio: Int32 { player.currentAudioTrackIndex }
    var currentSubtitle: Int32 { player.currentVideoSubTitleIndex }
    func setAudio(_ i: Int32) { player.currentAudioTrackIndex = i; objectWillChange.send() }
    func setSubtitle(_ i: Int32) { player.currentVideoSubTitleIndex = i; objectWillChange.send() }

    private func pairs(_ idx: [Any]?, _ names: [Any]?) -> [Track] {
        let i = (idx ?? []).compactMap { ($0 as? NSNumber)?.int32Value }
        let n = (names ?? []).map { "\($0)" }
        return zip(i, n).map { Track(id: $0, name: $1) }
    }

    /// Format d'image : chaque appui passe au suivant. Toujours « Original » au départ.
    func nextAspect() {
        let all = Aspect.allCases
        let a = all[(all.firstIndex(of: aspect)! + 1) % all.count]
        apply(a)
    }

    func apply(_ a: Aspect) {
        aspect = a
        let b = videoView.bounds.size
        let screen = b.width > 0 && b.height > 0 ? "\(Int(b.width)):\(Int(b.height))" : "16:9"
        player.videoCropGeometry = nil
        player.videoAspectRatio = nil
        player.scaleFactor = 0
        switch a {
        case .original: break
        case .fill: player.videoCropGeometry = strdup(screen)
        case .stretch: player.videoAspectRatio = strdup(screen)
        case .wide: player.videoAspectRatio = strdup("16:9")
        case .classic: player.videoAspectRatio = strdup("4:3")
        }
    }
}
