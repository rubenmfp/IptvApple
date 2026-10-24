import SwiftUI
import AVFoundation

/// Ce qu'il faut lire.
struct PlayRequest: Identifiable {
    let id = UUID()
    let title: String
    let key: String            // clé de reprise : « vod:123 », « ep:456 », « live:789 »
    let kind: String           // "vod", "series" (épisode) ou "live"
    let urls: [URL]
    var startMs: Int = 0
    var seriesId: Int?         // épisode : série à laquelle il appartient
    var next: (() -> PlayRequest?)?
    var nextTitle: String?
    var live: Bool { kind == "live" }
}

/// Surface vidéo de VLC dans SwiftUI.
struct VideoSurface: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Éléments sélectionnables du lecteur (Apple TV).
enum PlayerFocus: Hashable { case surface, timeline, back, play, forward, audio, subtitles, speed, aspect, rotation, next }

/// Panneaux d'options (Apple TV).
enum OptionPanel: Equatable {
    case audio, subtitles, speed
    var title: String { self == .audio ? "Audio" : self == .subtitles ? "Sous-titres" : "Vitesse" }
    var origin: PlayerFocus { self == .audio ? .audio : self == .subtitles ? .subtitles : .speed }
}

struct PlayerView: View {
    /// Lecture en cours (change quand on passe à l'épisode suivant).
    @State private var req: PlayRequest
    var onClose: () -> Void = {}
    @State private var nextDismissed = false

    init(req: PlayRequest, onClose: @escaping () -> Void = {}) {
        _req = State(initialValue: req)
        self.onClose = onClose
    }

