# Captain Notes

## Description du projet

Une interface PRONOTE pour consulter l’agenda, les devoirs, les notes, les menus et les messages des enfants, avec des profils Famille, Parent et Enfant.

Le profil Famille regroupe les données des enfants. Chaque enfant peut aussi se connecter à son propre espace ; les parents disposent en plus de leur messagerie personnelle. Les devoirs faits et les messages lus sont synchronisés avec PRONOTE.

## Motivations

- Avoir accès à toutes les informations essentielles en un coup d'oeil, en retirant le superflu.
- Aider les parents à suivre l'avancement des devoirs
- Donner aux enfants un accès Famille à pronote sur un périphérique dédié, sans distraction (comme une tablette avec [Fully Kiosk Browser](https://play.google.com/store/apps/details?id=de.ozerov.fully&referrer=utm_source%3D/fully-home-en%26utm_content%3Dtext-link))

La simplicité est la priorité, toutes les fonctionnalités de pronote ne seront pas portées.

## Techno

Développée avec Elixir et Phoenix LiveView. L'historique des notes et moyennes utilise SQLite, sans serveur de base de données séparé.
Code massivement généré par intelligence artificielle (OpenAI Codex).
Prévu pour tourner avec Docker en production.

## Roadmap

- [x] emploi du temps
- [x] liste des devoirs 
- [x] liste des notes
- [x] menu de la cantine
- [x] évènements
- [x] version mobile
- [x] thèmes jours / nuits
- [x] marquer les devoirs faits
- [x] sécurisation avec code PIN
- [x] mode PWA (ajouter l'app à l'accueil du smartphone)
- [x] consulter les messages des enfants
- [x] consulter les messages des parents
- [x] comptes famille, enfants et parents séparés (pincode individuels)
- [x] consulter les resources associées aux devoirs
- [x] mettre un cache en lecture sur les API pronote
- [x] améliorer les écrans de notes et moyennes
- [ ] contacter la vie scolaire (parent)
- [ ] push notif prof absent
- [ ] push notif nouvelle note
- [ ] push notif nouveau message

## Screenshots

### Desktop

![Vue desktop 1 de Captain Notes](screenshots/desktop-01.jpg)

![Vue desktop 2 de Captain Notes](screenshots/desktop-02.jpg)

![Vue desktop 3 de Captain Notes](screenshots/desktop-03.jpg)

### Mobile

<p>
  <img src="screenshots/mobile-01.jpg" alt="Vue mobile 1 de Captain Notes" width="250" />
  <img src="screenshots/mobile-02.jpg" alt="Vue mobile 2 de Captain Notes" width="250" />
  <img src="screenshots/mobile-03.jpg" alt="Vue mobile 3 de Captain Notes" width="250" />
</p>

## Lancer le projet en local

Prérequis : Elixir et Erlang/OTP (versions utilisées par Docker : Elixir 1.19.4 et OTP 28).

```sh
mix setup
cp -n .envrc.example .envrc
```

Compléter `.envrc` :

- `PRONOTE_URL` : URL HTTPS de base, par exemple `https://mon-college.index-education.net/pronote/`, **sans** `parent.html` ni `eleve.html` (connexion directe, sans ENT ni QR code).
- `PRONOTE_FAMILY_USERNAME`, `PRONOTE_FAMILY_PASSWORD`, `PRONOTE_FAMILY_PIN_CODE` : compte parent utilisé par le profil **Famille**, qui permet de consulter tous ses enfants et leurs messages.
- `PRONOTE_PARENT_n_USERNAME`, `_PASSWORD`, `_FIRST_NAME`, `_PIN_CODE` : un profil par parent. Il accède aux enfants rattachés à son compte PRONOTE et à **Messages suivi de son prénom** dans le menu utilisateur.
- `PRONOTE_CHILD_n_USERNAME`, `_PASSWORD`, `_FIRST_NAME`, `_PIN_CODE` : un profil par enfant, limité à son propre compte élève. Son prénom doit correspondre à celui de PRONOTE. `_THEME` (`blue` ou `green`) et `_AVATAR_BASE64` restent facultatifs ; le thème affiché est toujours celui de l’enfant.

Remplacer `n` par `1`, `2`, etc. Configurer uniquement les profils souhaités. Chaque profil proposé au login nécessite ses identifiants et un **PIN de 8 chiffres** ; les parents et enfants nécessitent aussi un prénom. Un profil incomplet n’est pas proposé. Sans aucun profil complet, l’accès reste fermé.

Les identifiants élèves permettent aussi au profil Famille et aux parents de consulter les messages des enfants et de marquer leurs devoirs faits. Ils peuvent être renseignés sans PIN enfant si cet enfant ne doit pas avoir de connexion individuelle. Les messages des parents sont réservés à leur profil personnel. Tous les changements de statut lu/non lu ou fait/à faire restent explicites.

Au login, choisir un profil puis saisir son PIN. **Rester connecté** est décoché par défaut : session de **1 heure**, ou **30 jours** si coché, à partir de la connexion, sans prolongation automatique. Après trois erreurs sur un profil, l’attente est d’une minute, puis augmente d’une minute à chaque nouvel échec. Ces compteurs sont en mémoire et remis à zéro au redémarrage ; les sessions navigateur restent valables si la configuration et le secret de signature ne changent pas.

```sh
source .envrc
mix phx.server
```

Ouvrir [localhost:4000](http://localhost:4000). Après modification des variables, les recharger et redémarrer le serveur. Avec direnv, `direnv allow` remplace `source .envrc`.

Pour lancer les vérifications : `mix precommit`.

### Cache des lectures PRONOTE

Les réponses réussies sont conservées uniquement en mémoire : 5 minutes pour les cours, événements, devoirs, messages, notes et moyennes, 30 minutes pour les menus. Une entrée expirée est rechargée lors de la prochaine lecture. Un traitement supervisé relit aussi toutes les cinq minutes les cours de la semaine courante, les événements, les notes de la période courante et les messages accessibles de tous les profils configurés, même sans navigateur connecté. Le premier cycle commence cinq minutes après le démarrage. Les devoirs et menus restent chargés à la demande. Les données peuvent donc refléter l'état de PRONOTE au moment de la dernière lecture pendant cette durée.

Les cycles ne se chevauchent pas ; un cycle encore en cours fait sauter le prochain déclenchement. Les requêtes passent par les sessions sérialisées habituelles. Les erreurs sont isolées par profil et retentées au prochain cycle ; les messages ne sont jamais marqués lus automatiquement. Les caches agenda, notes et messages du profil sont invalidés avant la relecture. Les pages ouvertes de ce profil se rechargent à la fin du cycle, sauf si un chargement ou une écriture est en cours. Pour désactiver ce traitement : `PRONOTE_BACKGROUND_REFRESH=false`, puis redémarrer l'application.

## Construire et lancer en production avec Docker

Prérequis : Docker avec Buildx et Compose. Depuis le dossier du projet, construire l’image Linux amd64 :

```sh
docker buildx build --platform linux/amd64 --load -t pronotex:local .
cp -n .env.docker.example env
chmod 600 env
```

Compléter le fichier **`env`** (nom attendu par `docker-compose.yml`) avec les mêmes variables PRONOTE qu’en local, sans `export`, puis renseigner :

- `PHX_HOST` : nom de domaine de l’application, sans protocole ni chemin.
- `SECRET_KEY_BASE` : secret généré avec `mix phx.gen.secret`, à conserver lors des mises à jour.

Les secrets ne sont pas intégrés à l’image. Ne pas versionner `env`. Pour les avatars, utiliser les variables `PRONOTE_CHILD_n_AVATAR_BASE64` décrites dans le fichier exemple.

```sh
# Avant le premier lancement : configurer le stockage (voir section ci-dessous).
cp .env.example .env
# Adapter DATA_DIR, APP_UID et APP_GID dans .env avant de continuer.
docker compose up -d
docker compose ps
docker compose logs --tail=100 -f pronotex
```

Le conteneur écoute sur **127.0.0.1:4123** sur la machine hôte. Configurer un reverse proxy avec un certificat valide pour servir `https://<PHX_HOST>` et transmettre les requêtes vers `http://127.0.0.1:4123`, avec `X-Forwarded-Proto: https` et la prise en charge des WebSockets. HTTPS est nécessaire aux cookies de connexion en production.

Pour déployer sur une autre machine, exporter l’image :

```sh
docker save -o pronotex-image.tar pronotex:local
```

Transférer l’archive, `docker-compose.yml`, le fichier `env` et la configuration `.env` sur la machine cible, puis exécuter dans leur dossier :

```sh
docker load -i pronotex-image.tar
docker compose up -d --force-recreate
```

Pour une mise à jour, reconstruire l’image et transférer aussi le `docker-compose.yml` à jour, puis relancer `docker compose up -d --force-recreate`. Cette commande est également nécessaire après une modification de `env`.

### Historique des notes et des moyennes

SQLite et Ecto enregistrent chaque réponse fraîche de PRONOTE, y compris celles du rafraîchissement périodique. Les lectures du cache ne créent pas d'observation. L'historique est partagé entre les profils consultant le même identifiant d'élève PRONOTE, et séparé par établissement, année scolaire et période.

- Chaque note conserve obligatoirement `graded_on` (date de l'évaluation), `published_at` (publication) et `first_seen_at` (première découverte, en UTC). La réponse actuellement exploitée ne fournit pas de date de publication vérifiée : on utilise la première découverte avec `publication_estimated = true`. Cette date ne change pas à chaque lecture. Une date fiable fournie ultérieurement pourra remplacer l'estimation.
- Les corrections de notes conservent une révision. Une note absente d'une réponse ultérieure reste dans l'historique : son absence ne prouve pas une suppression.
- Les moyennes officielles générales, par matière et de classe sont enregistrées ensemble, à la date de leur observation, uniquement lorsqu'elles changent. Le premier import est donc daté du jour de sa récupération, sans reconstituer un passé fictif. Les valeurs PRONOTE sont conservées telles quelles, y compris les valeurs manquantes et les notes non numériques.

Les migrations s'exécutent automatiquement avant les sessions PRONOTE au démarrage. En développement, la base est `data/pronotex_dev.db` (ignorée par Git) ; les tests utilisent une base en mémoire. Après ajout d'une dépendance ou du dépôt, redémarrer le serveur de développement.

En Docker, le dossier `DATA_DIR` du serveur est monté sur `/app/data`. Avec `DATA_DIR=.` et le Compose dans `/volume1/docker/pronotex`, la base se trouve exactement dans **`/volume1/docker/pronotex/pronotex.db`**. Le dossier entier est monté pour que SQLite puisse aussi créer `pronotex.db-wal` et `pronotex.db-shm`. Utiliser un disque local au serveur, pas un partage SMB/NFS.

#### Configuration du stockage

Copier `.env.example` vers `.env`, à côté de `docker-compose.yml`, sur le serveur. Ce fichier configure Compose ; le fichier `env` contient toujours les secrets de l'application.

```dotenv
DATA_DIR=.
APP_UID=1000
APP_GID=1000
DOCKER_PLATFORM=linux/amd64
```

Remplacer `APP_UID` et `APP_GID` par les résultats de `id -u` et `id -g` du compte qui possède le dossier sur le serveur. Pour un autre emplacement, renseigner par exemple `DATA_DIR=/srv/pronotex/data`, créer ce dossier et donner à ce compte le droit d'y écrire. Le conteneur utilise cette identité non privilégiée ; aucun changement récursif de propriétaire n'est effectué. Le dossier doit exister : Compose refuse de le créer implicitement avec des permissions inadaptées. La base garde son chemin interne `/app/data/pronotex.db`.

Le script local `deploy.sh` crée automatiquement `.env` au premier déploiement, avec `DATA_DIR=.` et l'UID/GID du compte SSH ; il préserve ensuite ce fichier. Ses destinations sont configurables via `DEPLOY_SHARED_DIR` (défaut `/Volumes/docker/pronotex`), `DEPLOY_REMOTE_DIR` (`/volume1/docker/pronotex`), `DEPLOY_HOST`, `DEPLOY_PORT` et `DOCKER_PLATFORM`. Les deux dossiers doivent désigner le même emplacement, vu depuis le poste local et depuis le serveur. Ce script local est ignoré par Git ; le déploiement manuel utilise directement les fichiers Compose et les exemples versionnés.

#### Migration du volume SQLite existant

Si un précédent déploiement utilise déjà le volume nommé, `deploy.sh` s'arrête avant de recréer le conteneur. Pour conserver l'historique, depuis le dossier du projet sur le serveur :

```sh
container=$(sudo docker compose ps -aq pronotex)
sudo docker compose stop pronotex
# Choisir un dossier temporaire neuf ; ne pas écraser une base déjà présente.
mkdir sqlite-migration
sudo docker cp "$container:/app/data/." ./sqlite-migration/
```

Déplacer les fichiers `pronotex.db`, `pronotex.db-wal` et `pronotex.db-shm` présents dans ce dossier vers `DATA_DIR`, sans écraser de fichiers existants. Donner uniquement à ces fichiers l'UID/GID configurés dans `.env`. Puis exécuter `sudo docker compose up -d --force-recreate`. Conserver l'ancien volume jusqu'à vérification de l'historique ; ne pas le supprimer pendant la migration.

Pour sauvegarder simplement : arrêter le service (`docker compose stop pronotex`), sauvegarder **la base et les éventuels fichiers WAL/SHM du dossier**, puis redémarrer (`docker compose start pronotex`). Restaurer service arrêté en conservant les permissions. Les sauvegardes contiennent des données scolaires personnelles. Les fichiers du dossier restent présents après suppression ou recréation des conteneurs.

## Notifications de nouvelles notes

Activer **Réglages → Activer les notifications** sur chaque appareil, puis accepter l'autorisation du navigateur. Sur iPhone/iPad, utiliser l'application ajoutée à l'écran d'accueil (iOS/iPadOS 16.4 minimum) ; en production, HTTPS est requis. Le corps de la notification liste les matières concernées, sans les suffixes après `>` et sans doublons. Une notification « Edgar a eu de nouvelles notes » regroupe les notes découvertes dans une même réponse pour cet enfant. Un clic ouvre sa page Notes ; si la session a expiré, il faut se reconnecter.

Le serveur relève les données toutes les cinq minutes, uniquement **entre 07 h et 22 h**, dans le fuseau `TZ` (Europe/Paris par défaut dans Docker, configurable dans `.env`). Une requête déjà en cours peut finir après 22 h, mais les lectures suivantes attendront le matin. Les consultations manuelles restent disponibles. `PRONOTE_BACKGROUND_REFRESH=false` désactive ce relevé automatique. L'envoi des notifications utilise les services Web Push du navigateur (Apple, Google, Mozilla ou Microsoft) et fonctionne même avec l'app fermée ; il n'exige aucun compte Firebase. Le serveur doit pouvoir les joindre en HTTPS. La réception dépend aussi du réseau et des réglages de notifications de l'appareil.

Les abonnements, les références de comparaison, la file d'envoi et les clés VAPID sont conservés dans **la même base SQLite persistante**. Les migrations et la génération initiale des clés sont automatiques : aucune commande supplémentaire après déploiement. Sauvegarder cette base protège aussi l'identité du serveur push. Le contact VAPID utilise `https://PHX_HOST` ; on peut définir `WEB_PUSH_SUBJECT=mailto:admin@example.com` dans le fichier `env`. Ne pas partager la base : elle contient la clé privée et les abonnements.

Le premier relevé d'un enfant pour un profil et une période constitue une référence silencieuse. Les identifiants PRONOTE pouvant changer à la reconnexion, la détection compare le nombre de notes par matière et date d'évaluation, sans alerter lors d'une correction de score ou de commentaire. Elle conserve le maximum observé : une suppression suivie d'un remplacement à la même date et dans la même matière peut donc passer inaperçue. Les noms complets ambigus au sein d'un profil ne déclenchent pas d'alertes. Les profils ont des abonnements séparés ; un appareil est lié au dernier profil pour lequel les notifications ont été activées. Une déconnexion ou une nouvelle connexion désactive cet abonnement : réactiver ensuite l'option dans Réglages.

Les échecs d'envoi temporaires sont réessayés avec un délai croissant (huit tentatives maximum, expiration après 24 h). Les abonnements révoqués sont supprimés. Le même identifiant de notification est conservé lors des tentatives pour limiter les doublons à l'affichage ; une livraison exactement une fois n'est pas garantie par Web Push. Le service worker sert uniquement aux notifications et ne met aucune page privée en cache.

### Déclencher manuellement une notification

Depuis le dossier Compose du serveur (par exemple `/volume1/docker/pronotex`), après déploiement :

```sh
docker compose exec pronotex /app/bin/pronotex rpc 'IO.inspect(Pronotex.Push.notify_grades("family", "Edgar"))'
```

La fonction vérifie qu'Edgar appartient au profil `family`, puis met une notification en file pour chacun de ses appareils abonnés et réveille immédiatement le service d'envoi. `{:ok, %{queued: 1}}` signifie qu'un appareil est ciblé, pas que la réception est déjà confirmée. `{:error, :no_subscriptions}` indique qu'il faut activer les notifications dans Réglages pour ce profil. Remplacer `family` par l'identifiant du profil voulu (`child-1`, `parent-1`, etc.) et utiliser le nom complet en cas de prénoms identiques. Une indisponibilité PRONOTE est signalée par `{:error, :pronote_unavailable}`.

L'appel ne lit ni ne modifie les notes, l'historique ou la référence de comparaison. Chaque appel volontaire déclenche une nouvelle notification, y compris la nuit ; seule la collecte automatique est suspendue de 22 h à 7 h. Pour cibler une période précise : `Pronotex.Push.notify_grades("family", "Edgar", period: "semester1")`. Sans cette option, le lien ouvre la période courante. Pour renseigner le texte de la notification manuelle, passer `subjects: ["MATHÉMATIQUES", "ESPAGNOL LV2 > Compréhension"]` ; sans cette liste, le corps reste vide.

## Licence

Captain Notes est distribué sous [licence MIT](LICENSE). Elle autorise l'utilisation, la modification et la redistribution, y compris commerciales, sous réserve de conserver la notice de copyright et la licence. Le logiciel est fourni sans garantie. Les dépendances et éléments tiers restent soumis à leurs licences respectives.

Ce projet est un développement indépendant, réalisé sans l'accord d'Index Éducation, à des fins personnelles et non commerciales. Il n'est ni affilié à Index Éducation, ni approuvé ou soutenu par cette société.
