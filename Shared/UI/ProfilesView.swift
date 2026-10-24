import SwiftUI

/// Pastille d'un profil : carré arrondi en dégradé, initiale en blanc.
struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 60
    var circle = false

    static let palette: [UInt32] = [0xE50914, 0x2196F3, 0x1DB954, 0xFF9800, 0x9C27B0, 0xE91E8C, 0x00ACC1, 0x8D6E63]
    static func color(_ i: Int) -> Color { Accent.rgb(palette[(0..<palette.count).contains(i) ? i : 0]) }

    var body: some View {
        let c = Self.color(profile.color)
        let r = circle ? size / 2 : size * 0.2
        RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(LinearGradient(colors: [c, c.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(.black))
            .overlay(
                Text(String(profile.name.trimmed.prefix(1)).uppercased())
                    .font(.system(size: size * 0.46, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            )
            .frame(width: size, height: size)
    }
}

/// Bouton de profil : grossit et s'entoure de blanc à la sélection (Apple TV) ou à l'appui (iPhone).
private struct AvatarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { AvatarButtonBody(configuration: configuration) }
}

private struct AvatarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var focusedEnv
    private var focused: Bool {
        #if os(tvOS)
        return focusedEnv
        #else
        return false
        #endif
    }
    var body: some View {
        configuration.label
            .scaleEffect(focused ? 1.12 : (configuration.isPressed ? 0.94 : 1))
            .brightness(focused ? 0.05 : 0)
            .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 18, y: 10)
            .animation(.easeOut(duration: 0.18), value: focused)
    }
}

/// « Qui regarde ? » : choix du profil, ajout, et mode « Gérer » (renommer, couleur, supprimer).
struct ProfilePickerView: View {
    @EnvironmentObject var model: AppModel
    @State private var managing = false
    @State private var editing: ProfileDraft?
    @FocusState private var focus: String?

    private var tile: CGFloat { Theme.tv ? 200 : 96 }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bg, Color.black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: Theme.tv ? 60 : 34) {
                Text(managing ? "Gérer les profils" : "Qui regarde ?")
                    .font(.system(size: Theme.tv ? 56 : 30, weight: .bold))
                    .foregroundStyle(.white)
                let cols = [GridItem(.adaptive(minimum: tile + (Theme.tv ? 40 : 20)), spacing: Theme.tv ? 50 : 20)]
                LazyVGrid(columns: cols, spacing: Theme.tv ? 50 : 26) {
                    ForEach(model.profiles) { p in
                        Button {
                            if managing { editing = ProfileDraft(profile: p, isNew: false) } else { model.selectProfile(p.id) }
                        } label: {
                            VStack(spacing: Theme.tv ? 18 : 10) {
                                ProfileAvatar(profile: p, size: tile)
                                    .overlay {
                                        if managing {
                                            RoundedRectangle(cornerRadius: tile * 0.2, style: .continuous).fill(.black.opacity(0.45))
                                            Image(systemName: "pencil").font(.system(size: tile * 0.3, weight: .bold)).foregroundStyle(.white)
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: tile * 0.2, style: .continuous)
                                            .strokeBorder(.white, lineWidth: focus == p.id ? (Theme.tv ? 6 : 3) : 0)
                                    )
                                Text(p.name)
                                    .font(Theme.tv ? .title3 : .subheadline)
                                    .foregroundStyle(focus == p.id ? .white : Theme.dim)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(AvatarButtonStyle())
                        .focused($focus, equals: p.id)
                    }
                    if model.profiles.count < Profiles.maxCount {
                        Button {
                            editing = ProfileDraft(profile: Profile(id: "", name: "", color: nextColor), isNew: true)
                        } label: {
                            VStack(spacing: Theme.tv ? 18 : 10) {
                                RoundedRectangle(cornerRadius: tile * 0.2, style: .continuous)
                                    .strokeBorder(Color.white.opacity(focus == "+" ? 1 : 0.35), lineWidth: Theme.tv ? 4 : 2)
                                    .frame(width: tile, height: tile)
                                    .overlay(Image(systemName: "plus").font(.system(size: tile * 0.34, weight: .semibold)).foregroundStyle(.white))
                                Text("Ajouter").font(Theme.tv ? .title3 : .subheadline).foregroundStyle(focus == "+" ? .white : Theme.dim)
                            }
                        }
                        .buttonStyle(AvatarButtonStyle())
                        .focused($focus, equals: "+")
                    }
                }
                .frame(maxWidth: Theme.tv ? 1300 : 420)

                Button(managing ? "Terminé" : "Gérer les profils") { withAnimation { managing.toggle() } }
                    .buttonStyle(PillStyle(selected: managing))
            }
            .padding(Theme.tv ? 80 : 24)
        }
        .onAppear { focus = model.profile.id }
        #if os(tvOS)
        .fullScreenCover(item: $editing) { d in ProfileEditor(draft: d) }
        #else
        .sheet(item: $editing) { d in ProfileEditor(draft: d) }
        #endif
    }

    private var nextColor: Int {
        let used = Set(model.profiles.map(\.color))
        return (0..<ProfileAvatar.palette.count).first { !used.contains($0) } ?? 0
    }
}