    @StateObject private var engine = PlayerEngine()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var lastSave = Date.distantPast
    @State private var osd = ""          // message bref : « +10 s »
    @State private var osdTask: Task<Void, Never>?
    @FocusState private var focus: PlayerFocus?
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    #if os(tvOS)
    @State private var panel: OptionPanel?
    @FocusState private var panelFocus: Int?
    #else
    @State private var rotation = Prefs.rotation
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(view: engine.videoView).ignoresSafeArea()
            #if os(tvOS)
            tvSurface
            #else
            TapSurface(onTap: toggleControls, onDoubleTap: { left in doubleTap(left) }).ignoresSafeArea()
            #endif
            stateLayer
            if controls { controlsLayer.transition(.opacity) }
            if let title = req.nextTitle, req.next != nil, !nextDismissed {
                NextEpisodeOverlay(clock: engine.clock, title: title, focus: $focus, controlsShown: controls) { goNext() }
            }
            #if os(tvOS)
            if let p = panel { optionPanel(p).transition(.move(edge: .trailing).combined(with: .opacity)) }
            #endif
            if !osd.isEmpty {
                Text(osd).font(.title2.bold()).padding(.horizontal, 22).padding(.vertical, 12)
                    .background(.black.opacity(0.6), in: Capsule()).foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
        }
        #if os(tvOS)
        .ignoresSafeArea()
        #else
        // iPhone : les commandes restent dans la zone sûre (titre et heure sous l'encoche), l'image occupe tout l'écran
        .statusBarHidden(true)
        #endif
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: start)
        .onDisappear(perform: finish)
        .onReceive(engine.clock.$timeMs) { _ in autosave() }
        .onChange(of: engine.phase) { _, p in
            if p == .ended {
                saveProgress()
                if req.next != nil { goNext() } else { close() }
            }
            if case .failed = p { showControls() }
        }
        .onChange(of: scenePhase) { _, p in
            if p == .background { saveProgress(); engine.suspend() }
            if p == .active { engine.resume() }
        }
        .onChange(of: focus) { _, _ in if controls { scheduleHide() } }
        #if os(tvOS)
        .onExitCommand {
            if panel != nil { closePanel() }
            else if focus == .next { nextDismissed = true; focus = .surface }
            else if controls, engine.phase != .opening, !isFailed { hideControls() } else { close() }
        }
        .onPlayPauseCommand { engine.togglePause(); showControls() }
        #endif
    }

    private var isFailed: Bool { if case .failed = engine.phase { return true }; return false }

    // MARK: - États (ouverture, erreur)

    @ViewBuilder private var stateLayer: some View {
        switch engine.phase {
        case .opening:
            VStack(spacing: 14) {
                ProgressView().scaleEffect(Theme.tv ? 1.6 : 1.2).tint(.white)
                Text("Ouverture…").foregroundStyle(.white)
                if !engine.attempt.isEmpty { Text(engine.attempt).font(.footnote).foregroundStyle(Theme.dim) }
            }
            .allowsHitTesting(false)
        case .failed(let msg):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
                Text("Lecture impossible").font(.title3.bold()).foregroundStyle(.white)
                Text(msg).font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                Text("Un VPN actif sur l'appareil peut provoquer ce problème.").font(.footnote).foregroundStyle(Theme.dim)
                Button("Fermer") { close() }
                    #if os(iOS)
                    .buttonStyle(.borderedProminent)
                    #endif
            }
            .padding(30)
            .frame(maxWidth: 800)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        default: EmptyView()
        }
    }

    // MARK: - Commandes

    private var controlsLayer: some View {
        VStack(spacing: 0) {
            // haut : titre à gauche ; heure et heure de fin à droite, deux lignes alignées, sans fond
            HStack(alignment: .top) {
                #if os(iOS)
                Button { close() } label: { Image(systemName: "xmark").font(.title2.weight(.semibold)).padding(10) }
                    .foregroundStyle(.white)
                #endif
                Text(req.title).font(Theme.tv ? .title3.bold() : .headline).foregroundStyle(.white).lineLimit(1)
                Spacer()
                ClockView(clock: engine.clock, rate: engine.rate, live: req.live)
            }
            .padding(.horizontal, Theme.tv ? 80 : 12)
            .padding(.top, Theme.tv ? 50 : 4)

            Spacer(minLength: 0)

            VStack(spacing: Theme.tv ? 22 : 8) {
                if !req.live { timeline }
                buttonRow
            }
            .padding(.horizontal, Theme.tv ? 80 : 12)
            .padding(.bottom, Theme.tv ? 50 : 4)
        }
        .background(
            LinearGradient(colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder private var timeline: some View {
        #if os(tvOS)
        // barre sélectionnable : ◀ ▶ = −/+10 s, OK = pause, ▼ = boutons
        Button { engine.togglePause(); showControls() } label: {
            TimelineView(clock: engine.clock, focused: focus == .timeline, onScrub: nil)
        }
        .buttonStyle(InvisibleButtonStyle())
        .focused($focus, equals: .timeline)
        .onMoveCommand { dir in
            switch dir {
            case .left: seek(-10)
            case .right: seek(10)
            default: break
            }
        }
        #else
        TimelineView(clock: engine.clock, focused: false) { fraction, done in
            if done { engine.seek(toFraction: fraction) }
            scheduleHide()
        }
        #endif
    }

    /// Bas de l'écran : reculer, lecture, avancer à gauche ; audio, sous-titres, vitesse, format à droite.
    /// iPhone en portrait : deux lignes (lecture à gauche, options à droite en dessous), sinon tout est serré.
    @ViewBuilder private var buttonRow: some View {
        #if os(iOS)
        if verticalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .phone {
            VStack(spacing: 6) {
                HStack(spacing: 14) { transportButtons; Spacer(minLength: 0) }
                HStack(spacing: 14) { Spacer(minLength: 0); optionButtons }
            }
            .foregroundStyle(.white)
        } else {
            HStack(spacing: 14) { transportButtons; Spacer(minLength: 10); optionButtons }
                .foregroundStyle(.white)
        }
        #else
        HStack(spacing: 26) { transportButtons; Spacer(minLength: 10); optionButtons }
            .foregroundStyle(.white)
            .disabled(panel != nil)
        #endif
    }

    @ViewBuilder private var transportButtons: some View {
        if !req.live {
            iconButton("gobackward.10", "Reculer de 10 s", .back) { seek(-10) }
        }
        iconButton(engine.phase == .paused ? "play.fill" : "pause.fill", engine.phase == .paused ? "Lecture" : "Pause", .play) {
            engine.togglePause()
        }
        if !req.live {
            iconButton("goforward.10", "Avancer de 10 s", .forward) { seek(10) }
        }
    }

    @ViewBuilder private var optionButtons: some View {
        #if os(tvOS)
        iconButton("speaker.wave.2", "Audio", .audio) { openPanel(.audio) }
        iconButton("captions.bubble", "Sous-titres", .subtitles) { openPanel(.subtitles) }
        if !req.live { iconButton("gauge.with.dots.needle.67percent", "Vitesse", .speed) { openPanel(.speed) } }
        #else
        OptionsMenus(engine: engine, live: req.live, focus: $focus,
                     onOpen: { keepControls(20) }, onPick: { scheduleHide() })
        if UIDevice.current.userInterfaceIdiom == .phone {
            iconButton(rotation == 1 ? "rotate.right" : "lock.rotation", "Rotation", .rotation) { nextRotation() }
        }
        #endif
        iconButton("aspectratio", "Format : " + engine.aspect.rawValue, .aspect) {
            engine.nextAspect()
            #if os(iOS)
            Prefs.aspect = engine.aspect.rawValue
            #endif
            flash("Format : " + engine.aspect.rawValue)
        }
    }

    private func iconButton(_ icon: String, _ text: String, _ f: PlayerFocus, action: @escaping () -> Void) -> some View {
        Button(action: { action(); scheduleHide() }) {
            Image(systemName: icon)
                .font(.system(size: Theme.tv ? 30 : 26, weight: .semibold))
                .frame(width: Theme.tv ? 70 : 48, height: Theme.tv ? 70 : 48)
                .contentShape(Rectangle())
                .accessibilityLabel(text)
        }
        #if os(iOS)
        .buttonStyle(PressStyle())
        #endif
        .focused($focus, equals: f)
    }

    // MARK: - Télécommande (Apple TV)

    #if os(tvOS)
    /// Commandes masquées : un bouton invisible plein écran reçoit la télécommande.
    /// OK = pause, ◀ ▶ = −/+10 s, ▲ ▼ = afficher les commandes.
    private var tvSurface: some View {
        Button {
            engine.togglePause()
            showControls()
        } label: {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(InvisibleButtonStyle())
        .focused($focus, equals: .surface)
        .disabled(controls)
        .onMoveCommand { dir in
            switch dir {
            case .left: seek(-10)
            case .right: seek(10)
            default: showControls()
            }
        }
    }
    #endif

    // MARK: - Actions

    private func start() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        UIApplication.shared.isIdleTimerDisabled = true
        #if os(iOS)
        applyRotation()
        #endif
        #if os(iOS)
        // iPhone : « Plein écran » par défaut (beaucoup de films ont des bandes noires incrustées), puis le dernier choix
        engine.defaultAspect = PlayerEngine.Aspect(rawValue: Prefs.aspect) ?? .fill
        #endif
        startPlayback(req)
        showControls()
    }

    /// Lance une lecture (au départ, ou pour l'épisode suivant).
    private func startPlayback(_ r: PlayRequest) {
        #if os(iOS)
        // lecture en ligne : le téléchargement en cours s'arrête le temps de la lecture (une seule connexion)
        if r.urls.first?.isFileURL != true { DownloadManager.shared.suspendForStreaming() }
        #endif
        engine.onStarted = { url in
            if !r.live, !url.pathExtension.isEmpty { Store.setGoodExt(r.kind, url.pathExtension) }
            if r.live {
                Store.addRecentLive(r.key)
            } else if let sid = r.seriesId {
                Store.addRecent("series:\(sid)")
                if let epId = Int(r.key.replacingOccurrences(of: "ep:", with: "")) { Store.setLastEp(sid, epId) }
            } else {
                Store.addRecent(r.key)
            }
        }
        #if os(iOS)
        // l'écran passe en paysage : on attend la fin de la rotation pour que VLC prenne la bonne taille d'image
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            engine.play(r.urls, startAt: r.startMs, live: r.live)
        }
        #else
        engine.play(r.urls, startAt: r.startMs, live: r.live)
        #endif
    }

    /// Épisode suivant : l'épisode en cours est noté comme vu, puis le suivant démarre dans le même lecteur.
    private func goNext() {
        guard let make = req.next, let n = make() else { close(); return }
        if engine.durationMs > 0 { Store.setProgress(req.key, pos: engine.durationMs, dur: engine.durationMs) }
        engine.stop()
        nextDismissed = false
        req = n
        // une seule connexion autorisée : petite pause entre la fermeture et l'ouverture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { startPlayback(n) }
        showControls()
    }

    private func finish() {
        saveProgress()
        engine.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        #if os(iOS)
        Orientation.release()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { DownloadManager.shared.resumeAfterStreaming() }
        #endif
        onClose()
    }

    private func close() { dismiss() }

    private func saveProgress() {
        guard !req.live, engine.durationMs > 0, engine.timeMs > 0 else { return }
        Store.setProgress(req.key, pos: engine.phase == .ended ? engine.durationMs : engine.timeMs, dur: engine.durationMs)
    }

    private func autosave() {
        if Date().timeIntervalSince(lastSave) > 10 { lastSave = Date(); saveProgress() }
    }

    private func seek(_ s: Int) {
        guard !req.live else { return }
        engine.seek(by: s)
        flash(s > 0 ? "+\(s) s" : "\(s) s")
        if controls { scheduleHide() }
    }

    private func flash(_ text: String) {
        osd = text
        osdTask?.cancel()
        osdTask = Task { try? await Task.sleep(nanoseconds: 1_200_000_000); if !Task.isCancelled { osd = "" } }
    }

    @State private var lastToggle = Date.distantPast
    @State private var controlsBeforeToggle = false

    /// Un appui affiche ou masque tout de suite les commandes (sans attendre un éventuel second appui).
    private func toggleControls() {
        controlsBeforeToggle = controls
        lastToggle = Date()
        controls ? hideControls() : showControls()
    }

    /// Deux appuis : −/+10 s. Le premier appui avait basculé les commandes : on revient à l'état d'avant.
    private func doubleTap(_ left: Bool) {
        if Date().timeIntervalSince(lastToggle) < 0.6 {
            if controlsBeforeToggle { showControls() } else { hideControls() }
        }
        seek(left ? -10 : 10)
    }

    /// Garde les commandes affichées plus longtemps (menu ouvert).
    private func keepControls(_ seconds: UInt64) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            if !Task.isCancelled, engine.phase == .playing, !panelOpen { hideControls() }
        }
    }

    private func showControls() {
        let wasHidden = !controls
        withAnimation(.easeOut(duration: 0.2)) { controls = true }
        #if os(tvOS)
        // la sélection ne va sur la barre de progression que si les commandes étaient masquées
        if wasHidden || focus == nil || focus == .surface {
            DispatchQueue.main.async { focus = req.live ? .play : .timeline }
        }
        #else
        _ = wasHidden
        #endif
        scheduleHide()
    }

    /// Les commandes se masquent après 5 s sans action, seulement pendant la lecture.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled, engine.phase == .playing, !panelOpen { hideControls() }
        }
    }

    #if os(tvOS)
    private var panelOpen: Bool { panel != nil }

    /// Panneau d'options à droite (Apple TV) : plus fiable que les menus du système, et Retour le referme
    /// en laissant la sélection sur le bouton d'où l'on vient.
    private func openPanel(_ p: OptionPanel) {
        withAnimation(.easeOut(duration: 0.2)) { panel = p }
        let sel = panelItems(p).firstIndex { $0.on } ?? 0
        DispatchQueue.main.async { panelFocus = sel }
        hideTask?.cancel()
    }

    private func closePanel() {
        guard let p = panel else { return }
        withAnimation(.easeIn(duration: 0.2)) { panel = nil }
        DispatchQueue.main.async { focus = p.origin }
        scheduleHide()
    }

    private struct PanelItem { let title: String; let on: Bool; let action: () -> Void }

    private func panelItems(_ p: OptionPanel) -> [PanelItem] {
        switch p {
        case .audio:
            return engine.audioTracks.map { t in PanelItem(title: t.name, on: t.id == engine.currentAudio) { engine.setAudio(t.id) } }
        case .subtitles:
            return engine.subtitleTracks.map { t in
                PanelItem(title: t.id < 0 ? "Désactivés" : t.name, on: t.id == engine.currentSubtitle) { engine.setSubtitle(t.id) }
            }
        case .speed:
            let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
            let current = Double(engine.rate)
            var out: [PanelItem] = []
            for r in rates {
                let title: String = r == 1 ? "Normale" : String(format: "×%g", r)
                let on: Bool = abs(current - r) < 0.01
                let rate = Float(r)
                out.append(PanelItem(title: title, on: on, action: { engine.setRate(rate) }))
            }
            return out
        }
    }

    private func optionPanel(_ p: OptionPanel) -> some View {
        let items = panelItems(p)
        return HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text(p.title).font(.title3.bold()).foregroundStyle(.white).padding(.bottom, 6)
                if items.isEmpty {
                    Text(p == .subtitles ? "Aucun sous-titre" : "Aucune piste").foregroundStyle(Theme.dim)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                            Button {
                                it.action()
                                closePanel()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "checkmark").opacity(it.on ? 1 : 0)
                                    Text(it.title).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .frame(width: 520, alignment: .leading)
                            }
                            .focused($panelFocus, equals: i)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(40)
            .frame(width: 640)
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.85))
            .focusSection()
        }
        .ignoresSafeArea()
    }
    #else
    private var panelOpen: Bool { false }

    /// iPhone : paysage par défaut (comme Netflix) ; le bouton passe à « suit le téléphone », puis « portrait ».
    private func nextRotation() {
        rotation = (rotation + 1) % 3
        Prefs.rotation = rotation
        applyRotation()
        flash(["Paysage", "Rotation automatique", "Portrait"][rotation])
    }

    private func applyRotation() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        switch rotation {
        case 1: Orientation.lock(.allButUpsideDown)
        case 2: Orientation.lock(.portrait)
        default: Orientation.lock(.landscape)
        }
    }
    #endif

    private func hideControls() {
        hideTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { controls = false }
        #if os(tvOS)
        if focus != .next { DispatchQueue.main.async { focus = .surface } }
        #endif
    }
}

