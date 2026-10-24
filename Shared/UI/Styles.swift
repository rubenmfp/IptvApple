import SwiftUI

// Styles communs : rendu « premium » homogène sur l'iPhone et l'Apple TV.

/// Étiquette de catégorie (raccourci vers une rangée, tuile du Direct).
/// iPhone : texte fin dans un contour discret. Apple TV : texte seul qui s'éclaire, grossit et se souligne à la sélection.
struct ChipStyle: ButtonStyle {
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View { ChipBody(configuration: configuration, tint: tint) }
}

private struct ChipBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color?
    @Environment(\.isFocused) private var focused

    var body: some View {
        #if os(tvOS)
        configuration.label
            .font(.callout.weight(focused ? .semibold : .regular))
            .foregroundStyle(focused ? Color.white : (tint.map { $0.opacity(0.95) } ?? Theme.dim))
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .overlay(alignment: .bottom) {
                Capsule().fill(tint ?? Theme.accent).frame(height: 4).opacity(focused ? 1 : 0)
            }
            .scaleEffect(focused ? 1.12 : 1)
            .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 8)
            .animation(.easeOut(duration: 0.15), value: focused)
        #else
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.light)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill((tint ?? .white).opacity(tint == nil ? 0.05 : 0.18)))
            .overlay(Capsule().strokeBorder((tint ?? .white).opacity(tint == nil ? 0.22 : 0.5), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
        #endif
    }
}

/// Bouton d'action (fiche, « À la une »).
/// `prominent` : bouton principal (Lecture), blanc. `selected` : état actif (note donnée, favori, série suivie), couleur d'accent.
/// `round` : pictogramme seul, dans un cercle.
struct PillStyle: ButtonStyle {
    var prominent = false
    var selected = false
    var round = false
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, selected: selected, round: round)
    }
}

private struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let selected: Bool
    let round: Bool
    @Environment(\.isFocused) private var focusedEnv

    private var focused: Bool {
        #if os(tvOS)
        return focusedEnv
        #else
        return false
        #endif
    }

    private var fill: Color {
        if focused { return selected ? Theme.accent : .white }
        if selected { return Theme.accent.opacity(0.9) }
        return prominent ? .white.opacity(0.92) : .white.opacity(0.14)
    }
    private var ink: Color {
        if selected { return .white }
        return focused || prominent ? .black : .white
    }

    var body: some View {
        let h: CGFloat = Theme.tv ? 66 : 44
        configuration.label
            .font(Theme.tv ? .callout.weight(.semibold) : .subheadline.weight(.semibold))
            .labelStyle(round ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, round ? 0 : (Theme.tv ? 30 : 18))
            .frame(minWidth: round ? h : nil, minHeight: h, maxHeight: h)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(.white.opacity(selected && focused ? 0.9 : 0), lineWidth: 3))
            .scaleEffect(focused ? 1.1 : (configuration.isPressed ? 0.95 : 1))
            .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 14, y: 6)
            .animation(.easeOut(duration: 0.15), value: focused)
            .animation(.easeOut(duration: 0.2), value: selected)
    }
}

/// Style d'étiquette choisi à l'exécution.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Lien texte (« Lire la suite ») : couleur d'accent, plus petit, sans allure de bouton ; à la sélection (Apple TV),
/// un léger fond et un grossissement.
struct TextLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TextLinkBody(configuration: configuration) }
}

private struct TextLinkBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var focused
    var body: some View {
        configuration.label
            .font(Theme.tv ? .caption.weight(.bold) : .footnote.weight(.bold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, Theme.tv ? 12 : 0)
            .padding(.vertical, Theme.tv ? 6 : 2)
            .background(Capsule().fill(.white.opacity(Theme.tv && focused ? 0.14 : 0)))
            .scaleEffect(Theme.tv && focused ? 1.08 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// « J'adore » : deux pouces levés.
struct DoubleThumb: View {
    var filled = false
    var size: CGFloat = Theme.tv ? 30 : 22
    var body: some View {
        ZStack {
            Image(systemName: filled ? "hand.thumbsup.fill" : "hand.thumbsup")
                .offset(x: -size * 0.22, y: size * 0.06)
                .opacity(0.75)
            Image(systemName: filled ? "hand.thumbsup.fill" : "hand.thumbsup")
                .offset(x: size * 0.22, y: -size * 0.06)
        }
        .font(.system(size: size * 0.82, weight: .semibold))
        .frame(width: size * 1.5, height: size)
    }
}

/// Pictogramme d'une note : -1 je n'aime pas, 1 j'aime, 2 j'adore, 0 pas de note.
struct RatingIcon: View {
    let value: Int
    var filled = false
    var size: CGFloat = Theme.tv ? 30 : 22
    var body: some View {
        switch value {
        case 2: DoubleThumb(filled: filled, size: size)
        case -1: Image(systemName: filled ? "hand.thumbsdown.fill" : "hand.thumbsdown").font(.system(size: size * 0.9, weight: .semibold))
        default: Image(systemName: filled ? "hand.thumbsup.fill" : "hand.thumbsup").font(.system(size: size * 0.9, weight: .semibold))
        }
    }
}

let ratingLabels: [Int: String] = [-1: "Je n'aime pas", 1: "J'aime", 2: "J'adore"]

extension View {
    /// Apple TV : la zone devient une « section » de sélection. Descendre depuis n'importe quel bouton de la ligne
    /// du dessus y entre, même sans bouton aligné verticalement.
    @ViewBuilder func tvSection() -> some View {
        #if os(tvOS)
        self.focusSection()
        #else
        self
        #endif
    }
}
