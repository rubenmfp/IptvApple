import SwiftUI

/// Connexion : identifiants Xtream, ou lien M3U décomposé par l'appli.
struct LoginView: View {
    @EnvironmentObject var model: AppModel

    @State private var mode = 0          // 0 = identifiants, 1 = lien M3U
    @State private var host = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var link = ""
    @State private var busy = false
    @State private var err: String?

    private var parsed: XtreamAccount? { Xtream.parseLink(link) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.tv ? 28 : 18) {
                HStack(spacing: 14) {
                    Image(systemName: "play.tv.fill").font(.system(size: Theme.tv ? 56 : 34)).foregroundStyle(Theme.accent)
                    Text("IptvTV").font(.system(size: Theme.tv ? 56 : 34, weight: .bold)).foregroundStyle(.white)
                }
                Text("Connectez-vous à votre fournisseur. Les identifiants restent sur cet appareil, dans le trousseau.")
                    .foregroundStyle(Theme.dim)

                Picker("Méthode", selection: $mode) {
                    Text("Identifiants").tag(0)
                    Text("Lien M3U").tag(1)
                }
                .pickerStyle(.segmented)

                if mode == 0 {
                    field("Serveur (ex. http://exemple.com:8080)", text: $host, url: true)
                    field("Utilisateur", text: $user)
                    SecureField("Mot de passe", text: $pass)
                        .textContentType(.password)
                        .modifier(FieldStyle())
                } else {
                    field("Lien M3U", text: $link, url: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Le lien ressemble à : http://serveur:port/get.php?username=UTILISATEUR&password=MOTDEPASSE&type=m3u_plus")
                        Text("L'appli en tire le serveur (avant « /get.php »), l'utilisateur (après « username= ») et le mot de passe (après « password= »).")
                        if let p = parsed {
                            Text("Lu : serveur \(p.host) · utilisateur \(p.user) · mot de passe de \(p.pass.count) caractères")
                                .foregroundStyle(Theme.light)
                        } else if !link.trimmed.isEmpty {
                            Text("Lien non reconnu.").foregroundStyle(Theme.accent)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                }

                if let err {
                    Text(err).foregroundStyle(Theme.accent).font(.callout)
                }

                Button {
                    connect()
                } label: {
                    HStack(spacing: 10) {
                        if busy { ProgressView() }
                        Text(busy ? "Connexion…" : "Se connecter").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.tv ? 0 : 6)
                }
                #if os(iOS)
                .buttonStyle(.borderedProminent)
                #endif
                .disabled(busy)

                #if os(tvOS)
                Text("Astuce : quand le clavier s'affiche sur la TV, votre iPhone propose aussi de saisir le texte.")
                    .font(.footnote).foregroundStyle(Theme.dim)
                #endif
            }
            .padding(Theme.tv ? 60 : 24)
            .frame(maxWidth: Theme.tv ? 1000 : 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func field(_ title: String, text: Binding<String>, url: Bool = false) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(url ? .URL : .default)
            .modifier(FieldStyle())
    }

    private func connect() {
        err = nil
        let acct: XtreamAccount
        if mode == 0 {
            let h = Xtream.normalizeHost(host)
            guard !h.isEmpty, !user.trimmed.isEmpty, !pass.isEmpty else { err = "Remplissez le serveur, l'utilisateur et le mot de passe."; return }
            acct = XtreamAccount(host: h, user: user.trimmed, pass: pass)
        } else {
            guard let p = parsed else { err = "Lien non reconnu : collez le lien M3U complet fourni par votre fournisseur."; return }
            acct = p
        }
        busy = true
        Task {
            err = await model.login(acct)
            busy = false
        }
    }
}

struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .padding(12)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
        #else
        content
        #endif
    }
}
