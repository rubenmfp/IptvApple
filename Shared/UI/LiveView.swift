import SwiftUI

/// Direct (version simple pour l'étape 3) : une rangée par catégorie, une chaîne se lance d'un appui.
/// Recherche, genres, liste déroulante et changement de chaîne arrivent à l'étape 6.
struct LiveView: View {
    @EnvironmentObject var model: AppModel
    @State private var play: PlayRequest?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.rowGap) {
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
            }
            .padding(.vertical, Theme.tv ? 10 : 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { model.loadLive() }
        .fullScreenCover(item: $play) { r in
            PlayerView(req: r) { model.progressChanged() }
        }
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
                        ChannelCard(item: c) { start(c) }
                    }
                }
                .padding(.horizontal, Theme.edge)
                .padding(.vertical, Theme.tv ? 24 : 0)
            }
            .scrollClipDisabled()
        }
    }

    private func start(_ c: Item) {
        let v = c.variants.first
        play = PlayRequest(title: c.name, key: c.key, kind: "live", urls: model.liveURLs(id: v?.id ?? c.id))
    }
}

struct ChannelCard: View {
    let item: Item
    let action: () -> Void
    private var w: CGFloat { Theme.tv ? 260 : 140 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    if let q = item.variants.first?.q, q != "?" { QualityBadge(text: q).padding(6) }
                }
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
            Text(item.name)
                .font(Theme.tv ? .caption : .caption2)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .frame(width: w, alignment: .leading)
        }
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
