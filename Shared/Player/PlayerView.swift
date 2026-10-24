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
    var live: Bool { kind == "live" }
}

/// Surface vidéo de VLC dans SwiftUI.
struct VideoSurface: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct PlayerView: View {
    let req: PlayRequest
    var onClose: () -> Void = {}

    @StateObject private var engine = PlayerEngine()
    @Environment(\.dismiss) private var dismiss
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var lastSave = Date.distantPast
    @State private var osd = ""          // message bref : « +10 s »
    @State private var osdTask: Task<Void, Never>?
    @State private var scrubbing: Double?
    #if os(tvOS)
    @FocusState private var focus: Focus?
    enum Focus: Hashable { case surface, play }
    #endif

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                VideoSurface(view: engine.videoView).ignoresSafeArea()
                #if os(tvOS)
                tvSurface
                #else
                Color.clear.contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture(count: 2).onEnded { v in
                            seek(v.location.x < geo.size.width / 2 ? -10 : 10)
                        }.exclusively(before: TapGesture().onEnded { toggleControls() })
                    )
                #endif
                stateLayer
                if controls { controlsLayer.transition(.opacity) }
                if !osd.isEmpty {
                    Text(osd).font(.title2.bold()).padding(.horizontal, 22).padding(.vertical, 12)
                        .background(.black.opacity(0.6), in: Capsule()).foregroundStyle(.white)
                }
            }
        }
        .ignoresSafeArea()
        #if os(iOS)
        .statusBarHidden(true)
        #endif
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: start)
        .onDisappear(perform: finish)
        .onReceive(engine.$timeMs) { _ in autosave() }
        .onChange(of: engine.phase) { _, p in
            if p == .ended { saveProgress(); close() }
            if case .failed = p { controls = true }
        }
        #if os(tvOS)
        .onExitCommand {
            if controls && engine.phase == .playing { hideControls() } else { close() }
        }
        .onPlayPauseCommand { engine.togglePause(); showControls() }
        #endif
    }

    // MARK: - États (ouverture, erreur)

    @ViewBuilder private var stateLayer: some View {
        switch engine.phase {
        case .opening:
            VStack(spacing: 14) {
                ProgressView().scaleEffect(Theme.tv ? 1.6 : 1.2).tint(.white)
                Text("Ouverture…").foregroundStyle(.white)
                if !engine.attempt.isEmpty { Text(engine.attempt).font(.footnote).foregroundStyle(Theme.dim) }
            }
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

    private var endTime: String {
        let left = max(0, engine.durationMs - engine.timeMs)
        guard engine.durationMs > 0, !req.live else { return "" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "Fin à " + f.string(from: Date().addingTimeInterval(Double(left) / 1000 / Double(max(engine.rate, 0.1))))
    }

    private var clock: String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date()) }

    private var controlsLayer: some View {
        VStack {
            // haut : titre à gauche ; heure et heure de fin à droite, deux lignes alignées, sans fond
            HStack(alignment: .top) {
                #if os(iOS)
                Button { close() } label: { Image(systemName: "xmark").font(.title2.weight(.semibold)).padding(10) }
                    .foregroundStyle(.white)
                #endif
                Text(req.title).font(Theme.tv ? .title3.bold() : .headline).foregroundStyle(.white).lineLimit(1)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(clock)
                    if !endTime.isEmpty { Text(endTime) }
                }
                .font(Theme.tv ? .title3 : .subheadline).monospacedDigit().foregroundStyle(.white)
                .shadow(color: .black, radius: 3)
            }
            .padding(.horizontal, Theme.tv ? 80 : 20)
            .padding(.top, Theme.tv ? 50 : 24)

            Spacer()
            #if os(iOS)
            HStack(spacing: 56) {
                if !req.live { roundButton("gobackward.10") { seek(-10) } }
                roundButton(engine.phase == .paused ? "play.fill" : "pause.fill", big: true) { engine.togglePause(); showControls() }
                if !req.live { roundButton("goforward.10") { seek(10) } }
            }
            Spacer()
            #endif

            VStack(spacing: Theme.tv ? 22 : 10) {
                if !req.live && engine.durationMs > 0 { timeline }
                buttonRow
            }
            .padding(.horizontal, Theme.tv ? 80 : 20)
            .padding(.bottom, Theme.tv ? 50 : 20)
        }
        .background(
            LinearGradient(colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
    }

    private func roundButton(_ icon: String, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: big ? 44 : 30, weight: .semibold))
                .frame(width: big ? 76 : 60, height: big ? 76 : 60)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var timeline: some View {
        let shown = scrubbing.map { Int(Double(engine.durationMs) * $0) } ?? engine.timeMs
        let frac = engine.durationMs > 0 ? Double(shown) / Double(engine.durationMs) : 0
        return VStack(spacing: 6) {
            #if os(iOS)
            Slider(value: Binding(get: { scrubbing ?? frac }, set: { scrubbing = $0; showControls() }), in: 0...1) { editing in
                if !editing, let s = scrubbing { engine.seek(toFraction: s); scrubbing = nil }
            }
            .tint(Theme.accent)
            #else
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3))
                    Capsule().fill(Theme.accent).frame(width: g.size.width * frac)
                }
            }
            .frame(height: 8)
            #endif
            HStack {
                Text(fmtTime(shown))
                Spacer()
                Text("-" + fmtTime(engine.durationMs - shown))
            }
            .font(Theme.tv ? .callout : .caption).monospacedDigit().foregroundStyle(.white)
        }
    }

    private var buttonRow: some View {
        HStack(spacing: Theme.tv ? 30 : 18) {
            #if os(tvOS)
            if !req.live { iconButton("gobackward.10", "Reculer") { seek(-10) } }
            iconButton(engine.phase == .paused ? "play.fill" : "pause.fill", engine.phase == .paused ? "Lecture" : "Pause") {
                engine.togglePause(); showControls()
            }
            .focused($focus, equals: .play)
            if !req.live { iconButton("goforward.10", "Avancer") { seek(10) } }
            #endif
            Menu {
                let tracks = engine.audioTracks
                if tracks.isEmpty { Text("Aucune piste") }
                ForEach(tracks, id: \.self) { t in
                    Button { engine.setAudio(t.id) } label: { checkLabel(t.name, on: t.id == engine.currentAudio) }
                }
            } label: { menuLabel("speaker.wave.2", "Audio") }
            Menu {
                ForEach(engine.subtitleTracks, id: \.self) { t in
                    Button { engine.setSubtitle(t.id) } label: { checkLabel(t.id < 0 ? "Désactivés" : t.name, on: t.id == engine.currentSubtitle) }
                }
                if engine.subtitleTracks.isEmpty { Text("Aucun sous-titre") }
            } label: { menuLabel("captions.bubble", "Sous-titres") }
            if !req.live {
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                        Button { engine.setRate(Float(r)) } label: {
                            checkLabel(r == 1 ? "Normale" : String(format: "×%g", r), on: abs(Double(engine.rate) - r) < 0.01)
                        }
                    }
                } label: { menuLabel("gauge.with.dots.needle.67percent", "Vitesse") }
            }
            iconButton("aspectratio", engine.aspect.rawValue) { engine.nextAspect(); flash("Format : " + engine.aspect.rawValue) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private func checkLabel(_ s: String, on: Bool) -> some View {
        if on { Label(s, systemImage: "checkmark") } else { Text(s) }
    }

    private func menuLabel(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .labelStyle(.iconOnly)
            .font(.system(size: Theme.tv ? 30 : 22))
            .frame(width: Theme.tv ? 70 : 40, height: Theme.tv ? 70 : 40)
            .accessibilityLabel(text)
    }

    private func iconButton(_ icon: String, _ text: String, action: @escaping () -> Void) -> some View {
        Button(action: { action(); showControls() }) {
            Label(text, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: Theme.tv ? 30 : 22))
                .frame(width: Theme.tv ? 70 : 40, height: Theme.tv ? 70 : 40)
        }
        #if os(iOS)
        .buttonStyle(.plain)
        #endif
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
        engine.onStarted = { url in
            if !req.live, !url.pathExtension.isEmpty { Store.setGoodExt(req.kind, url.pathExtension) }
            if req.live { Store.addRecentLive(req.key) } else { Store.addRecent(req.key) }
        }
        engine.play(req.urls, startAt: req.startMs, live: req.live)
        showControls()
    }

    private func finish() {
        saveProgress()
        engine.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        onClose()
    }

    private func close() {
        dismiss()
    }

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
    }

    private func flash(_ text: String) {
        osd = text
        osdTask?.cancel()
        osdTask = Task { try? await Task.sleep(nanoseconds: 1_200_000_000); if !Task.isCancelled { osd = "" } }
    }

    private func toggleControls() { controls ? hideControls() : showControls() }

    private func showControls() {
        withAnimation(.easeOut(duration: 0.2)) { controls = true }
        #if os(tvOS)
        if focus == nil || focus == .surface { DispatchQueue.main.async { focus = .play } }
        #endif
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled, engine.phase == .playing, scrubbing == nil { hideControls() }
        }
    }

    private func hideControls() {
        hideTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { controls = false }
        #if os(tvOS)
        DispatchQueue.main.async { focus = .surface }
        #endif
    }
}

#if os(tvOS)
struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
#endif
