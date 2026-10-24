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

struct HeroView: View {
    let items: [Item]
    let open: (Item) -> Void
    @State private var index = 0

    var body: some View {
        let item = items[min(index, items.count - 1)]
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: item.poster, px: Theme.tv ? 900 : 500)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.heroHeight)
                .blur(radius: Theme.tv ? 30 : 18)
                .clipped()
                .overlay(LinearGradient(colors: [.clear, Theme.bg.opacity(0.6), Theme.bg], startPoint: .top, endPoint: .bottom))
            HStack(alignment: .bottom, spacing: Theme.tv ? 40 : 16) {
                RemoteImage(url: item.poster, px: Theme.tv ? 500 : 300, fallback: item.name)
                    .frame(width: Theme.tv ? 260 : 130, height: Theme.tv ? 390 : 195)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 12)
                VStack(alignment: .leading, spacing: Theme.tv ? 14 : 8) {
                    Text("À LA UNE").font(.caption.weight(.heavy)).foregroundStyle(Theme.accent)
                    Text(item.name)
                        .font(Theme.tv ? .title2.weight(.bold) : .title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if item.year > 0 { Text(String(item.year)) }
                        if item.rating > 0 { Text("★ " + fmtRating(item.rating)).foregroundStyle(Theme.gold) }
                        Text(item.cat).lineLimit(1)
                    }
                    .font(Theme.tv ? .callout : .caption)
                    .foregroundStyle(Theme.dim)
                    Button {
                        open(item)
                    } label: {
                        Label("Voir la fiche", systemImage: "info.circle")
                    }
                    #if os(iOS)
                    .buttonStyle(.borderedProminent)
                    #endif
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.edge)
            .padding(.bottom, 8)
        }
        .frame(height: Theme.heroHeight)
        .task(id: items.map(\.key)) {
            // une affiche différente toutes les 10 secondes
            while !Task.isCancelled && items.count > 1 {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                withAnimation(.easeInOut(duration: 0.6)) { index = (index + 1) % items.count }
            }
        }
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
            LazyHStack(spacing: Theme.tv ? 24 : 8) {
                ForEach(rows) { r in
                    Button {
                        go(r.id)
                    } label: {
                        Text(r.title)
                            .font(Theme.tv ? .callout : .subheadline)
                            .lineLimit(1)
                            #if os(iOS)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(Theme.light)
                            #endif
                    }
                    #if os(iOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .padding(.horizontal, Theme.edge)
            .padding(.vertical, Theme.tv ? 16 : 0)
        }
        .scrollClipDisabled()
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
                        PosterCard(item: item) { open(item) }
                    }
                }
                .padding(.horizontal, Theme.edge)
                .padding(.vertical, Theme.tv ? 24 : 0)
            }
            .scrollClipDisabled()
        }
    }
}

struct PosterCard: View {
    let item: Item
    let action: () -> Void

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
            Text(item.name)
                .font(Theme.tv ? .caption : .caption2)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .frame(width: w, alignment: .leading)
        }
    }
}
