#if os(iOS)
import SwiftUI

/// Bouton de téléchargement : télécharger, progression (appui = pause), en pause (appui = reprendre),
/// terminé, échec (appui = réessayer).
struct DownloadButton: View {
    @ObservedObject private var dl = DownloadManager.shared
    let entry: DLEntry
    var big = false

    var body: some View {
        let e = dl.entry(entry.key)
        Button {
            switch e?.state {
            case nil: dl.add(entry)
            case .downloading?, .queued?: dl.pause(entry.key)
            case .paused?, .failed?: dl.resume(entry.key)
            case .done?: break
            }
        } label: {
            ZStack {
                switch e?.state {
                case nil: Image(systemName: "arrow.down.circle")
                case .queued?: Image(systemName: "clock")
                case .downloading?:
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.25), lineWidth: 3)
                        Circle().trim(from: 0, to: max(0.02, e?.progress ?? 0)).stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "pause.fill").font(.system(size: 9))
                    }
                    .frame(width: 22, height: 22)
                case .paused?: Image(systemName: "pause.circle")
                case .done?: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                case .failed?: Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(Theme.gold)
                }
            }
            .font(.system(size: 22))
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
            .accessibilityLabel(label(e))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(big ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func label(_ e: DLEntry?) -> String {
        switch e?.state {
        case nil: return "Télécharger"
        case .queued?: return "En attente"
        case .downloading?: return "Téléchargement \(Int((e?.progress ?? 0) * 100)) %"
        case .paused?: return "En pause"
        case .done?: return "Téléchargé"
        case .failed?: return "Échec, réessayer"
        }
    }
}

/// Onglet « Plus » (iPhone) : téléchargements et réglages.
struct PlusView: View {
    @ObservedObject private var dl = DownloadManager.shared

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    DownloadsView()
                } label: {
                    HStack {
                        Label("Téléchargements", systemImage: "arrow.down.circle")
                        Spacer()
                        let active = dl.entries.filter { $0.state == .downloading || $0.state == .queued }.count
                        if active > 0 { Text("\(active) en cours").font(.footnote).foregroundStyle(Theme.accent) }
                    }
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Réglages", systemImage: "gearshape")
                }
            }
            .navigationTitle("Plus")
        }
    }
}

/// Téléchargements : en cours (progression, pause, reprise), puis films et séries téléchargés, lisibles sans connexion.
struct DownloadsView: View {
    @ObservedObject private var dl = DownloadManager.shared
    @EnvironmentObject var model: AppModel
    @State private var play: PlayRequest?

    private var active: [DLEntry] { dl.entries.filter { $0.state != .done } }
    private var films: [DLEntry] { dl.entries.filter { $0.state == .done && $0.kind == "vod" }.sorted { $0.added > $1.added } }
    private struct SeriesGroup { let name: String; let eps: [DLEntry] }
    private var series: [SeriesGroup] {
        let eps = dl.entries.filter { $0.state == .done && $0.kind == "series" }
        let names = Array(Set(eps.map { $0.seriesName ?? "Séries" })).sorted()
        return names.map { n in
            SeriesGroup(name: n, eps: eps.filter { ($0.seriesName ?? "Séries") == n }.sorted { ($0.season, $0.num) < ($1.season, $1.num) })
        }
    }