// MARK: - Éléments qui suivent la position (redessinés seuls, sans toucher aux menus)

/// Bouton « Épisode suivant » pendant le générique estimé (4 % de l'épisode, entre 20 s et 3 min).
struct NextEpisodeOverlay: View {
    @ObservedObject var clock: PlaybackClock
    let title: String
    var focus: FocusState<PlayerFocus?>.Binding
    let controlsShown: Bool
    let action: () -> Void

    private var visible: Bool {
        guard clock.durationMs > 60_000 else { return false }
        let window = min(max(clock.durationMs * 4 / 100, 20_000), 180_000)
        let left = clock.durationMs - clock.timeMs
        return left > 0 && left < window
    }

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if visible {
                    Button(action: action) {
                        HStack(spacing: 12) {
                            Image(systemName: "forward.end.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Épisode suivant").font(Theme.tv ? .headline : .subheadline.bold())
                                Text(title).font(Theme.tv ? .caption : .caption2).lineLimit(1).opacity(0.8)
                            }
                        }
                        .padding(.horizontal, Theme.tv ? 28 : 16)
                        .padding(.vertical, Theme.tv ? 16 : 10)
                        .frame(maxWidth: Theme.tv ? 520 : 300, alignment: .leading)
                        #if os(iOS)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.black)
                        #endif
                    }
                    #if os(iOS)
                    .buttonStyle(PressStyle())
                    #endif
                    .focused(focus, equals: .next)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.trailing, Theme.tv ? 80 : 16)
            .padding(.bottom, controlsShown ? (Theme.tv ? 260 : 150) : (Theme.tv ? 70 : 30))
        }
        .animation(.easeOut(duration: 0.3), value: visible)
        #if os(tvOS)
        .onChange(of: visible) { _, v in
            // Apple TV : OK lance tout de suite l'épisode suivant, Retour masque le bouton
            if v { DispatchQueue.main.async { focus.wrappedValue = .next } }
        }
        #endif
    }
}

