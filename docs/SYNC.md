# Synchronisation Wi-Fi entre IptvTV (Android) et IptvApple (iPhone, Apple TV)

Document de référence commun aux deux applis. La version 1 (IptvTV 0.14) reste valable telle quelle ; l'extension
« profils » s'y ajoute sans la casser : une appli qui ne la connaît pas ignore simplement les nouvelles clés.

## Transport (inchangé)
- Service Bonjour / NSD `_iptvtv._tcp`, nom `IptvTV-` + 6 premiers caractères de l'identifiant de l'appareil, port 38472
  (ou un port libre annoncé par le service).
- Le client ouvre une connexion TCP, envoie **une ligne** JSON terminée par `\n`, lit **une ligne** en réponse, ferme.
- Message : `{"v":1,"acct":"…","dev":"Nom de l'appareil","recs":[[clé, date_ms, valeur|null], …]}`.
- `acct` = 12 premiers octets du SHA-256 de `serveur|utilisateur`, en hexadécimal (24 caractères). Serveur : espaces
  retirés, `/` finaux retirés, en minuscules. Utilisateur : espaces retirés. Si `acct` diffère, le serveur répond
  `{"err":"acct"}` et rien n'est appliqué.
- Le serveur applique les données reçues, puis répond avec toutes les siennes ; le client applique la réponse.

## Règle de fusion (inchangée)
Pour chaque clé : la date la plus récente l'emporte. Date absente localement = 1 si la donnée existe, 0 sinon.
On ignore un enregistrement si `date < date locale`, ou si `date == date locale` et (`valeur == null` ou la donnée
existe déjà). Sinon on enregistre la date reçue et, si la valeur diffère, on l'applique (`null` = suppression).
Une suppression est datée comme une modification (on garde la date même quand la donnée n'existe plus).

## Clés d'un profil (version 1 = profil principal)
| Clé | Valeur |
|---|---|
| `pos|<clé>` | `position_ms;durée_ms` (clé : `vod:123`, `ep:456`) |
| `seen|<clé>` | `1` (vu à 90 %) |
| `fav|<clé>` | `1` (clé : `vod:`, `series:`, `live:`) |
| `rate|<clé>` | `-1` je n'aime pas, `1` j'aime, `2` j'adore |
| `last|<id série>` | identifiant du dernier épisode lancé |
| `lq|live:<id>` | qualité choisie pour la chaîne (`FHD`, `HD`…) |
| `fw|series:<id>` | `{"v":id,"k":["saison:num",…triés],"n":[{"i":id,"s":saison,"e":num,"t":"titre"}]}` |
| `recent`, `rlive` | clés séparées par des virgules, la plus récente d'abord |
| `lists` | `{"nom":["vod:1",…],…}` dans l'ordre des listes |
| `hcats` | tableau JSON trié de `vod|nom`, `series|nom`, `live|nom` |
| `prefq` | qualité préférée |
| `accent` | indice dans la palette (0 Rouge, 1 Bleu, 2 Rose, 3 Vert, 4 Orange, 5 Violet, 6 Lime), 99 = personnalisée |
| `chue`, `csat` | teinte (0-360) et saturation (0-1) de la couleur personnalisée |
| `tmdb` | clé TMDB — **commune** : seulement avec le profil principal, jamais préfixée |

## Extension « profils »
1. **Profil principal** : identifiant `main`. Ses données gardent les clés ci-dessus sans préfixe (compatibilité 0.14).
   Une appli sans profils l'assimile à son unique jeu de données.
2. **Liste des profils** : une clé par profil, `prof|<id>`, y compris `prof|main` ;
   valeur `{"name":"Léa","color":5,"order":1}` ou `null` si le profil a été supprimé (suppression datée).
   - `id` : 8 caractères hexadécimaux en minuscules, tirés au hasard à la création ; `main` pour le principal.
   - `color` : indice dans la palette des profils, identique sur les deux applis :
     0 `#E50914`, 1 `#2196F3`, 2 `#1DB954`, 3 `#FF9800`, 4 `#9C27B0`, 5 `#E91E8C`, 6 `#00ACC1`, 7 `#8D6E63`.
   - `order` : position dans la liste (indicatif). 5 profils au plus côté interface.
   - Le profil principal ne peut pas être supprimé (un `null` pour `prof|main` est ignoré).
   - Recevoir `null` (plus récent) pour un profil : supprimer ce profil et toutes ses données locales ;
     si c'était le profil en cours, revenir au principal.
3. **Données des autres profils** : mêmes clés, préfixées par `@<id>:` — par exemple `@ab12cd34:pos|ep:456`,
   `@ab12cd34:lists`. Chaque profil a ses propres dates. `tmdb` n'est jamais préfixée.
4. **Ordre d'application** d'un message : d'abord les `prof|…` (création, renommage, suppression), puis les clés sans
   préfixe (profil principal), puis les clés `@id:` des profils qui existent après l'étape 1. Les clés d'un profil
   inconnu ou supprimé sont ignorées.
5. **Profil en cours** : propre à chaque appareil, jamais transmis.
6. Non synchronisés : réglages du lecteur (rendu sonore, format d'image, rotation), guide, synchronisation elle-même.