    var body: some View {
        List {
            Section {
                Text("Espace utilisé : \(fmtBytes(dl.usedBytes)) · libre : \(fmtBytes(dl.freeBytes))")
                    .font(.footnote).foregroundStyle(Theme.dim)
                Text("Un téléchargement à la fois ; il se met en pause pendant une lecture en ligne (une seule connexion autorisée), puis reprend.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            if !active.isEmpty {
                Section("En cours") {
                    ForEach(active, id: \.key) { e in activeRow(e) }
                }
            }
            if !films.isEmpty {
                Section("Films") {
                    ForEach(films, id: \.key) { e in doneRow(e) }
                }
            }
            ForEach(series, id: \.name) { g in
                Section(g.name) {
                    ForEach(g.eps, id: \.key) { e in doneRow(e) }
                }
            }
            if dl.entries.isEmpty {
                Text("Aucun téléchargement. Sur la fiche d'un film ou d'un épisode, touchez la flèche ↓.")
                    .foregroundStyle(Theme.dim)
            }
        }
        .navigationTitle("Téléchargements")
        .fullScreenCover(item: $play) { r in
            PlayerView(req: r) { model.progressChanged() }
        }
    }

    private func thumb(_ e: DLEntry) -> some View {
        RemoteImage(url: e.poster, px: 200, fallback: "")
            .frame(width: e.kind == "vod" ? 44 : 78, height: e.kind == "vod" ? 66 : 44)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func activeRow(_ e: DLEntry) -> some View {
        HStack(spacing: 12) {
            thumb(e)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.title).font(.subheadline.bold()).lineLimit(1)
                if !e.subtitle.isEmpty { Text(e.subtitle).font(.caption).foregroundStyle(Theme.dim).lineLimit(1) }
                switch e.state {
                case .downloading:
                    ProgressView(value: e.progress).tint(Theme.accent)
                    Text(e.total > 0 ? "\(fmtBytes(e.bytes)) sur \(fmtBytes(e.total))" : "Démarrage…").font(.caption2).foregroundStyle(Theme.dim)
                case .queued: Text("En attente").font(.caption).foregroundStyle(Theme.dim)
                case .paused: Text("En pause").font(.caption).foregroundStyle(Theme.dim)
                case .failed: Text("Échec : \(e.error ?? "inconnu")").font(.caption).foregroundStyle(Theme.gold).lineLimit(2)
                case .done: EmptyView()
                }
            }
            Spacer(minLength: 0)
            DownloadButton(entry: e)
        }
        .swipeActions {
            Button(role: .destructive) { dl.remove(e.key) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func doneRow(_ e: DLEntry) -> some View {
        Button { play = request(e) } label: {
            HStack(spacing: 12) {
                thumb(e)
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.title).font(.subheadline.bold()).lineLimit(2).foregroundStyle(.white)
                    HStack(spacing: 8) {
                        if !e.subtitle.isEmpty && e.kind == "vod" { Text(e.subtitle) }
                        Text(fmtBytes(e.total))
                        let p = Store.pos(e.key), d = Store.dur(e.key)
                        if p > 10_000, d > 0 { Text("vu à \(p * 100 / d) %").foregroundStyle(Theme.accent) }
                        else if Store.seen(e.key) { Text("vu") }
                    }
                    .font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.white)
            }
        }
        .swipeActions {
            Button(role: .destructive) { dl.remove(e.key) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    /// Lecture du fichier (le serveur en secours) ; même reprise que la lecture en ligne ;
    /// pour un épisode, l'épisode téléchargé suivant de la même série enchaîne.
    private func request(_ e: DLEntry) -> PlayRequest {
        let pos = Store.pos(e.key)
        var r = PlayRequest(title: e.kind == "vod" ? e.title : "\(e.seriesName ?? "") · \(e.title)", key: e.key, kind: e.kind,
                            urls: model.playURLs(kind: e.kind, id: e.id, ext: e.ext, key: e.key), startMs: pos > 10_000 ? pos : 0)
        r.seriesId = e.seriesId
        if let sid = e.seriesId {
            let next = dl.entries
                .filter { $0.seriesId == sid && $0.state == .done && ($0.season, $0.num) > (e.season, e.num) }
                .min { ($0.season, $0.num) < ($1.season, $1.num) }
            if let n = next {
                r.nextTitle = n.title
                r.next = {
                    var nr = request(n)
                    nr.startMs = 0
                    return nr
                }
            }
        }
        return r
    }
}
#endif
