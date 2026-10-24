import SwiftUI

/// Direct : recherche de chaîne, tuiles (Favoris, Récentes, genres, catégories) qui ouvrent la liste déroulante
/// de leurs chaînes, puis rangées Favoris, Regardées récemment et une rangée par catégorie.
struct LiveView: View {
    @EnvironmentObject var model: AppModel
    @State private var play: PlayRequest?
    @State private var query = ""
    @State private var term = ""
    @State private var picker: Row?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.rowGap) {
                searchField
                if term.trimmed.count >= 2 {
                    let found = model.searchLive(term)
                    if found.isEmpty {
                        Text("Aucune chaîne trouvée.").foregroundStyle(Theme.dim).padding(.horizontal, Theme.edge)
                    } else {
                        channelRow(Row(id: "live|*search", title: "Résultats", items: found))
                    }
                }
                tiles
                if let r = model.favLiveRow() { channelRow(r) }
                if let r = model.recentLiveRow() { channelRow(r) }
                ForEach(model.liveRows) { r in channelRow(r) }
                if model.liveLoading {
                    HStack(spacing: 10) { ProgressView(); Text("Chargement des chaînes…") }
                        .foregroundStyle(Theme.dim).padding(.horizontal, Theme.edge)
                } else if let e = model.liveError {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(e).foregroundStyle(Theme.dim)
                        Button("Réessayer") { model.loadLive(force: true) }
                    }
                    .padding(.horizontal, Theme.edge)
                }
                if !model.live.isEmpty && model.epg.isEmpty {
                    Text("Astuce : chargez le guide des programmes dans Réglages pour voir ce qui passe.")
                        .font(.footnote).foregroundStyle(Theme.dim).padding(.horizontal, Theme.edge)
                }
            }
            .padding(.vertical, Theme.tv ? 10 : 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { model.loadLive() }
        .task(id: query) {
            guard query.trimmed.count >= 2 else { term = query; return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled { term = query }
        }
        .fullScreenCover(item: $play) { r in
            PlayerView(req: r) { model.progressChanged() }
        }
        #if os(tvOS)
        .fullScreenCover(item: $picker) { r in
            ChannelPicker(row: r) { c, list in picker = nil; start(c, list, r.title) }
        }
        #else
        .sheet(item: $picker) { r in
            ChannelPicker(row: r) { c, list in picker = nil; start(c, list, r.title) }
        }
        #endif
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
            TextField("Rechercher une chaîne", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { term = query }
        }
        #if os(iOS)
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        #endif
        .padding(.horizontal, Theme.edge)
    }

    /// Tuiles : Favoris, Récentes, genres, puis catégories du fournisseur.
    private var tiles: some View {
        let rows = [model.favLiveRow(), model.recentLiveRow().map { Row(id: $0.id, title: "Récentes", items: $0.items) }].compactMap { $0 }
            + model.liveGenres + model.liveRows
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.tv ? 40 : 8) {
                ForEach(rows) { r in
                    Button { picker = r } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.tv ? 10 : 6) {
                            Text(r.title).lineLimit(1)
                            Text("\(r.items.count)").font(Theme.tv ? .caption2 : .caption2).opacity(0.6).monospacedDigit()
                        }
                    }
                    .buttonStyle(ChipStyle(tint: r.id.hasPrefix("genre|") ? Theme.accent : nil))
                }
            }
            .padding(.horizontal, Theme.edge)
            .padding(.vertical, Theme.tv ? 10 : 2)
        }
        .scrollClipDisabled()
        .tvSection()
    }

    private func channelRow(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: Theme.tv ? 6 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(r.title).font(Theme.rowTitle).foregroundStyle(Theme.light)
                Text("\(r.items.count)").font(.caption).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, Theme.edge)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.cardGap) {
                    ForEach(r.items, id: \.key) { c in
                        ChannelCard(item: c, sub: model.epgLine(c)) { start(c, r.items, r.title) }
                    }
                }
                .padding(.horizontal, Theme.edge)
                .padding(.vertical, Theme.tv ? 24 : 0)
            }
            .scrollClipDisabled()
        }
    }

    private func start(_ c: Item, _ list: [Item], _ name: String) {
        play = model.liveRequest(c, list: list, listName: name)
    }
}