struct ProfileDraft: Identifiable {
    var profile: Profile
    var isNew: Bool
    var id: String { isNew ? "new" : profile.id }
}

/// Nom et couleur d'un profil ; suppression (sauf le profil principal, lié à la synchronisation Wi-Fi).
struct ProfileEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProfileDraft
    @State private var confirmDelete = false

    init(draft: ProfileDraft) { _draft = State(initialValue: draft) }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: Theme.tv ? 40 : 24) {
                Text(draft.isNew ? "Nouveau profil" : "Modifier le profil")
                    .font(.system(size: Theme.tv ? 46 : 24, weight: .bold)).foregroundStyle(.white)
                ProfileAvatar(profile: draft.profile.name.isEmpty ? Profile(id: "", name: "?", color: draft.profile.color) : draft.profile,
                              size: Theme.tv ? 180 : 110)
                TextField("Nom du profil", text: $draft.profile.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(Theme.tv ? .title3 : .title3)
                    #if os(iOS)
                    .padding(12)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                    #endif
                    .frame(maxWidth: Theme.tv ? 700 : 320)
                HStack(spacing: Theme.tv ? 26 : 12) {
                    ForEach(ProfileAvatar.palette.indices, id: \.self) { i in
                        Button { draft.profile.color = i } label: {
                            Circle().fill(ProfileAvatar.color(i))
                                .frame(width: Theme.tv ? 60 : 32, height: Theme.tv ? 60 : 32)
                                .overlay(Circle().strokeBorder(.white, lineWidth: draft.profile.color == i ? (Theme.tv ? 5 : 3) : 0))
                        }
                        .buttonStyle(AvatarButtonStyle())
                    }
                }
                HStack(spacing: Theme.tv ? 30 : 12) {
                    Button(draft.isNew ? "Créer" : "Enregistrer") { save() }
                        .buttonStyle(PillStyle(prominent: true))
                    Button("Annuler") { dismiss() }
                        .buttonStyle(PillStyle())
                    if !draft.isNew && draft.profile.id != Profiles.mainId {
                        Button("Supprimer") { confirmDelete = true }
                            .buttonStyle(PillStyle())
                    }
                }
                if draft.profile.id == Profiles.mainId {
                    Text("Profil principal : il ne peut pas être supprimé.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
            }
            .padding(Theme.tv ? 80 : 24)
        }
        .alert("Supprimer « \(draft.profile.name) » ?", isPresented: $confirmDelete) {
            Button("Supprimer", role: .destructive) { model.deleteProfile(draft.profile.id); dismiss() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ses favoris, listes, reprises et réglages seront effacés.")
        }
    }

    private func save() {
        if draft.isNew {
            model.addProfile(name: draft.profile.name, color: draft.profile.color)
        } else {
            var p = draft.profile
            if p.name.trimmed.isEmpty { p.name = "Profil" }
            model.updateProfile(p)
        }
        dismiss()
    }
}
