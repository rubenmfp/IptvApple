import SwiftUI

/// Contenu choisi (pour ouvrir sa fiche).
struct Selection: Identifiable {
    let item: Item
    var id: String { item.key }
}

/// Écran à rangées : « À la une », bandeau de catégories, puis une rangée horizontale par catégorie.
struct BrowseView: View {
    @EnvironmentObject var model: AppModel
    let rows: [Row]
    let hero: [Item]
    @State private var selected: Selection?
    @State private var searching = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: Theme.rowGap) {
                    if !hero.isEmpty {
                        HeroView(items: hero) { selected = Selection(item: $0) }
                    }
                    if rows.count > 1 {
                        CategoryStrip(rows: rows) { id in
                            withAnimation { proxy.scrollTo(id, anchor: .top) }
                        }
                    }
                    ForEach(rows) { r in
                        RowView(row: r) { selected = Selection(item: $0) }
                            .id(r.id)
                    }
                    StatusLine()
                        .padding(.horizontal, Theme.edge)
                        .padding(.bottom, 30)
                }
                .padding(.top, Theme.tv ? 10 : 0)
            }
            .overlay {
                if rows.isEmpty { EmptyState() }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        #if os(iOS)
        // iPhone : la loupe en haut à droite, comme sur Android
        .overlay(alignment: .topTrailing) {
            Button { searching = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white)
            }
            .padding(.trailing, 12)
            .padding(.top, 4)
        }
        .sheet(isPresented: $searching) { SearchView(closable: true) }
        #endif
        #if os(tvOS)
        // sur la TV, une feuille s'affiche en petit panneau central : la fiche prend tout l'écran
        .fullScreenCover(item: $selected) { s in
            ItemSheet(item: s.item)
        }
        #else
        .sheet(item: $selected) { s in
            ItemSheet(item: s.item)
        }
        #endif
    }
}

/// Message pendant le chargement, en cas d'erreur ou si le catalogue est vide.
struct EmptyState: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 16) {
            if model.loading {
                ProgressView()
                Text(model.progress.isEmpty ? "Chargement…" : model.progress).foregroundStyle(Theme.dim)
                Text("Le premier chargement peut prendre une minute : le catalogue est gros.")
                    .font(.footnote).foregroundStyle(Theme.dim.opacity(0.7)).multilineTextAlignment(.center)
            } else if let e = model.error {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Theme.accent)
                Text(e).multilineTextAlignment(.center).foregroundStyle(Theme.light)
                Button("Réessayer") { model.refresh() }
            } else {
                Text("Catalogue vide.").foregroundStyle(Theme.dim)
                Button("Actualiser") { model.refresh() }
            }
        }
        .padding(40)
        .frame(maxWidth: 700)
    }
}

/// Ligne discrète en bas des rangées : mise à jour en cours ou erreur, sans masquer le catalogue enregistré.
struct StatusLine: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if model.loading {
            HStack(spacing: 10) {
                ProgressView()
                Text(model.progress.isEmpty ? "Mise à jour du catalogue…" : model.progress)
            }
            .font(.footnote).foregroundStyle(Theme.dim)
        } else if let e = model.error {
            Text("Mise à jour impossible : \(e)").font(.footnote).foregroundStyle(Theme.dim)
        }
    }
}

// MARK: - À la une

/// Grande image du titre (nette), titre en grand, note, genre, résumé, boutons Lecture et Plus d'infos ;
/// un titre différent toutes les 10 secondes (pas pendant qu'un bouton est sélectionné).
struct HeroView: View {
    @EnvironmentObject var model: AppModel
    let items: [Item]
    let open: (Item) -> Void
    @State private var index = 0
    @State private var details: [String: AppModel.HeroInfo] = [:]
    @State private var play: PlayRequest?
    @FocusState private var focus: Int?

