import Foundation
import UIKit
#if os(tvOS)
import TVVLCKit
#else
import MobileVLCKit
#endif

/// Moteur de lecture (VLCKit) : lit le .mkv, le HEVC 10 bits et le son MP2, que le lecteur d'Apple ne sait pas lire.
/// Essaie une à une les adresses possibles (serveur, extension) et retient celle qui marche.
/// Vue qui accueille l'image de VLC et signale ses changements de taille.
final class VideoHostView: UIView {
    var onResize: (() -> Void)?
    private var last: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != last {
            last = bounds.size
            fit()
            onResize?()
            // VLC peut repositionner son image un peu après : on recale encore une fois
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.fit() }
        }
    }

    /// L'image de VLC (vues et calques ajoutés par VLC) occupe toute la surface.
    func fit() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for v in subviews {
            v.frame = bounds
            for l in v.layer.sublayers ?? [] { l.frame = v.bounds }
        }
        let viewLayers = Set(subviews.map { ObjectIdentifier($0.layer) })
        for l in layer.sublayers ?? [] where !viewLayers.contains(ObjectIdentifier(l)) { l.frame = bounds }
        CATransaction.commit()
    }
}

final class PlaybackClock: ObservableObject {
    @Published private(set) var timeMs = 0
    @Published private(set) var durationMs = 0
    func set(time t: Int) { if abs(t - timeMs) >= 200 { timeMs = t } }
    func set(duration d: Int) { if d != durationMs { durationMs = d } }
}

final class PlayerEngine: ObservableObject {
    enum Phase: Equatable { case opening, playing, paused, ended, failed(String) }

    enum Aspect: String, CaseIterable {
        case original = "Original", fill = "Plein écran", stretch = "Étiré", wide = "16/9", classic = "4/3"
    }

    #if os(tvOS)
    let player = VLCMediaPlayer()
    #else
    /// iPhone : sous-titres plus petits (taille relative à la hauteur de l'image : 20 = petit, 16 = normal).
    let player = VLCMediaPlayer(options: ["--freetype-rel-fontsize=20"])
    #endif
    let videoView: VideoHostView = {
        let v = VideoHostView()
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false
        return v
    }()

