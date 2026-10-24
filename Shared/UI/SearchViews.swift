import SwiftUI

/// Ouverture de la fiche d'un contenu : feuille sur iPhone, plein écran sur l'Apple TV.
struct ItemDetailPresenter: ViewModifier {
    @Binding var selected: Selection?
    func body(content: Content) -> some View {
        #if os(tvOS)
        content.fullScreenCover(item: $selected) { s in ItemSheet(item: s.item) }
        #else
        content.sheet(item: $selected) { s in ItemSheet(item: s.item) }
        #endif
    }
}

extension View {
    func itemDetail(_ selected: Binding<Selection?>) -> some View { modifier(ItemDetailPresenter(selected: selected)) }
}

/// Liste de rangées (recherche, listes, personne).
struct RowsList: View {
    let rows: [Row]
    @Binding var selected: Selection?
    var body: some View {
        LazyVStack(alignment: .leading, spacing: Theme.rowGap) {
            ForEach(rows) { r in
                RowView(row: r) { selected = Selection(item: $0) }
            }
        }
    }
}

// MARK: - Recherche

/// Recherche de films et de séries : par titre, acteur ou réalisateur, sans tenir compte des accents.
/// Lancée 2 s après la dernière lettre, ou tout de suite avec la touche Rechercher.
struct SearchView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var closable = false
    @State private var text = ""
    @State private var term = ""
    @State private var rows: [Row] = []
    @State private var searching = false
    @State private var selected: Selection?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.tv ? 30 : 16) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                    TextField("Titre, acteur, réalisateur…", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($fieldFocused)
                        .onSubmit { term = text }
                    #if os(iOS)
                    if !text.isEmpty {
                        Button { text = ""; term = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }
                    }
                    if closable { Button("Fermer") { dismiss() } }
                    #endif
                }
                .padding(Theme.tv ? 0 : 12)
                #if os(iOS)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                #endif
                .padding(.horizontal, Theme.tv ? 80 : Theme.edge)

                if searching || (text.trimmed.count >= 2 && text != term) {
                    HStack(spacing: 10) { ProgressView(); Text("Recherche…").foregroundStyle(Theme.dim) }
                        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                } else if term.trimmed.count >= 2 && rows.isEmpty {
                    Text("Aucun résultat pour « \(term.trimmed) ».").foregroundStyle(Theme.dim)
                        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                } else if term.trimmed.isEmpty {
                    Text(model.indexedCount < model.filmCount / 2
                         ? "Astuce : pour trouver les films par acteur, lancez « Indexer les acteurs des films » dans les réglages."
                         : "Films et séries, par titre, acteur ou réalisateur.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                }
                RowsList(rows: rows, selected: $selected)
            }
            .padding(.vertical, Theme.tv ? 40 : 16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .task(id: text) {
            // 2 secondes après la dernière lettre
            guard text.trimmed.count >= 2 else { if text.isEmpty { term = "" }; return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { term = text }
        }
        .task(id: term) {
            searching = true
            rows = await model.search(term)
            searching = false
        }
        .onAppear { if text.isEmpty { fieldFocused = true } }
        .itemDetail($selected)
    }
}

// MARK: - Personne (acteur, réalisateur)

struct PersonView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let name: String
    @State private var selected: Selection?

    var body: some View {
        let items = model.titles(with: name)
        let rows = [Row(id: "p|vod", title: "Films", items: items.filter { $0.type == "vod" }),
                    Row(id: "p|series", title: "Séries", items: items.filter { $0.type == "series" })].filter { !$0.items.isEmpty }
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.tv ? 30 : 16) {
                HStack {
                    Text(name).font(Theme.tv ? .title2.bold() : .title3.bold()).foregroundStyle(.white)
                    Spacer()
                    #if os(iOS)
                    Button("Fermer") { dismiss() }
                    #endif
                }
                .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                if rows.isEmpty {
                    Text("Aucun autre titre trouvé.").foregroundStyle(Theme.dim).padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                }
                RowsList(rows: rows, selected: $selected)
            }
            .padding(.vertical, Theme.tv ? 40 : 20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .itemDetail($selected)
    }
}

// MARK: - Mes listes

/// Favoris et listes personnelles. Un appui long sur une affiche ajoute ou retire d'une liste.
struct ListsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: Selection?
    @State private var deleting: String?
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        let rows = model.listRows()
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.tv ? 30 : 18) {
                if rows.isEmpty || rows.allSatisfy({ $0.items.isEmpty }) {
                    Text("Aucun favori ni liste pour l'instant. Sur une affiche, un appui long ouvre le menu Favoris / listes.")
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                }
                ForEach(rows) { r in
                    if r.items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.title).font(Theme.rowTitle).foregroundStyle(Theme.light)
                            Text("Liste vide.").font(.footnote).foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                    } else {
                        RowView(row: r) { selected = Selection(item: $0) }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gérer les listes").font(.headline).foregroundStyle(Theme.light)
                    HStack(spacing: Theme.tv ? 24 : 10) {
                        Button { newName = ""; creating = true } label: { Label("Nouvelle liste", systemImage: "plus") }
                        ForEach(Store.listNames, id: \.self) { n in
                            Button(role: .destructive) { deleting = n } label: { Label(n, systemImage: "trash") }
                        }
                    }
                    #if os(iOS)
                    .buttonStyle(.bordered)
                    #endif
                }
                .padding(.horizontal, Theme.tv ? 80 : Theme.edge)
                .padding(.top, 10)
            }
            .padding(.vertical, Theme.tv ? 40 : 16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Mes listes")
        .itemDetail($selected)
        .alert("Supprimer la liste « \(deleting ?? "") » ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Supprimer", role: .destructive) { if let d = deleting { model.deleteList(d) }; deleting = nil }
            Button("Annuler", role: .cancel) { deleting = nil }
        }
        .alert("Nouvelle liste", isPresented: $creating) {
            TextField("Nom de la liste", text: $newName)
            Button("Créer") { model.createList(newName, with: nil) }
            Button("Annuler", role: .cancel) {}
        }
    }
}
