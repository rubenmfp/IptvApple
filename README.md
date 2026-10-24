# IptvApple

Version Apple (iPhone et Apple TV) de l'appli Android IptvTV : lecteur Xtream Codes sombre, pour un usage privé.

## État
Étape 2 : connexion (identifiants Xtream ou lien M3U) et catalogue films et séries en rangées par catégorie.

## Organisation
- `Shared/` : code commun à l'iPhone et à l'Apple TV.
- `iOS/`, `tvOS/` (plus tard) : code propre à chaque appareil.
- `IptvApple.xcodeproj` : projet Xcode, généré par `python3 tools/gen_project.py` (à relancer après un ajout de fichier).
- Cibles : `IptvApple` (iPhone, iPad) et `IptvAppleTV` (Apple TV). Minimum iOS 17 / tvOS 17.
- Compatible avec Xcode 15.2 (Mac sous macOS Ventura). Le workflow GitHub vérifie la compilation à chaque envoi.

## Installation (compte Apple gratuit)
Le Mac de l'utilisateur (MacBook Pro 2017, macOS Ventura, Xcode 15.2 au maximum) ne peut pas installer directement sur
iOS 27 / tvOS 27 (« developer disk image could not be mounted »). On passe donc par **Sideloadly** :
1. GitHub fabrique l'appli à chaque envoi (Xcode 15.2) et publie `IptvTV-iPhone-x.y.ipa` et `IptvTV-AppleTV-x.y.ipa`
   dans *Releases* (« Dernière version »).
2. Sur le Mac : Sideloadly, appareil choisi dans « iDevice », fichier glissé sur l'icône IPA, identifiant Apple, Start.
   Apple TV : même Wi-Fi, écran Réglages > Télécommandes et appareils > App et appareils distants ouvert.
3. Validité 7 jours. iPhone : renouvellement automatique par Sideloadly. Apple TV : à refaire à la main (le renouvellement
   automatique Apple TV de Sideloadly est réservé à son Patreon).

## Règles
Aucun identifiant (serveur, utilisateur, mot de passe, clé TMDB, jeton) dans le code ou le dépôt : l'appli les garde
dans le trousseau de l'appareil.
