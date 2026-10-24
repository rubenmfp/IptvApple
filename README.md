# IptvApple

Version Apple (iPhone et Apple TV) de l'appli Android IptvTV : lecteur Xtream Codes sombre, pour un usage privé.

## État (version 0.9)
Reprend les fonctions de l'appli Android IptvTV 0.14 :
- connexion par identifiants Xtream ou lien M3U ; catalogue enregistré, affiché tout de suite, mis à jour en arrière-plan ;
- Accueil, Films, Séries : « À la une », tuiles de catégories, rangées, Reprendre, favoris, « Recommandé pour vous »,
  « Populaires · France » (TMDB) ; noms nettoyés et versions regroupées (HD, SD, 4K…) ;
- recherche par titre, acteur ou réalisateur ; Mes listes ; appui long (favoris, listes, retirer de Reprendre) ;
- fiche : versions, qualité préférée, notes, distribution cliquable, saisons et épisodes (vus, nouveaux), TMDB (note,
  résumé français, bande-annonce, images, photos) ; Sorties (séries suivies, nouveaux épisodes) ;
- Direct : genres, liste déroulante filtrable, récentes, favoris, qualité par chaîne, guide XMLTV ; dans le lecteur,
  chaîne précédente / suivante et liste des chaînes sans couper celle en cours ;
- lecteur VLC : ±10 s, audio, sous-titres, vitesse, format d'image, rendu sonore (égaliseur) et volume amplifié,
  épisode suivant ou recommandations pendant le générique, autre qualité si la lecture échoue, diagnostic dans les réglages ;
- iPhone : téléchargement des films et épisodes (lus dans l'appli, comptés dans la reprise), lecture en paysage,
  double appui à gauche / à droite ;
- synchronisation par le Wi-Fi avec la TV Android (même protocole : `_iptvtv._tcp`, port 38472, même format de données).

Non repris : image dans l'image sur iPhone (le lecteur VLC ne le permet pas simplement), choix du décodeur Android
(sans objet : VLC décode lui-même), présentation TV / téléphone imposée (chaque appareil a sa propre appli).

## Organisation
- `Shared/` : code commun à l'iPhone et à l'Apple TV.
  `Core/` (noms, Xtream, données, guide, TMDB, suivis) est testé par `Tests/main.swift` dans le workflow ;
  `App/` (état de l'appli, téléchargements, synchronisation), `Player/` (VLC), `UI/` (écrans).
- `Frameworks/` : VLCKit 3.7 (MobileVLCKit, TVVLCKit), téléchargé par `tools/fetch_vlckit.sh`.
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
dans le trousseau de l'appareil. La synchronisation n'envoie jamais les identifiants Xtream (seulement une empreinte).
