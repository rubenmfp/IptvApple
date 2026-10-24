import SwiftUI

/// Fiche complète : résumé, versions, lecture et reprise ; pour une série, saisons et épisodes ; puis distribution
/// et titres de la même catégorie.
struct ItemSheet: View {
    @State private var item: Item
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var info: ItemInfo?
    @State private var loadError: String?
    @State private var variant: Variant?
    @State private var season: Int?
    @State private var expanded = false
    @State private var play: PlayRequest?
    @State private var similar: [Item] = []
    @State private var fav = false

    init(item: Item) { _item = State(initialValue: item) }

    private var isSeries: Bool { item.type == "series" }
    private var chosen: Variant? { variant ?? item.variants.first }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.tv ? 34 : 22) {
                    header.id("top")
                    if !isSeries, item.variants.count > 1 { versions }
                    if isSeries { episodesSection }
                    people
                    if !similar.isEmpty { similarRow(proxy) }
                    #if os(iOS)
                    Button("Fermer") { dismiss() }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, Theme.edge)
                    #endif
                }
                .padding(.vertical, Theme.tv ? 50 : 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { backdrop }
        .task(id: item.key) { await load() }
        .fullScreenCover(item: $play) { r in
            PlayerView(req: r) { model.progressChanged() }
        }
    }

    // MARK: - Chargement

    private func load() async {
        fav = Store.isFav(item.key)
        similar = model.sameCategory(as: item)
        variant = nil
        expanded = false
        loadError = nil
        info = model.cachedInfo(item)
        if info == nil {
            do { info = try await model.info(for: item) } catch { loadError = AppModel.message(error) }
        }
        if isSeries, let i = info {
            season = AppModel.episodeToPlay(seriesId: item.id, info: i)?.0.season ?? i.seasons.first
        }
    }

    // MARK: - En-tête

    private var backdrop: some View {
        ZStack {
            Theme.bg
            RemoteImage(url: info?.backdrop ?? item.poster, px: Theme.tv ? 900 : 500)
                .blur(radius: Theme.tv ? 50 : 30)
                .opacity(0.35)
                .overlay(LinearGradient(colors: [Theme.bg.opacity(0.1), Theme.bg], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }

    private var meta: String {
        var parts: [String] = []
        if item.year > 0 { parts.append(String(item.year)) }
        else if let d = info?.releaseDate, d.count >= 4 { parts.append(String(d.prefix(4))) }
        if let r = info?.runtime, r > 0, !isSeries { parts.append(r >= 60 ? "\(r / 60) h \(String(format: "%02d", r % 60))" : "\(r) min") }
        if isSeries, let i = info, !i.seasons.isEmpty { parts.append(i.seasons.count == 1 ? "1 saison" : "\(i.seasons.count) saisons") }
        if let g = info?.genre, !g.isEmpty { parts.append(g) }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.tv ? 50 : 16) {
            RemoteImage(url: item.poster, px: Theme.tv ? 600 : 400, fallback: item.name)
                .frame(width: Theme.tv ? 300 : 120, height: Theme.tv ? 450 : 180)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 10)
            VStack(alignment: .leading, spacing: Theme.tv ? 16 : 10) {
                Text(item.name)
                    .font(Theme.tv ? .title2.weight(.bold) : .title3.weight(.bold))
                    .foregroundStyle(.white)
                HStack(spacing: 10) {
                    Text(isSeries ? "Série" : "Film").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    if item.rating > 0 { Text("★ " + fmtRating(item.rating)).foregroundStyle(Theme.gold) }
                }
                .font(Theme.tv ? .callout : .subheadline)
                if !meta.isEmpty { Text(meta).font(Theme.tv ? .callout : .footnote).foregroundStyle(Theme.dim) }
                plot
                playButtons
                if let e = loadError { Text(e).font(.footnote).foregroundStyle(Theme.dim) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
    }

    @ViewBuilder private var plot: some View {
        if let p = info?.plot, !p.isEmpty {
            let long = p.count > (Theme.tv ? 300 : 180)
            VStack(alignment: .leading, spacing: 6) {
                Text(p)
                    .font(Theme.tv ? .callout : .footnote)
                    .foregroundStyle(Theme.light)
                    .lineLimit(expanded || !long ? nil : (Theme.tv ? 4 : 4))
                    .fixedSize(horizontal: false, vertical: true)
                if long {
                    Button(expanded ? "Réduire" : "Lire la suite") { withAnimation { expanded.toggle() } }
                        .font(Theme.tv ? .callout : .footnote.bold())
                        #if os(iOS)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        #endif
                }
            }
        } else if info == nil && loadError == nil {
            ProgressView().padding(.vertical, 6)
        }
    }

    // MARK: - Boutons

    private var vodProgress: (pos: Int, dur: Int)? {
        _ = model.progressTick
        guard let v = chosen else { return nil }
        let k = "vod:\(v.id)"
        let p = Store.pos(k)
        return p > 10_000 ? (p, Store.dur(k)) : nil
    }

    private var playButtons: some View {
        HStack(spacing: Theme.tv ? 30 : 10) {
            if isSeries {
                if let i = info, let target = AppModel.episodeToPlay(seriesId: item.id, info: i) {
                    let e = target.0
                    Button { play = model.episodeRequest(series: item, info: i, episode: e) } label: {
                        Label("\(target.resume ? "Reprendre" : "Lecture") S\(e.season) É\(e.num)", systemImage: "play.fill").bold()
                    }
                }
            } else if let p = vodProgress {
                Button { startFilm(at: p.pos) } label: { Label("Reprendre à \(fmtTime(p.pos))", systemImage: "play.fill").bold() }
                Button { startFilm(at: 0) } label: { Label("Début", systemImage: "backward.end.fill") }
            } else {
                Button { startFilm(at: 0) } label: { Label("Lecture", systemImage: "play.fill").bold() }
            }
            #if os(iOS)
            if !isSeries, let v = chosen {
                DownloadButton(entry: DLEntry(key: "vod:\(v.id)", kind: "vod", id: v.id, ext: v.ext, title: item.name,
                                              subtitle: v.q == "?" ? "" : v.q, poster: item.poster), big: true)
            }
            #endif
            Button {
                Store.toggleFav(item.key)
                fav = Store.isFav(item.key)
                model.progressChanged()
            } label: {
                Label(fav ? "Favori" : "Ajouter aux favoris", systemImage: fav ? "heart.fill" : "heart")
                    #if os(iOS)
                    .labelStyle(.iconOnly)
                    #endif
            }
            #if os(iOS)
            .tint(fav ? Theme.accent : .gray)
            #endif
        }
        #if os(iOS)
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        #endif
    }

    #if os(iOS)
    private func episodeDownload(_ e: Episode) -> DLEntry {
        DLEntry(key: e.key, kind: "series", id: e.id, ext: e.ext, title: "S\(e.season) É\(e.num) · \(e.title)",
                subtitle: item.name, poster: e.image ?? item.poster, seriesId: item.id, seriesName: item.name,
                season: e.season, num: e.num)
    }
    #endif

    private func startFilm(at ms: Int) {
        guard let v = chosen else { return }
        play = PlayRequest(title: item.name, key: "vod:\(v.id)", kind: "vod",
                           urls: model.playURLs(kind: "vod", id: v.id, ext: info?.ext.isEmpty == false && v.id == item.id ? info!.ext : v.ext,
                                                key: "vod:\(v.id)"),
                           startMs: ms)
    }

    private var versions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Version").font(.headline).foregroundStyle(Theme.light)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.tv ? 20 : 8) {
                    ForEach(item.variants, id: \.id) { v in
                        Button { variant = v } label: {
                            HStack(spacing: 6) {
                                if v.id == chosen?.id { Image(systemName: "checkmark") }
                                Text(v.q == "?" ? "Standard" : v.q)
                            }
                        }
                        #if os(iOS)
                        .buttonStyle(.bordered)
                        .tint(v.id == chosen?.id ? Theme.accent : .gray)
                        #endif
                    }
                }
                .padding(.vertical, Theme.tv ? 20 : 0)
            }
            .scrollClipDisabled()
        }
        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
    }

    // MARK: - Saisons et épisodes

    @ViewBuilder private var episodesSection: some View {
        if let i = info, !i.episodes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.tv ? 18 : 12) {
                if i.seasons.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.tv ? 20 : 8) {
                            ForEach(i.seasons, id: \.self) { s in
                                Button { season = s } label: { Text("Saison \(s)") }
                                    #if os(iOS)
                                    .buttonStyle(.bordered)
                                    .tint(s == season ? Theme.accent : .gray)
                                    #endif
                            }
                        }
                        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                        .padding(.vertical, Theme.tv ? 20 : 0)
                    }
                    .scrollClipDisabled()
                } else {
                    Text("Épisodes").font(Theme.rowTitle).foregroundStyle(Theme.light)
                        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                }
                let eps = i.episodes.filter { $0.season == (season ?? i.seasons.first) }
                #if os(tvOS)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 40) {
                        ForEach(eps, id: \.id) { e in
                            EpisodeCard(episode: e, fallback: item.poster) { play = model.episodeRequest(series: item, info: i, episode: e) }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
                #else
                LazyVStack(alignment: .leading, spacing: 12) {
                    #if os(iOS)
                    Button {
                        eps.forEach { DownloadManager.shared.add(episodeDownload($0)) }
                    } label: {
                        Label(i.seasons.count > 1 ? "Télécharger la saison \(season ?? 1)" : "Télécharger tous les épisodes",
                              systemImage: "arrow.down.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    #endif
                    ForEach(eps, id: \.id) { e in
                        #if os(iOS)
                        EpisodeRow(episode: e, fallback: item.poster, download: episodeDownload(e)) {
                            play = model.episodeRequest(series: item, info: i, episode: e)
                        }
                        #else
                        EpisodeRow(episode: e, fallback: item.poster) { play = model.episodeRequest(series: item, info: i, episode: e) }
                        #endif
                    }
                }
                .padding(.horizontal, Theme.edge)
                #endif
            }
        } else if info != nil {
            Text("Aucun épisode pour cette série.").foregroundStyle(Theme.dim).padding(.horizontal, Theme.tv ? 80 : Theme.edge)
        }
    }

    // MARK: - Distribution et même catégorie

    @ViewBuilder private var people: some View {
        if let i = info, !(i.cast.isEmpty && i.director.isEmpty) {
            VStack(alignment: .leading, spacing: 6) {
                if !i.cast.isEmpty { (Text("Distribution : ").bold() + Text(i.cast)).lineLimit(3) }
                if !i.director.isEmpty { (Text(isSeries ? "Création : " : "Réalisation : ").bold() + Text(i.director)).lineLimit(2) }
            }
            .font(Theme.tv ? .callout : .footnote)
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
        }
    }

    private func similarRow(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dans la même catégorie").font(Theme.rowTitle).foregroundStyle(Theme.light)
                .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.cardGap) {
                    ForEach(similar, id: \.key) { s in
                        PosterCard(item: s) {
                            item = s
                            info = nil
                            withAnimation { proxy.scrollTo("top", anchor: .top) }
                        }
                    }
                }
                .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                .padding(.vertical, Theme.tv ? 24 : 0)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Épisode