struct ChannelCard: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    var sub: String?
    let action: () -> Void
    private var w: CGFloat { Theme.tv ? 260 : 140 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: action) {
                ZStack {
                    Theme.panel
                    if let p = item.poster, !p.isEmpty {
                        LogoImage(url: p).padding(Theme.tv ? 22 : 12)
                    } else {
                        Text(item.name).font(Theme.tv ? .headline : .caption).foregroundStyle(Theme.light)
                            .multilineTextAlignment(.center).padding(8)
                    }
                }
                .frame(width: w, height: w * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: Theme.tv ? 12 : 8))
                .overlay(alignment: .topTrailing) {
                    if let q = qualities { QualityBadge(text: q).padding(6) }
                }
                .overlay(alignment: .topLeading) {
                    if Store.isFav(item.key) {
                        Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.accent).padding(6)
                    }
                }
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
            .contextMenu {
                let fav = Store.isFav(item.key)
                Button { model.toggleFav(item) } label: {
                    Label(fav ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: fav ? "heart.slash" : "heart")
                }
            }
            Text(item.name)
                .font(Theme.tv ? .caption : .caption2)
                .foregroundStyle(Theme.light)
                .lineLimit(1)
                .frame(width: w, alignment: .leading)
            if let s = sub {
                Text(s).font(Theme.tv ? .caption2 : .system(size: 10)).foregroundStyle(Theme.dim).lineLimit(1)
                    .frame(width: w, alignment: .leading)
            }
        }
    }

    /// Qualités proposées pour la chaîne : « FHD · HD · SD ».
    private var qualities: String? {
        let qs = item.variants.map(\.q).filter { $0 != "?" }
        guard !qs.isEmpty else { return nil }
        var seen = Set<String>()
        return qs.map { $0.split(separator: " ").first.map(String.init) ?? $0 }.filter { seen.insert($0).inserted }.joined(separator: " · ")
    }
}

/// Liste déroulante des chaînes d'une tuile, avec un filtre : plus rapide à parcourir qu'une rangée.
struct ChannelPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let row: Row
    let pick: (Item, [Item]) -> Void
    @State private var filter = ""

    var body: some View {
        let list = row.items
        let k = Names.searchKey(filter.trimmed)
        let shown = k.isEmpty ? list : list.filter { Names.searchKey($0.name).contains(k) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(row.title).font(Theme.tv ? .title2.bold() : .title3.bold()).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text(shown.count == 1 ? "1 chaîne" : "\(shown.count) chaînes").font(.footnote).foregroundStyle(Theme.dim)
                #if os(iOS)
                Button("Fermer") { dismiss() }
                #endif
            }
            TextField("Filtrer cette liste", text: $filter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #if os(iOS)
                .padding(10)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                #endif
            ScrollView {
                LazyVStack(spacing: Theme.tv ? 12 : 6) {
                    ForEach(shown, id: \.key) { c in
                        ChannelLine(item: c, sub: model.epgLine(c)) { pick(c, list) }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(Theme.tv ? 60 : 16)
        .frame(maxWidth: Theme.tv ? 1100 : .infinity, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// Une ligne de liste de chaînes : logo, nom, programme en cours, qualités, cœur si favorite.
struct ChannelLine: View {
    let item: Item
    var sub: String?
    var current = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    if let p = item.poster, !p.isEmpty { LogoImage(url: p) } else { Image(systemName: "tv").foregroundStyle(Theme.dim) }
                }
                .frame(width: Theme.tv ? 90 : 56, height: Theme.tv ? 54 : 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(Theme.tv ? .headline : .subheadline.bold()).lineLimit(1)
                    if let s = sub { Text(s).font(Theme.tv ? .caption : .caption2).opacity(0.7).lineLimit(1) }
                }
                Spacer(minLength: 0)
                let qs = item.variants.map(\.q).filter { $0 != "?" }
                if qs.count > 1 { Text(qs.joined(separator: " · ")).font(.caption2).opacity(0.7).lineLimit(1) }
                if Store.isFav(item.key) { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.accent) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, Theme.tv ? 10 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(iOS)
            .background(current ? Theme.accent.opacity(0.28) : Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            #endif
        }
        #if os(iOS)
        .buttonStyle(.plain)
        #endif
    }
}

/// Logo entier (sans recadrage).
struct LogoImage: View {
    let url: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() } else { Color.clear }
        }
        .task(id: url) {
            if let c = ImageStore.shared.cached(url, px: 400) { image = c; return }
            image = await ImageStore.shared.load(url, px: 400)
        }
    }
}

extension Row: Equatable, Hashable {
    static func == (a: Row, b: Row) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