    var body: some View {
        let item = items[min(index, items.count - 1)]
        let d = details[item.key]
        ZStack(alignment: .bottomLeading) {
            artwork(item, d).id(item.key).transition(.opacity)
            VStack(alignment: .leading, spacing: Theme.tv ? 16 : 9) {
                Text("À LA UNE")
                    .font(.system(size: Theme.tv ? 20 : 11, weight: .heavy))
                    .kerning(Theme.tv ? 4 : 2.5)
                    .foregroundStyle(Theme.accent)
                Text(item.name)
                    .font(.system(size: Theme.tv ? 62 : 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.6), radius: 10)
                metaLine(item, d)
                if let p = d?.plot, !p.isEmpty {
                    Text(p)
                        .font(Theme.tv ? .callout : .footnote)
                        .foregroundStyle(Theme.light.opacity(0.92))
                        .lineLimit(Theme.tv ? 3 : 3)
                        .frame(maxWidth: Theme.tv ? 980 : .infinity, alignment: .leading)
                        .shadow(color: .black.opacity(0.7), radius: 6)
                        .transition(.opacity)
                }
                HStack(spacing: Theme.tv ? 24 : 10) {
                    Button { start(item) } label: { Label("Lecture", systemImage: "play.fill") }
                        .buttonStyle(PillStyle(prominent: true))
                        .focused($focus, equals: 0)
                    Button { open(item) } label: { Label("Plus d'infos", systemImage: "info.circle") }
                        .buttonStyle(PillStyle())
                        .focused($focus, equals: 1)
                    Spacer(minLength: 0)
                    if items.count > 1 { dots }
                }
                .padding(.top, Theme.tv ? 8 : 4)
            }
            .padding(.horizontal, Theme.tv ? 0 : Theme.edge)
            .padding(.bottom, Theme.tv ? 30 : 14)
        }
        .frame(height: Theme.heroHeight)
        .tvSection()
        .animation(.easeInOut(duration: 0.6), value: item.key)
        .animation(.easeOut(duration: 0.4), value: d)
        .task(id: item.key) {
            if details[item.key] == nil { details[item.key] = await model.heroInfo(item) }
            // le suivant à l'avance : pas d'attente au changement
            let next = items[(index + 1) % items.count]
            if details[next.key] == nil { details[next.key] = await model.heroInfo(next) }
        }
        .task(id: items.map(\.key)) {
            index = 0
            while !Task.isCancelled && items.count > 1 {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if focus == nil { index = (index + 1) % items.count }
            }
        }
        .fullScreenCover(item: $play) { r in
            PlayerView(req: r) { model.progressChanged() }
        }
    }

    /// Image : la grande image horizontale si elle existe ; sinon l'affiche, nette, à droite, fondue dans le fond.
    @ViewBuilder private func artwork(_ item: Item, _ d: AppModel.HeroInfo?) -> some View {
        GeometryReader { g in
            ZStack(alignment: .trailing) {
                Theme.bg
                if let b = d?.backdrop, !b.isEmpty {
                    RemoteImage(url: b, px: Theme.tv ? 1920 : 1000)
                        .frame(width: g.size.width, height: g.size.height)
                        .clipped()
                } else {
                    RemoteImage(url: item.poster, px: Theme.tv ? 900 : 600)
                        .frame(width: min(g.size.width, g.size.height * (Theme.tv ? 1.15 : 0.95)), height: g.size.height)
                        .clipped()
                        .overlay(LinearGradient(colors: [Theme.bg, Theme.bg.opacity(0)], startPoint: .leading, endPoint: .init(x: 0.45, y: 0.5)))
                }
            }
            .overlay(LinearGradient(colors: [Theme.bg.opacity(0.92), Theme.bg.opacity(0.45), .clear],
                                    startPoint: .leading, endPoint: .init(x: 0.75, y: 0.5)))
            .overlay(LinearGradient(colors: [.clear, .clear, Theme.bg.opacity(0.75), Theme.bg],
                                    startPoint: .top, endPoint: .bottom))
        }
        .frame(height: Theme.heroHeight)
        .ignoresSafeArea(edges: .horizontal)     // bord à bord, au-delà des marges de la TV
    }

    private func metaLine(_ item: Item, _ d: AppModel.HeroInfo?) -> some View {
        HStack(spacing: Theme.tv ? 14 : 8) {
            if item.rating > 0 {
                Label(fmtRating(item.rating), systemImage: "star.fill").foregroundStyle(Theme.gold)
            }
            if item.year > 0 { Text(String(item.year)) }
            Text(item.type == "series" ? "Série" : "Film")
            let g = (d?.genre).flatMap { $0.isEmpty ? nil : $0 } ?? item.cat
            Text(g).lineLimit(1)
            if item.variants.contains(where: { $0.q == "4K" }) { QualityBadge(text: "4K") }
        }
        .font(Theme.tv ? .callout.weight(.medium) : .caption.weight(.medium))
        .foregroundStyle(Theme.light.opacity(0.85))
        .labelStyle(.titleAndIcon)
    }

    private var dots: some View {
        HStack(spacing: Theme.tv ? 10 : 5) {
            ForEach(items.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.white : Color.white.opacity(0.3))
                    .frame(width: i == index ? (Theme.tv ? 28 : 16) : (Theme.tv ? 10 : 6), height: Theme.tv ? 10 : 6)
            }
        }
        .animation(.easeOut(duration: 0.3), value: index)
    }

    /// Film : lecture directe (reprise s'il est commencé). Série : la fiche, pour choisir l'épisode.
    private func start(_ item: Item) {
        if item.type == "vod" { play = model.filmRequest(item) } else { open(item) }
    }
}

