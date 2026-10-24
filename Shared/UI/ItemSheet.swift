import SwiftUI

/// Fiche (étape 3) : versions, lecture et reprise pour les films. La fiche complète (résumé, saisons, épisodes) arrive à l'étape 4.
struct ItemSheet: View {
    let item: Item
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var variant: Variant?
    @State private var play: PlayRequest?

    private var chosen: Variant? { variant ?? item.variants.first }

    private var progress: (pos: Int, dur: Int)? {
        _ = model.progressTick
        guard let v = chosen else { return nil }
        let k = "\(item.type):\(v.id)"
        let p = Store.pos(k)
        return p > 10_000 ? (p, Store.dur(k)) : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: Theme.tv ? 40 : 16) {
                    RemoteImage(url: item.poster, px: Theme.tv ? 600 : 400, fallback: item.name)
                        .frame(width: Theme.tv ? 300 : 140, height: Theme.tv ? 450 : 210)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.name)
                            .font(Theme.tv ? .title2.weight(.bold) : .title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text(item.type == "series" ? "Série" : "Film").foregroundStyle(Theme.accent).font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            if item.year > 0 { Text(String(item.year)) }
                            if item.rating > 0 { Text("★ " + fmtRating(item.rating)).foregroundStyle(Theme.gold) }
                        }
                        .foregroundStyle(Theme.dim)
                        Text(item.cat).foregroundStyle(Theme.dim)
                        if !item.people.isEmpty {
                            Text(item.people).font(.footnote).foregroundStyle(Theme.dim).lineLimit(3)
                        }
                    }
                }

                if item.type == "vod" {
                    playButtons
                    if item.variants.count > 1 { versions }
                } else {
                    Text("Saisons et épisodes : à l'étape 4.").foregroundStyle(Theme.dim)
                }

                #if os(iOS)
                Button("Fermer") { dismiss() }
                    .buttonStyle(.bordered)
                #endif
            }
            .padding(Theme.tv ? 60 : 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                Theme.bg
                #if os(tvOS)
                RemoteImage(url: item.poster, px: 600)
                    .blur(radius: 60)
                    .opacity(0.35)
                    .overlay(LinearGradient(colors: [Theme.bg.opacity(0.2), Theme.bg], startPoint: .top, endPoint: .bottom))
                #endif
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $play) { r in
            PlayerView(req: r) { model.progressChanged() }
        }
    }

    private var playButtons: some View {
        HStack(spacing: Theme.tv ? 30 : 12) {
            if let p = progress {
                Button { start(at: p.pos) } label: {
                    Label("Reprendre à \(fmtTime(p.pos))", systemImage: "play.fill").bold()
                }
                Button { start(at: 0) } label: { Label("Depuis le début", systemImage: "backward.end.fill") }
            } else {
                Button { start(at: 0) } label: { Label("Lecture", systemImage: "play.fill").bold() }
            }
        }
        #if os(iOS)
        .buttonStyle(.borderedProminent)
        #endif
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
    }

    private func start(at ms: Int) {
        guard let v = chosen else { return }
        play = PlayRequest(title: item.name, key: "vod:\(v.id)", kind: "vod",
                           urls: model.fileURLs(kind: "vod", id: v.id, ext: v.ext), startMs: ms)
    }
}
