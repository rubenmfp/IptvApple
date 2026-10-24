import SwiftUI

enum Theme {
    static let bg = Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x10 / 255)
    static let panel = Color(red: 0x17 / 255, green: 0x1A / 255, blue: 0x20 / 255)
    static let dim = Color(red: 0xB4 / 255, green: 0xB8 / 255, blue: 0xC0 / 255)
    static let light = Color(red: 0xE6 / 255, green: 0xE8 / 255, blue: 0xEC / 255)
    /// Couleur d'accent choisie dans les réglages (rouge par défaut).
    static var accent: Color { Accent.color(Store.accent) }
    static let gold = Color(red: 1, green: 0xD5 / 255, blue: 0x4F / 255)

    #if os(tvOS)
    static let tv = true
    static let posterWidth: CGFloat = 200
    static let edge: CGFloat = 0          // la TV a déjà ses marges de sécurité
    static let rowGap: CGFloat = 36
    static let cardGap: CGFloat = 36
    static let heroHeight: CGFloat = 640
    #else
    static let tv = false
    static let posterWidth: CGFloat = 112
    static let edge: CGFloat = 16
    static let rowGap: CGFloat = 22
    static let cardGap: CGFloat = 10
    static let heroHeight: CGFloat = 470
    #endif

    static var rowTitle: Font { tv ? .title3.weight(.semibold) : .headline }
}

/// Petite étiquette de qualité (« 4K », « FHD »…).
struct QualityBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: Theme.tv ? 18 : 10, weight: .bold))
            .foregroundStyle(Theme.gold)
            .padding(.horizontal, Theme.tv ? 8 : 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// Palette de la couleur d'accent (comme sur Android), plus une couleur personnalisée.
enum Accent {
    static let palette: [(String, UInt32)] = [("Rouge", 0xE50914), ("Bleu", 0x2196F3), ("Rose", 0xE91E8C), ("Vert", 0x1DB954),
                                              ("Orange", 0xFF9800), ("Violet", 0x9C27B0), ("Lime", 0x9BD84E)]
    static let customIndex = 99           // comme sur Android

    static func rgb(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func color(_ i: Int) -> Color {
        if i == customIndex { return Color(hue: Store.customHue / 360, saturation: Store.customSat, brightness: 0.92) }
        return rgb(palette[(0..<palette.count).contains(i) ? i : 0].1)
    }
}
