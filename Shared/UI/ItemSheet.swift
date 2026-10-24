import SwiftUI

/// Fiche simplifiée (étape 2) : sert à vérifier le nettoyage des noms et le regroupement des versions.
/// La vraie fiche (résumé, saisons, lecture) arrive aux étapes 3 et 4.
struct ItemSheet: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss

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
                        if item.type == "vod" {
                            Text("Versions").font(.headline).foregroundStyle(Theme.light).padding(.top, 6)
                            HStack(spacing: 8) {
                                ForEach(item.variants, id: \.id) { v in
                                    QualityBadge(text: v.q == "?" ? "Standard" : v.q)
                                }
                            }
                        }
                        if !item.people.isEmpty {
                            Text(item.people).font(.footnote).foregroundStyle(Theme.dim).lineLimit(3)
                        }
                    }
                }
                Text("La lecture et la fiche complète arrivent aux prochaines étapes.")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                #if os(iOS)
                Button("Fermer") { dismiss() }
                    .buttonStyle(.bordered)
                #endif
            }
            .padding(Theme.tv ? 60 : 20)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
