import SwiftUI

#if os(tvOS)

/// Clavier AZERTY intégré à l'écran (Apple TV) : la saisie reste visible avec les résultats dessous, qui se mettent à jour
/// au fil des lettres, sans clavier plein écran. « Dictée » ouvre le clavier d'Apple (dictée, saisie depuis l'iPhone).
struct TVKeyboard: View {
    @Binding var text: String
    var placeholder = "Rechercher"
    @State private var numbers = false
    @FocusState private var focus: String?

    private static let letters: [[String]] = [
        ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"],
        ["W", "X", "C", "V", "B", "N", "É", "È", "À", "Ç"],
    ]
    private static let digits: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "'", ":", "&", "!", "?", ".", ",", "(", ")"],
        ["Ê", "Ë", "Ï", "Î", "Ô", "Ù", "Û", "Ü", "Æ", "Œ"],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                if text.isEmpty {
                    Text(placeholder).foregroundStyle(Theme.dim)
                } else {
                    Text(text).foregroundStyle(.white) + Text("▏").foregroundStyle(Theme.accent)
                }
            }
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .padding(.bottom, 4)

            ForEach(Array((numbers ? Self.digits : Self.letters).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { k in
                        Button { text += k.lowercased() } label: { Text(k).frame(width: 74, height: 62) }
                            .buttonStyle(KeyStyle())
                            .focused($focus, equals: k)
                    }
                }
            }
            HStack(spacing: 10) {
                Button { text += " " } label: { Label("Espace", systemImage: "space").labelStyle(.iconOnly).frame(width: 242, height: 62) }
                    .buttonStyle(KeyStyle())
                Button { if !text.isEmpty { text.removeLast() } } label: { Image(systemName: "delete.left").frame(width: 158, height: 62) }
                    .buttonStyle(KeyStyle())
                Button { text = "" } label: { Text("Effacer").frame(width: 158, height: 62) }
                    .buttonStyle(KeyStyle())
                Button { numbers.toggle() } label: { Text(numbers ? "ABC" : "123").frame(width: 158, height: 62) }
                    .buttonStyle(KeyStyle(selected: numbers))
                // clavier d'Apple : dictée par la télécommande, ou saisie depuis l'iPhone
                TextField("Dictée, iPhone", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(width: 300)
            }
        }
        .focusSection()
        .defaultFocus($focus, "A")
    }
}

/// Touche : grise, blanche et plus grande à la sélection.
private struct KeyStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { KeyBody(configuration: configuration, selected: selected) }
}

private struct KeyBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(focused ? .black : .white)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(focused ? Color.white : (selected ? Theme.accent.opacity(0.6) : Color.white.opacity(0.1))))
            .scaleEffect(focused ? 1.12 : (configuration.isPressed ? 0.95 : 1))
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 8, y: 4)
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}
#endif
