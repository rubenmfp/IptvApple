# Prompt pour l'appli Android IptvTV : synchronisation par GitHub (et profils)

Copier tout ce qui suit dans la conversation de l'appli Android, avec le fichier `SYNC.md` joint.

---

Ajoute à l'appli Android IptvTV une **synchronisation par GitHub**, compatible avec la version Apple (IptvApple 0.19),
en plus de la synchronisation Wi-Fi existante. Le format exact est dans le fichier `SYNC.md` joint (sections
« Extension profils » et « Synchronisation par GitHub ») : il fait foi, les deux applis doivent produire et lire
exactement les mêmes données.

Contexte : usage privé, je partage l'appli avec 2 ou 3 amis. La synchronisation par GitHub doit être **facultative** :
tant qu'aucun dépôt ni jeton n'est saisi, rien ne change (mes amis ne doivent pas être concernés).

Règle de sécurité (impérative) : n'écris **aucun identifiant** dans le code, les fichiers du projet ou les notes
(serveur, utilisateur, mot de passe Xtream, clé TMDB, jeton GitHub). Le jeton GitHub est saisi sur l'appareil et rangé
de façon sûre (EncryptedSharedPreferences ou Android Keystore) ; il n'est jamais envoyé, ni en Wi-Fi ni dans le fichier.
La clé TMDB ne va jamais sur GitHub.

À faire :
1. **Profils** (si ce n'est pas déjà fait) : profils comme sur la version Apple, synchronisés selon `SYNC.md`
   (`prof|<id>` avec `{"name","color","order"}` ou `null`, données des autres profils préfixées `@<id>:`, profil
   principal `main` sans préfixe, palette des couleurs de profil identique, ordre d'application prof → principal → autres).
   La synchronisation Wi-Fi doit envoyer et recevoir ces clés.
2. **Moteur GitHub** (un objet du type `CloudSync`, sur Dispatchers.IO) :
   - fichier `iptvtv/<acct>.json` dans le dépôt privé saisi (`pseudo/dépôt`, accepter aussi une adresse
     `https://github.com/pseudo/dépôt`) ; `acct` = même empreinte que la synchronisation Wi-Fi ;
   - lecture, application locale, fusion, écriture avec le `sha` lu, nouvel essai sur 409/422 (3 au plus), exactement
     comme décrit dans `SYNC.md` ; écrire seulement si la fusion diffère de ce qui a été lu ;
   - même liste de données que le Wi-Fi, **sans `tmdb`** ;
   - quand : 2 s après l'ouverture, toutes les 5 minutes tant que l'appli est au premier plan, 1 minute après une
     modification (regroupement), et au passage en arrière-plan s'il reste des modifications (WorkManager ou tâche
     courte) ; bouton « Synchroniser maintenant » ;
   - après des données reçues, l'appli relit ce qui est partagé (comme après un échange Wi-Fi).
3. **Réglages > Synchronisation par GitHub** :
   - champ « Dépôt privé (ex. pseudo/iptv-synchro) », champ jeton masqué (« Jeton enregistré ✓ » s'il y en a un),
     boutons « Enregistrer et synchroniser » et « Effacer le jeton » ;
   - état : « Synchronisé à 17:52 · 3 élément(s) reçu(s) · envoyé », ou l'erreur en clair : 401 jeton refusé,
     403 jeton sans droit d'écriture (« Contents : Read and write »), 404 dépôt introuvable ou jeton sans accès ;
     avertir si le dépôt est public (`GET /repos/<dépôt>` → `"private": false`) ;
   - aide : sur github.com, créer un dépôt privé vide ; Settings > Developer settings > Fine-grained tokens > Generate
     new token, « Only select repositories » = ce dépôt, permission « Contents : Read and write ».
     Sur la TV, saisie possible avec le clavier du téléphone (télécommande Google TV) ou en collant.
4. **Tests** : fusion (plus récent, valeur contre `null` à date égale, clé inconnue gardée, données d'un profil
   supprimé retirées), aller-retour du format JSON, application d'un fichier produit par la version Apple
   (exemple : `{"v":1,"acct":"…","dev":"Apple TV","updated":1761930000000,"recs":[["fav|vod:7",1761930000000,"1"],
   ["prof|ab12cd34",1761930000000,"{\"name\":\"Léa\",\"color\":5,\"order\":1}"],["@ab12cd34:pos|ep:3",1761930000000,"5000;60000"]]}`).
5. Mets à jour le README (section Synchronisation) et le numéro de version.

Explique-moi simplement ce qui a changé une fois fini (je ne suis pas développeur), et comment le régler sur la TV.