func fmtRating(_ r: Double) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.maximumFractionDigits = 1
    f.minimumFractionDigits = 1
    return f.string(from: NSNumber(value: r)) ?? String(r)
}

// MARK: - Bandeau de catégories

struct CategoryStrip: View {
    let rows: [Row]
    let go: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.tv ? 40 : 8) {
                ForEach(rows) { r in
                    Button {
                        go(r.id)
                    } label: {
                        Text(r.title).lineLimit(1)
                    }
                    .buttonStyle(ChipStyle())
                }
            }
            .padding(.horizontal, Theme.edge)
            .padding(.vertical, Theme.tv ? 10 : 2)
        }
        .scrollClipDisabled()
        .tvSection()
    }
}

// MARK: - Rangée et affiche

struct RowView: View {
    let row: Row
    let open: (Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tv ? 6 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.title).font(Theme.rowTitle).foregroundStyle(Theme.light)
                Text("\(row.items.count)").font(.caption).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, Theme.edge)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.cardGap) {
                    ForEach(row.items, id: \.key) { item in
                        PosterCard(item: item, resume: row.id.hasPrefix("resume|")) { open(item) }
                    }
                }
                .padding(.horizontal, Theme.edge)
                .padding(.vertical, Theme.tv ? 24 : 0)
            }
            .scrollClipDisabled()
            .tvSection()
        }
    }
}

struct PosterCard: View {
    let item: Item
    var resume = false
    let action: () -> Void
    @State private var tmdbRate: Double?

    /// Note affichée : celle de TMDB (comme sur la fiche), sinon celle du fournisseur.
    private var shownRate: Double? {
        if let r = tmdbRate, r > 0 { return r }
        if tmdbRate == nil || tmdbRate == -1 || tmdbRate == 0 { return item.rating > 0 ? item.rating : nil }
        return nil
    }

    private var w: CGFloat { Theme.posterWidth }
    private var badge: String? {
        let qs = item.variants.map(\.q)
        if qs.contains("4K") { return "4K" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: action) {
                RemoteImage(url: item.poster, px: Int(w * 2), fallback: item.name)
                    .frame(width: w, height: w * 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tv ? 12 : 8))
                    .overlay(alignment: .topTrailing) {
                        if let b = badge { QualityBadge(text: b).padding(6) }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let r = shownRate {
                            Text("★ " + fmtRating(r))
                                .font(.system(size: Theme.tv ? 16 : 9, weight: .bold))
                                .foregroundStyle(Theme.gold)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                                .padding(Theme.tv ? 8 : 4)
                                .padding(.bottom, AppModel.progress(of: item) != nil ? 4 : 0)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let p = AppModel.progress(of: item), p.dur > 0 {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(.white.opacity(0.35))
                                    Rectangle().fill(Theme.accent).frame(width: g.size.width * min(1, Double(p.pos) / Double(p.dur)))
                                }
                            }
                            .frame(height: Theme.tv ? 6 : 4)
                        }
                    }
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
            // appui long : favoris, listes ; dans « Reprendre » : retirer
            .contextMenu { ItemMenu(item: item, resume: resume) }
            .task(id: item.key) {
                guard Tmdb.enabled else { return }
                if let c = await Tmdb.shared.cachedRate(item.key) { tmdbRate = c; return }
                try? await Task.sleep(nanoseconds: 400_000_000)      // pas de requête pendant un défilement rapide
                if Task.isCancelled { return }
                tmdbRate = await Tmdb.shared.rate(item)
            }
            Text(item.name)
                .font(Theme.tv ? .caption : .caption2)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .frame(width: w, alignment: .leading)
        }
    }
}


/// Menu de l'appui long sur une affiche : favoris, listes personnelles, nouvelle liste ; « Retirer de Reprendre ».
struct ItemMenu: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    var resume = false

    var body: some View {
        let fav = Store.isFav(item.key)
        Button { model.toggleFav(item) } label: {
            Label(fav ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: fav ? "heart.slash" : "heart")
        }
        ForEach(Store.listNames, id: \.self) { name in
            let inside = Store.inList(name, item.key)
            Button { model.toggleInList(name, item) } label: {
                Label(inside ? "Retirer de « \(name) »" : "Ajouter à « \(name) »", systemImage: inside ? "minus.circle" : "text.badge.plus")
            }
        }
        Button { model.newListFor = item } label: { Label("Nouvelle liste…", systemImage: "plus") }
        if resume {
            Button(role: .destructive) { model.removeFromResume(item) } label: {
                Label("Retirer de « Reprendre »", systemImage: "xmark")
            }
        }
    }
}
