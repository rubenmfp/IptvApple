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
    private var newIds: Set<Int> { Set(model.news[item.key]?.map(\.id) ?? []) }
    /// Version choisie, sinon la qualité préférée (la dernière choisie ailleurs), sinon la meilleure.
    private var chosen: Variant? {
        variant ?? item.variants.first { $0.q == Store.prefQuality } ?? item.variants.first
    }
    @State private var person: String?
    @State private var rating = 0
    @State private var tmdb: TmdbInfo?
    @State private var photos: [String: String] = [:]
    @Environment(\.openURL) private var openURL
    /// Favoris et listes : menu, nouvelle liste.
    @State private var listTick = 0
    @State private var creatingList = false
    @State private var newListName = ""
    @State private var listDialog = false
    @State private var showPoster = false
    #if os(iOS)
    @State private var rateOpen = false
    #endif
    #if os(tvOS)
    @FocusState private var actionFocus: String?
    #endif

    private var inAnyList: Bool {
        _ = listTick
        return fav || Store.listNames.contains { Store.inList($0, item.key) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.tv ? 34 : 22) {
                    header.id("top")
                    #if os(iOS)
                    phoneActions
                    #endif
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
        #if os(iOS)
        .fullScreenCover(isPresented: $showPoster) { PosterViewer(url: item.poster, title: item.name) }
        #endif
        .alert("Nouvelle liste", isPresented: $creatingList) {
            TextField("Nom de la liste", text: $newListName)
            Button("Créer") { model.createList(newListName, with: item); listTick += 1 }
            Button("Annuler", role: .cancel) {}
        } message: { Text("« \(item.name) » y sera ajouté.") }
        #if os(tvOS)
        .confirmationDialog(item.name, isPresented: $listDialog, titleVisibility: .visible) { listActions }
        #endif
        .fullScreenCover(item: $play) { r in
            PlayerView(req: r) { model.progressChanged() }
        }
        #if os(tvOS)
        .fullScreenCover(item: Binding(get: { person.map { PersonRef(name: $0) } }, set: { person = $0?.name })) { p in PersonView(name: p.name) }
        #else
        .sheet(item: Binding(get: { person.map { PersonRef(name: $0) } }, set: { person = $0?.name })) { p in PersonView(name: p.name) }
        #endif
    }

    // MARK: - Chargement

    private func load() async {
        fav = Store.isFav(item.key)
        rating = Store.rating(item.key)
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
        await loadTmdb()
    }

    /// Avec une clé TMDB : note et votes, résumé en français, date, durée, bande-annonce, photos, images des épisodes.
    private func loadTmdb() async {
        tmdb = nil
        photos = [:]
        guard Tmdb.enabled else { return }
        let key = item.key
        guard let t = await Tmdb.shared.details(type: item.type, tmdbId: info?.tmdb ?? item.tmdb, title: item.name, year: item.year),
              key == item.key else { return }
        tmdb = t
        if var i = info {
            if !t.overview.isEmpty { i.plot = t.overview }
            if i.runtime == 0 { i.runtime = t.runtime }
            if i.releaseDate.isEmpty { i.releaseDate = t.date }
            if isSeries {
                for s in i.seasons where i.episodes.contains(where: { $0.season == s && $0.image == nil }) {
                    let st = await Tmdb.shared.seasonStills(tvId: t.id, season: s)
                    for k in i.episodes.indices where i.episodes[k].season == s && i.episodes[k].image == nil {
                        i.episodes[k].image = st[i.episodes[k].num]
                    }
                }
            }
            if key == item.key { info = i }
        }
        var ph: [String: String] = [:]
        for p in t.cast + t.directors { if let u = p.photo { ph[p.name.lowercased()] = u } }
        photos = ph
    }

    // MARK: - En-tête

    /// Fond : la grande image du titre (TMDB ou fournisseur) nette, fondue vers le bas et la gauche ;
    /// à défaut, l'affiche floutée.
    private var backdrop: some View {
        let wide = (tmdb?.backdrop).flatMap { $0.isEmpty ? nil : $0 } ?? info?.backdrop
        return ZStack(alignment: .top) {
            Theme.bg
            if let w = wide, !w.isEmpty {
                RemoteImage(url: w, px: Theme.tv ? 1920 : 900)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.tv ? 760 : 300)
                    .clipped()
                    .opacity(0.55)
                    .overlay(LinearGradient(colors: [.clear, Theme.bg.opacity(0.7), Theme.bg], startPoint: .top, endPoint: .bottom))
                    .overlay(LinearGradient(colors: [Theme.bg.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing))
            } else {
                RemoteImage(url: item.poster, px: Theme.tv ? 900 : 500)
                    .blur(radius: Theme.tv ? 50 : 30)
                    .opacity(0.35)
                    .overlay(LinearGradient(colors: [Theme.bg.opacity(0.1), Theme.bg], startPoint: .top, endPoint: .bottom))
            }
        }
        .ignoresSafeArea()
    }

    private var meta: String {
        var parts: [String] = []
        if item.year > 0 { parts.append(String(item.year)) }
        else if let d = info?.releaseDate, d.count >= 4 { parts.append(String(d.prefix(4))) }
        if let r = info?.runtime ?? tmdb?.runtime, r > 0, !isSeries { parts.append(r >= 60 ? "\(r / 60) h \(String(format: "%02d", r % 60))" : "\(r) min") }
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
                #if os(iOS)
                // iPhone : un appui sur l'affiche l'ouvre en plein écran
                .overlay(alignment: .bottomTrailing) {
                    if item.poster != nil {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .padding(5).background(Circle().fill(.black.opacity(0.55))).padding(5)
                    }
                }
                .onTapGesture { if item.poster != nil { showPoster = true } }
                #endif
            VStack(alignment: .leading, spacing: Theme.tv ? 16 : 10) {
                Text(item.name)
                    .font(Theme.tv ? .title2.weight(.bold) : .title3.weight(.bold))
                    .foregroundStyle(.white)
                HStack(spacing: 10) {
                    Text(isSeries ? "Série" : "Film").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    if let t = tmdb, t.rating > 0 {
                        Text("★ " + fmtRating(t.rating)).foregroundStyle(Theme.gold)
                        Text("\(t.votes) votes TMDB").foregroundStyle(Theme.dim)
                    } else if item.rating > 0 {
                        Text("★ " + fmtRating(item.rating)).foregroundStyle(Theme.gold)
                    }
                }
                .font(Theme.tv ? .callout : .subheadline)
                if !meta.isEmpty { Text(meta).font(Theme.tv ? .callout : .footnote).foregroundStyle(Theme.dim) }
                plot
                #if os(tvOS)
                playButtons
                #endif
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
                        .buttonStyle(TextLinkStyle())
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

    #if os(tvOS)
    /// Apple TV : boutons en pilules (Lecture en blanc), puis pictogrammes ronds ; le nom du pictogramme sélectionné
    /// s'affiche dessous. Une note donnée, un favori ou une série suivie apparaissent en couleur d'accent.
    private var playButtons: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 22) {
                if isSeries {
                    if let i = info, let target = AppModel.episodeToPlay(seriesId: item.id, info: i) {
                        let e = target.0
                        Button { play = model.episodeRequest(series: item, info: i, episode: e) } label: {
                            Label("\(target.resume ? "Reprendre" : "Lecture") S\(e.season) É\(e.num)", systemImage: "play.fill")
                        }
                        .buttonStyle(PillStyle(prominent: true))
                        .focused($actionFocus, equals: "play")
                    }
                } else if let p = vodProgress {
                    Button { startFilm(at: p.pos) } label: { Label("Reprendre à \(fmtTime(p.pos))", systemImage: "play.fill") }
                        .buttonStyle(PillStyle(prominent: true))
                        .focused($actionFocus, equals: "play")
                    Button { startFilm(at: 0) } label: { Label("Début", systemImage: "backward.end.fill") }
                        .buttonStyle(PillStyle(round: true))
                        .focused($actionFocus, equals: "Depuis le début")
                } else {
                    Button { startFilm(at: 0) } label: { Label("Lecture", systemImage: "play.fill") }
                        .buttonStyle(PillStyle(prominent: true))
                        .focused($actionFocus, equals: "play")
                }
                ForEach([-1, 1, 2], id: \.self) { v in
                    Button {
                        model.setRating(item, rating == v ? 0 : v)
                        rating = Store.rating(item.key)
                    } label: { RatingIcon(value: v, filled: rating == v, size: 30) }
                    .buttonStyle(PillStyle(selected: rating == v, round: true))
                    .focused($actionFocus, equals: (ratingLabels[v] ?? "") + (rating == v ? " ✓" : ""))
                }
                Button { listDialog = true } label: { Label("Favoris et listes", systemImage: inAnyList ? "heart.fill" : "heart") }
                    .buttonStyle(PillStyle(selected: inAnyList, round: true))
                    .focused($actionFocus, equals: inAnyList ? "Dans mes favoris / listes" : "Ajouter aux favoris ou à une liste")
                if isSeries {
                    let on = model.follows[item.key] != nil
                    Button { model.setFollow(item, info: info, on: !on) } label: {
                        Label(on ? "Suivie" : "Suivre", systemImage: on ? "bell.fill" : "bell")
                    }
                    .buttonStyle(PillStyle(selected: on, round: true))
                    .focused($actionFocus, equals: on ? "Série suivie (Sorties)" : "Suivre la série")
                }
                if let t = tmdb?.trailer {
                    Button { openTrailer(t) } label: { Label("Bande-annonce", systemImage: "film") }
                        .buttonStyle(PillStyle(round: true))
                        .focused($actionFocus, equals: "Bande-annonce")
                }
            }
            Text(actionFocus.map { $0 == "play" ? " " : $0 } ?? " ")
                .font(.caption).foregroundStyle(Theme.dim)
                .animation(nil, value: actionFocus)
        }
        .padding(.top, 10)
        .tvSection()
    }
    #endif

    /// Favoris, listes, nouvelle liste (menu sur iPhone, liste de choix sur l'Apple TV).
    @ViewBuilder private var listActions: some View {
        Button(fav ? "Retirer des favoris" : "Ajouter aux favoris") {
            model.toggleFav(item)
            fav = Store.isFav(item.key)
            listTick += 1
        }
        ForEach(Store.listNames, id: \.self) { name in
            let inside = Store.inList(name, item.key)
            Button(inside ? "Retirer de « \(name) »" : "Ajouter à « \(name) »") {
                model.toggleInList(name, item)
                listTick += 1
            }
        }
        Button("Nouvelle liste…") {
            newListName = ""
            // la liste de choix se ferme d'abord, puis la saisie du nom s'ouvre
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { creatingList = true }
        }
        #if os(tvOS)
        Button("Annuler", role: .cancel) {}
        #endif
    }

    #if os(iOS)
    /// iPhone (comme Netflix) : un grand bouton sur toute la largeur, la progression dessous,
    /// puis les actions secondaires en icônes légendées.
    private var phoneActions: some View {
        let target: (Episode, resume: Bool)? = isSeries ? info.flatMap { AppModel.episodeToPlay(seriesId: item.id, info: $0) } : nil
        let film = isSeries ? nil : vodProgress
        let pos: (Int, Int)? = isSeries
            ? target.flatMap { t in let p = Store.pos(t.0.key); return p > 10_000 ? (p, Store.dur(t.0.key)) : nil }
            : film.map { ($0.pos, $0.dur) }
        let title: String = {
            if let t = target { return "\(t.resume ? "Reprendre" : "Lecture") · S\(t.0.season) É\(t.0.num)" }
            if isSeries { return "Lecture" }
            return film != nil ? "Reprendre" : "Lecture"
        }()
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                if isSeries {
                    if let i = info, let t = target { play = model.episodeRequest(series: item, info: i, episode: t.0) }
                } else {
                    startFilm(at: film?.pos ?? 0)
                }
            } label: {
                Label(title, systemImage: "play.fill")
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(.black)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PressStyle())
            .disabled(isSeries && target == nil)
            .opacity(isSeries && target == nil ? 0.5 : 1)

            if let (p, d) = pos, d > 0 {
                HStack(spacing: 10) {
                    ProgressView(value: min(1, Double(p) / Double(d))).tint(Theme.accent)
                    Text("\(fmtTime(p)) sur \(fmtTime(d))").font(.caption).foregroundStyle(Theme.dim).monospacedDigit()
                }
            }

            HStack(spacing: 0) {
                if !isSeries && film != nil {
                    ActionTile(icon: "backward.end.fill", text: "Depuis le début") { startFilm(at: 0) }
                }
                if !isSeries, let v = chosen {
                    DownloadTile(entry: DLEntry(key: "vod:\(v.id)", kind: "vod", id: v.id, ext: v.ext, title: item.name,
                                                subtitle: v.q == "?" ? "" : v.q, poster: item.poster))
                }
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { rateOpen.toggle() } } label: {
                    VStack(spacing: 6) {
                        RatingIcon(value: rating == 0 ? 1 : rating, filled: rating != 0, size: 22)
                            .foregroundStyle(rating != 0 ? Theme.accent : .white)
                            .frame(height: 24)
                        Text(ratingLabels[rating] ?? "Noter").font(.caption2).foregroundStyle(rating != 0 ? Theme.accent : Theme.dim).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                if isSeries {
                    let on = model.follows[item.key] != nil
                    ActionTile(icon: on ? "bell.fill" : "bell", text: on ? "Suivie" : "Suivre", on: on) {
                        model.setFollow(item, info: info, on: !on)
                    }
                }
                if let t = tmdb?.trailer {
                    ActionTile(icon: "film", text: "Bande-annonce") { openTrailer(t) }
                }
                Menu { listActions } label: {
                    VStack(spacing: 6) {
                        Image(systemName: inAnyList ? "heart.fill" : "heart").font(.system(size: 22))
                            .foregroundStyle(inAnyList ? Theme.accent : .white)
                        Text(inAnyList ? "Dans mes listes" : "Ma liste").font(.caption2)
                            .foregroundStyle(inAnyList ? Theme.accent : Theme.dim).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
            }
            if rateOpen {
                // notes : trois pictogrammes ronds, celui choisi en couleur d'accent (un second appui retire la note)
                HStack(spacing: 18) {
                    ForEach([-1, 1, 2], id: \.self) { v in
                        Button {
                            model.setRating(item, rating == v ? 0 : v)
                            rating = Store.rating(item.key)
                            withAnimation(.easeOut(duration: 0.25).delay(0.35)) { rateOpen = false }
                        } label: {
                            VStack(spacing: 6) {
                                RatingIcon(value: v, filled: rating == v, size: 24)
                                    .foregroundStyle(.white)
                                    .frame(width: 58, height: 58)
                                    .background(Circle().fill(rating == v ? Theme.accent : Color.white.opacity(0.12)))
                                    .overlay(Circle().strokeBorder(.white.opacity(rating == v ? 0.8 : 0.15), lineWidth: rating == v ? 2 : 1))
                                    .scaleEffect(rating == v ? 1.08 : 1)
                                Text(ratingLabels[v] ?? "").font(.caption2).foregroundStyle(rating == v ? Theme.accent : Theme.dim)
                            }
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.edge)
    }

    private func episodeDownload(_ e: Episode) -> DLEntry {
        DLEntry(key: e.key, kind: "series", id: e.id, ext: e.ext, title: "S\(e.season) É\(e.num) · \(e.title)",
                subtitle: item.name, poster: e.image ?? item.poster, seriesId: item.id, seriesName: item.name,
                season: e.season, num: e.num)
    }
    #endif

    /// Bande-annonce dans l'appli YouTube (ou le navigateur sur iPhone).
    private func openTrailer(_ key: String) {
        #if os(tvOS)
        if let u = URL(string: "youtube://watch/\(key)") { openURL(u) }
        #else
        if let u = URL(string: "youtube://www.youtube.com/watch?v=\(key)"), UIApplication.shared.canOpenURL(u) { openURL(u) }
        else if let u = URL(string: "https://www.youtube.com/watch?v=\(key)") { openURL(u) }
        #endif
    }

    private func startFilm(at ms: Int) {
        guard let v = chosen else { return }
        play = model.filmRequest(item, variant: v, at: ms,
                                 ext: info?.ext.isEmpty == false && v.id == item.id ? info!.ext : v.ext)
    }

    private var versions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Version").font(.headline).foregroundStyle(Theme.light)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.tv ? 20 : 8) {
                    ForEach(item.variants, id: \.id) { v in
                        Button { variant = v; if v.q != "?" { Store.prefQuality = v.q } } label: {
                            Text(v.q == "?" ? "Standard" : v.q)
                        }
                        .buttonStyle(PillStyle(selected: v.id == chosen?.id))
                    }
                }
                .padding(.vertical, Theme.tv ? 20 : 2)
            }
            .scrollClipDisabled()
        }
        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tvSection()
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
                                    .buttonStyle(PillStyle(selected: s == season))
                            }
                        }
                        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                        .padding(.vertical, Theme.tv ? 20 : 2)
                    }
                    .scrollClipDisabled()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tvSection()
                } else {
                    Text("Épisodes").font(Theme.rowTitle).foregroundStyle(Theme.light)
                        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                }
                let eps = i.episodes.filter { $0.season == (season ?? i.seasons.first) }
                #if os(tvOS)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 40) {
                        ForEach(eps, id: \.id) { e in
                            EpisodeCard(episode: e, fallback: item.poster, isNew: newIds.contains(e.id)) { play = model.episodeRequest(series: item, info: i, episode: e) }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
                .tvSection()
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
                        EpisodeRow(episode: e, fallback: item.poster, isNew: newIds.contains(e.id), download: episodeDownload(e)) {
                            play = model.episodeRequest(series: item, info: i, episode: e)
                        }
                        #else
                        EpisodeRow(episode: e, fallback: item.poster, isNew: newIds.contains(e.id)) { play = model.episodeRequest(series: item, info: i, episode: e) }
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

    /// Distribution et réalisation : chaque nom ouvre les autres titres de la personne.
    @ViewBuilder private var people: some View {
        if let i = info, !(i.cast.isEmpty && i.director.isEmpty) {
            VStack(alignment: .leading, spacing: Theme.tv ? 14 : 10) {
                personRow("Distribution", i.cast)
                personRow(isSeries ? "Création" : "Réalisation", i.director)
            }
        }
    }

    @ViewBuilder private func personRow(_ title: String, _ names: String) -> some View {
        let list = names.split(whereSeparator: { ",/;".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.tv ? .headline : .subheadline.bold()).foregroundStyle(Theme.light)
                    .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.tv ? 20 : 8) {
                        ForEach(Array(list.prefix(15)), id: \.self) { n in
                            Button { person = n } label: {
                                HStack(spacing: 8) {
                                    // photo de la personne (TMDB) quand elle est connue
                                    if let u = photos[n.lowercased()] {
                                        RemoteImage(url: u, px: 120).frame(width: Theme.tv ? 56 : 28, height: Theme.tv ? 56 : 28).clipShape(Circle())
                                    }
                                    Text(n).font(Theme.tv ? .callout : .footnote).lineLimit(1)
                                }
                                #if os(iOS)
                                .padding(.horizontal, 12).padding(.vertical, photos[n.lowercased()] == nil ? 7 : 4)
                                .background(Color.white.opacity(0.1), in: Capsule())
                                .foregroundStyle(Theme.light)
                                #endif
                            }
                            #if os(iOS)
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                    .padding(.vertical, Theme.tv ? 16 : 0)
                }
                .scrollClipDisabled()
                .frame(maxWidth: .infinity, alignment: .leading)
                .tvSection()
            }
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
            .tvSection()
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
    var isNew = false
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
                        if isNew { NewTag() }
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
    var isNew = false
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
                    .overlay(alignment: .topLeading) { if isNew { NewTag().padding(10) } }
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

struct PersonRef: Identifiable { let name: String; var id: String { name } }

/// Étiquette « NOUVEAU » d'un épisode sorti depuis le suivi de la série.
struct NewTag: View {
    var body: some View {
        Text("NOUVEAU").font(.system(size: Theme.tv ? 16 : 9, weight: .heavy))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
    }
}

#if os(iOS)
/// Affiche en plein écran (iPhone) : pincer ou toucher deux fois pour zoomer, glisser vers le bas ou ✕ pour fermer.
struct PosterViewer: View {
    let url: String?
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var drag: CGFloat = 0

    /// Le fond s'éclaircit à mesure qu'on fait glisser l'affiche pour la fermer.
    private var backdropOpacity: Double {
        let d = Double(abs(drag))
        return 1.0 - Swift.min(0.6, d / 600.0)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity).ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height + drag)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { v in scale = min(5, max(1, lastScale * v)) }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1.01 { withAnimation(.spring()) { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero } }
                            }
                            .simultaneously(with: DragGesture()
                                .onChanged { v in
                                    if scale > 1 {
                                        offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                                    } else {
                                        drag = v.translation.height
                                    }
                                }
                                .onEnded { v in
                                    if scale > 1 { lastOffset = offset; return }
                                    if abs(v.translation.height) > 140 { dismiss() } else { withAnimation(.spring()) { drag = 0 } }
                                })
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero } else { scale = 2.5; lastScale = 2.5 }
                        }
                    }
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
            .opacity(drag == 0 ? 1 : 0)
        }
        .overlay(alignment: .bottom) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 20).opacity(scale == 1 && drag == 0 ? 1 : 0)
        }
        .statusBarHidden(true)
        .task {
            guard let url else { return }
            // l'affiche du catalogue d'abord (déjà en mémoire), puis une version plus fine
            if let c = ImageStore.shared.cached(url, px: 400) { image = c }
            if let big = await ImageStore.shared.load(url, px: 1600) { image = big }
        }
    }
}
#endif