/// Heure et heure de fin, deux lignes alignées à droite, sans fond.
struct ClockView: View {
    @ObservedObject var clock: PlaybackClock
    let rate: Float
    let live: Bool

    var body: some View {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let left = max(0, clock.durationMs - clock.timeMs)
        return VStack(alignment: .trailing, spacing: 2) {
            Text(f.string(from: Date()))
            if !live, clock.durationMs > 0 {
                Text("Fin à " + f.string(from: Date().addingTimeInterval(Double(left) / 1000 / Double(max(rate, 0.1)))))
            }
        }
        .font(Theme.tv ? .title3 : .subheadline).monospacedDigit().foregroundStyle(.white)
        .shadow(color: .black, radius: 3)
    }
}

/// Barre de progression. Sur iPhone, elle se touche ou se fait glisser.
struct TimelineView: View {
    @ObservedObject var clock: PlaybackClock
    let focused: Bool
    /// (fraction, terminé)
    var onScrub: ((Double, Bool) -> Void)?
    @State private var drag: Double?

    var body: some View {
        let dur = max(clock.durationMs, 1)
        let frac = drag ?? (clock.durationMs > 0 ? Double(clock.timeMs) / Double(dur) : 0)
        let shown = Int(Double(dur) * frac)
        let h: CGFloat = Theme.tv ? (focused ? 14 : 8) : 5
        return VStack(spacing: Theme.tv ? 10 : 4) {
            GeometryReader { g in
                let bar = ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3)).frame(height: h)
                    Capsule().fill(Theme.accent).frame(width: max(h, g.size.width * frac), height: h)
                    if focused || onScrub != nil {
                        Circle().fill(.white)
                            .frame(width: Theme.tv ? 26 : 16, height: Theme.tv ? 26 : 16)
                            .offset(x: g.size.width * frac - (Theme.tv ? 13 : 8))
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                #if os(iOS)
                bar.gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let f = min(max(v.location.x / max(g.size.width, 1), 0), 1)
                        drag = f
                        onScrub?(f, false)
                    }
                    .onEnded { v in
                        let f = min(max(v.location.x / max(g.size.width, 1), 0), 1)
                        onScrub?(f, true)
                        drag = nil
                    }, including: onScrub == nil ? .none : .all)
                #else
                bar
                #endif
            }
            .frame(height: Theme.tv ? 30 : 28)
            HStack {
                Text(fmtTime(shown))
                Spacer()
                Text("-" + fmtTime(max(0, clock.durationMs - shown)))
            }
            .font(Theme.tv ? .callout : .caption).monospacedDigit().foregroundStyle(.white)
        }
        .opacity(clock.durationMs > 0 ? 1 : 0.4)
    }
}

