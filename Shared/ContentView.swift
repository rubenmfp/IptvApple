import SwiftUI
import UIKit

/// Étape 1 : écran « Bonjour » pour valider l'installation et la signature sur chaque appareil.
struct ContentView: View {
    @State private var presses = 0

    private var deviceLine: String {
        let d = UIDevice.current
        return "\(d.model) · \(d.systemName) \(d.systemVersion)"
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Bonjour")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                Text(deviceLine)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                Button {
                    presses += 1
                } label: {
                    Text(presses == 0 ? "Appuyer pour tester" : "Appuis : \(presses)")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                Text(versionLine)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(32)
        }
    }
}

#Preview {
    ContentView()
}
