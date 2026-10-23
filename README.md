# IptvApple

Version Apple (iPhone et Apple TV) de l'appli Android IptvTV : lecteur Xtream Codes sombre, pour un usage privé.

## État
Étape 1 : appli « Bonjour » qui valide l'installation et la signature sur chaque appareil.

## Organisation
- `Shared/` : code commun à l'iPhone et à l'Apple TV.
- `iOS/`, `tvOS/` (plus tard) : code propre à chaque appareil.
- `IptvApple.xcodeproj` : projet Xcode, généré par `python3 tools/gen_project.py` (à relancer après un ajout de fichier).
- Cibles : `IptvApple` (iPhone, iPad) et `IptvAppleTV` (Apple TV). Minimum iOS 17 / tvOS 17.
- Compatible avec Xcode 15.2 (Mac sous macOS Ventura). Le workflow GitHub vérifie la compilation à chaque envoi.

## Règles
Aucun identifiant (serveur, utilisateur, mot de passe, clé TMDB, jeton) dans le code ou le dépôt : l'appli les garde
dans le trousseau de l'appareil.