/// Menus audio, sous-titres et vitesse. Vue à part : la position qui avance ne les redessine pas (plus de clignotement).
struct OptionsMenus: View {
    @ObservedObject var engine: PlayerEngine
    let live: Bool
    var focus: FocusState<PlayerFocus?>.Binding
    var onOpen: () -> Void = {}
    var onPick: () -> Void = {}

    var body: some View {
        Menu {
            let tracks = engine.audioTracks
            if tracks.isEmpty { Text("Aucune piste") }
            ForEach(tracks, id: \.self) { t in
                Button { engine.setAudio(t.id); onPick() } label: { check(t.name, on: t.id == engine.currentAudio) }
            }
        } label: { icon("speaker.wave.2", "Audio") }
        .focused(focus, equals: .audio)
        .simultaneousGesture(TapGesture().onEnded { onOpen() })

        Menu {
            ForEach(engine.subtitleTracks, id: \.self) { t in
                Button { engine.setSubtitle(t.id); onPick() } label: { check(t.id < 0 ? "Désactivés" : t.name, on: t.id == engine.currentSubtitle) }
            }
            if engine.subtitleTracks.isEmpty { Text("Aucun sous-titre") }
        } label: { icon("captions.bubble", "Sous-titres") }
        .focused(focus, equals: .subtitles)
        .simultaneousGesture(TapGesture().onEnded { onOpen() })

        if !live {
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                    Button { engine.setRate(Float(r)); onPick() } label: {
                        check(r == 1 ? "Normale" : String(format: "×%g", r), on: abs(Double(engine.rate) - r) < 0.01)
                    }
                }
            } label: { icon("gauge.with.dots.needle.67percent", "Vitesse") }
            .focused(focus, equals: .speed)
            .simultaneousGesture(TapGesture().onEnded { onOpen() })
        }
    }

    @ViewBuilder private func check(_ s: String, on: Bool) -> some View {
        if on { Label(s, systemImage: "checkmark") } else { Text(s) }
    }

    private func icon(_ name: String, _ text: String) -> some View {
        Image(systemName: name)
            .font(.system(size: Theme.tv ? 30 : 22, weight: .semibold))
            .frame(width: Theme.tv ? 70 : 44, height: Theme.tv ? 70 : 44)
            .accessibilityLabel(text)
    }
}

#if os(iOS)
/// Zone de toucher plein écran (UIKit) : un appui affiche ou masque les commandes, deux appuis à gauche ou à droite = −/+10 s.
/// Les gestes UIKit restent fiables même quand l'image se met à jour en continu.
struct TapSurface: UIViewRepresentable {
    let onTap: () -> Void
    let onDoubleTap: (_ left: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.double(_:)))
        double.numberOfTapsRequired = 2
        // pas d'attente du second appui : l'affichage des commandes est immédiat
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.single(_:)))
        v.addGestureRecognizer(double)
        v.addGestureRecognizer(single)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onDoubleTap = onDoubleTap
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void = {}
        var onDoubleTap: (Bool) -> Void = { _ in }
        @objc func single(_ g: UITapGestureRecognizer) { onTap() }
        @objc func double(_ g: UITapGestureRecognizer) {
            guard let v = g.view else { return }
            onDoubleTap(g.location(in: v).x < v.bounds.width / 2)
        }
    }
}
#endif

#if os(iOS)
/// Bouton qui réagit visiblement au toucher (léger rétrécissement), comme dans les lecteurs connus.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
#endif

#if os(tvOS)
struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
#endif