private func episodeProgress(_ e: Episode) -> Double? {
    let p = Store.pos(e.key), d = Store.dur(e.key)
    return p > 0 && d > 0 ? min(1, Double(p) / Double(d)) : nil
}

/// iPhone : une ligne par épisode (image, numéro, titre, durée, progression).
struct EpisodeRow: View {
    let episode: Episode
    let fallback: String?
    #if os(iOS)
    var download: DLEntry? = nil
    #endif
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            mainButton
            #if os(iOS)
            if let d = download { DownloadButton(entry: d) }
            #endif
        }
    }

    private var mainButton: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottom) {
                    RemoteImage(url: episode.image ?? fallback, px: 300, fallback: "É\(episode.num)")
                        .frame(width: 132, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let p = episodeProgress(episode) {
                        GeometryReader { g in
                            Rectangle().fill(Theme.accent).frame(width: g.size.width * p, height: 3)
                        }
                        .frame(height: 3)
                    }
                }
                .frame(width: 132, height: 74)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(episode.num). \(episode.title)").font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
                        if Store.seen(episode.key) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.dim).font(.caption) }
                    }
                    if episode.runtime > 0 { Text("\(episode.runtime) min").font(.caption).foregroundStyle(Theme.dim) }
                    if !episode.plot.isEmpty { Text(episode.plot).font(.caption).foregroundStyle(Theme.dim).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Apple TV : une carte par épisode, dans une rangée horizontale.
struct EpisodeCard: View {
    let episode: Episode
    let fallback: String?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                RemoteImage(url: episode.image ?? fallback, px: 700, fallback: "Épisode \(episode.num)")
                    .frame(width: 400, height: 225)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .bottom) {
                        if let p = episodeProgress(episode) {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(.white.opacity(0.35))
                                    Rectangle().fill(Theme.accent).frame(width: g.size.width * p)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if Store.seen(episode.key) {
                            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white).padding(10)
                        }
                    }
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #endif
            Text("\(episode.num). \(episode.title)").font(.callout.bold()).foregroundStyle(Theme.light).lineLimit(1)
                .frame(width: 400, alignment: .leading)
            if episode.runtime > 0 { Text("\(episode.runtime) min").font(.caption).foregroundStyle(Theme.dim) }
        }
    }
}