    /// Ne publie que les vrais changements : réaffecter la même valeur redessinerait l'écran (menus qui clignotent).
    @Published private(set) var phase: Phase = .opening
    /// Position et durée, publiées à part : l'écran du lecteur (menus compris) n'est pas redessiné quatre fois par seconde,
    /// seuls la barre de progression et l'heure de fin le sont.
    let clock = PlaybackClock()
    var timeMs: Int { clock.timeMs }
    var durationMs: Int { clock.durationMs }
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
        // taille changée (rotation) : on réapplique le format, calculé d'après la taille de l'écran
        videoView.onResize = { [weak self] in
            guard let self, self.aspect != .original else { return }
            self.apply(self.aspect)
        }
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
            let msg = "Aucune adresse n'a fonctionné.\n" + errors.joined(separator: "\n")
            Prefs.playerErr = Self.stampNow() + " · " + msg.replacingOccurrences(of: "\n", with: " ")
            setPhase(.failed(msg))
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
        setPhase(.opening)
        player.play()
    }

    /// Passe à l'adresse suivante. L'abonnement n'autorise qu'une connexion : on ferme d'abord, puis on attend un peu.
    private func next(_ why: String) {
        errors.append("· \(candidates[index].pathExtension.isEmpty ? "flux" : "." + candidates[index].pathExtension) : \(why)")
        player.stop()
        index += 1
        setPhase(.opening)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.open() }
    }

    private func tick() {
        guard index < candidates.count else { return }
        let st = player.state
        let t = Int(player.time.intValue)
        if started || t > 0 { clock.set(time: max(0, t)) }
        if let len = player.media?.length.intValue, len > 0 { clock.set(duration: Int(len)) }

        if !started {
            if player.isPlaying && (t > 0 || player.hasVideoOut) {
                started = true
                onStarted?(candidates[index])
                applySound()
                let ext = candidates[index].pathExtension.isEmpty ? "flux" : "." + candidates[index].pathExtension
                Prefs.playerNote = Self.stampNow() + " · " + (live ? "direct" : "vidéo") + " · " + ext
                    + (candidates.count > 1 ? " (essai \(index + 1) sur \(candidates.count))" : "")
                    + (errors.isEmpty ? "" : " · échecs avant : " + errors.map { $0.replacingOccurrences(of: "· ", with: "") }.joined(separator: ", "))
                if startAtMs > 0 {
                    player.time = VLCTime(int: Int32(clamping: startAtMs))
                    startAtMs = 0
                }
                startedAt = Date()
                if defaultAspect != .original { apply(defaultAspect) }
                setPhase(.playing)
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
        refreshSubtitles()
        switch st {
        case .paused: setPhase(.paused)
        case .ended: setPhase(.ended)
        case .error:
            if case .failed = phase { break }
            Prefs.playerErr = Self.stampNow() + " · interruption en cours de lecture (.\(candidates[index].pathExtension))"
            setPhase(.failed("La lecture s'est interrompue (erreur réseau ou fichier)."))
        case .stopped: if phase != .ended { setPhase(.ended) }
        default: if player.isPlaying { setPhase(.playing) }
        }
    }

    private var suspendedAt: Int?
    private var wasPaused = false

    /// Appli en arrière-plan : on ferme le flux (une seule connexion) en retenant la position.
    func suspend() {
        guard started, index < candidates.count, suspendedAt == nil else { return }
        suspendedAt = live ? 0 : timeMs
        wasPaused = phase == .paused
        timer?.invalidate()
        player.stop()
    }

    /// Retour au premier plan : on rouvre la même adresse à la même position (l'image revient, pas d'écran noir).
    func resume() {
        guard let at = suspendedAt else { return }
        suspendedAt = nil
        startAtMs = at
        player.drawable = videoView
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        let keepPaused = wasPaused
        open()
        if keepPaused {
            // reprendre en pause : on attend que la lecture reparte pour la remettre en pause
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.player.isPlaying else { return }
                self.player.pause()
                self.setPhase(.paused)
            }
        }
    }

    private func setPhase(_ p: Phase) { if phase != p { phase = p } }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
    }

    // ---------- commandes ----------
    /// Pause / lecture d'après l'état affiché (pendant une mise en mémoire tampon, VLC ne se dit pas « en lecture »).
    func togglePause() {
        if phase == .paused { player.play(); setPhase(.playing) } else { player.pause(); setPhase(.paused) }
    }

    /// Format appliqué au démarrage de chaque lecture.
    var defaultAspect: Aspect = .original

    func seek(by seconds: Int) {
        guard !live, durationMs > 0 else { return }
        let target = min(max(0, timeMs + seconds * 1000), max(0, durationMs - 2000))
        player.time = VLCTime(int: Int32(clamping: target))
        clock.set(time: target)
        if seconds < 0 { showSubtitlesBriefly() }
    }

    func seek(toFraction f: Double) {
        guard !live, durationMs > 0 else { return }
        let target = Int(Double(durationMs) * min(max(f, 0), 0.995))
        player.time = VLCTime(int: Int32(clamping: target))
        clock.set(time: target)
    }

    func setRate(_ r: Float) { player.rate = r; rate = r }

    // ---------- rendu sonore (égaliseur de VLC) ----------
    static let soundNames = ["Normal", "Basses renforcées", "Dialogues plus clairs", "Cinéma"]
    /// 0 = normal, 1 = basses, 2 = dialogues, 3 = cinéma ; `boost` = volume amplifié. Retenus pour les lectures suivantes.
    @Published private(set) var sound = Prefs.fxPreset
    @Published private(set) var boost = Prefs.fxBoost

    func setSound(_ p: Int) { sound = p; Prefs.fxPreset = p; applySound() }
    func setBoost(_ b: Bool) { boost = b; Prefs.fxBoost = b; applySound() }

    /// Gains (dB) des 10 bandes de VLC : 60, 170, 310, 600 Hz, 1, 3, 6, 12, 14, 16 kHz.
    private func applySound() {
        let bands: [[CGFloat]] = [[], [7, 6, 4, 2, 0, 0, 0, 0, 0, 0], [-4, -3, -1, 1, 3, 4, 3, 1, 0, -1], [5, 3, 1, 0, -1, 1, 2, 3, 3, 2]]
        let pre: [CGFloat] = [0, -4, 0, -3]
        let p = (0..<bands.count).contains(sound) ? sound : 0
        if p == 0 && !boost {
            player.equalizerEnabled = false
            return
        }
        player.equalizerEnabled = true
        let b = bands[p]
        for i in 0..<Int(player.numberOfBands) {
            player.setAmplification(i < b.count ? b[i] : 0, forBand: UInt32(i))
        }
        player.preAmplification = pre[p] + (boost ? 9 : 0)
    }

    static func stampNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: Date())
    }

    struct Track: Hashable { let id: Int32; let name: String }

    // pistes : index VLC et nom (-1 = désactivé pour les sous-titres)
    var audioTracks: [Track] { pairs(player.audioTrackIndexes, player.audioTrackNames) }
    /// Liste gardée en mémoire : une fois les sous-titres désactivés, VLC ne la redonne pas toujours en entier.
    private var knownSubs: [Track] = []
    var subtitleTracks: [Track] {
        let now = pairs(player.videoSubTitlesIndexes, player.videoSubTitlesNames)
        if now.count > knownSubs.count { knownSubs = now }
        return knownSubs.isEmpty ? now : knownSubs
    }
    var currentAudio: Int32 { player.currentAudioTrackIndex }
    var currentSubtitle: Int32 { player.currentVideoSubTitleIndex }
    func setAudio(_ i: Int32) { player.currentAudioTrackIndex = i; objectWillChange.send() }

    /// Choix de l'utilisateur : il prime sur la désactivation par défaut et sur l'affichage temporaire.
    func setSubtitle(_ i: Int32) {
        userSubtitle = i
        tempSubtitleUntil = nil
        player.currentVideoSubTitleIndex = i
        objectWillChange.send()
    }

    private var startedAt: Date?
    private var userSubtitle: Int32?
    private var tempSubtitleUntil: Date?

    /// Sous-titres désactivés au départ (VLC active d'office ceux marqués « par défaut » dans le fichier),
    /// sauf choix de l'utilisateur ; fin de l'affichage temporaire après un retour arrière.
    private func refreshSubtitles() {
        _ = subtitleTracks
        if let until = tempSubtitleUntil, Date() > until {
            tempSubtitleUntil = nil
            if userSubtitle == nil || userSubtitle == -1 { player.currentVideoSubTitleIndex = -1 }
            return
        }
        guard tempSubtitleUntil == nil, userSubtitle == nil, let s = startedAt, Date().timeIntervalSince(s) < 8 else { return }
        if player.currentVideoSubTitleIndex != -1 { player.currentVideoSubTitleIndex = -1 }
    }

    /// Après un retour arrière, sous-titres affichés 10 s s'ils sont désactivés (pour relire une réplique).
    func showSubtitlesBriefly() {
        guard player.currentVideoSubTitleIndex == -1 else { return }
        let tracks = subtitleTracks.filter { $0.id >= 0 }
        guard let t = tracks.first(where: { $0.name.lowercased().contains("fr") }) ?? tracks.first else { return }
        player.currentVideoSubTitleIndex = t.id
        tempSubtitleUntil = Date().addingTimeInterval(10)
    }

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
