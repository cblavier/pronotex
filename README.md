# Captain Notes

## Description du projet

Une interface PRONOTE épurée pour consulter l’agenda, les devoirs, les notes, les menus et les messages des enfants, avec des profils Famille, Parent et Enfant.

Chaque membre de la famille peut se connecter à son propre espace ; un compte famille est également disponible pour accéder et gérer les devoirs de l'ensemble de la famille.

Les notes et moyennes sont historisées dans une base de données locales, afin d'afficher des courbes de tendance.
Nouvelles notes et cours annulés font l'objet de notifications sur smartphone.

## Motivations

- Avoir accès à toutes les informations essentielles en un coup d'oeil, en retirant le superflu.
- Aider les parents à suivre l'avancement des devoirs
- Donner aux enfants un accès Famille à pronote sur un périphérique dédié, sans distraction (comme une tablette avec [Fully Kiosk Browser](https://play.google.com/store/apps/details?id=de.ozerov.fully&referrer=utm_source%3D/fully-home-en%26utm_content%3Dtext-link))

La simplicité est la priorité, toutes les fonctionnalités de pronote ne seront pas portées.

## Techno

Développée avec Elixir et Phoenix LiveView. L'historique des notes et moyennes utilise SQLite.

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
- [x] push notif nouvelle note
- [ ] contacter la vie scolaire (parent)
- [ ] push notif prof absent
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

```sh
source .envrc
mix phx.server
```

Ouvrir [localhost:4000](http://localhost:4000). Après modification des variables, les recharger et redémarrer le serveur. Avec direnv, `direnv allow` remplace `source .envrc`.

Pour lancer les vérifications : `mix precommit`.

### Cache des lectures PRONOTE

Les réponses réussies sont conservées uniquement en mémoire : 5 minutes pour les cours, événements, devoirs, messages, notes et moyennes, 30 minutes pour les menus. Une entrée expirée est rechargée lors de la prochaine lecture. Un traitement supervisé relit aussi toutes les cinq minutes les cours de la semaine courante, les événements, les notes de la période courante et les messages accessibles de tous les profils configurés, même sans navigateur connecté.

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


#### Configuration du stockage

Copier `.env.example` vers `.env`, à côté de `docker-compose.yml`, sur le serveur. Ce fichier configure Compose ; le fichier `env` contient toujours les secrets de l'application.

```dotenv
DATA_DIR=.
APP_UID=1000
APP_GID=1000
DOCKER_PLATFORM=linux/amd64
```

Remplacer `APP_UID` et `APP_GID` par les résultats de `id -u` et `id -g` du compte qui possède le dossier sur le serveur. Pour un autre emplacement, renseigner par exemple `DATA_DIR=/srv/pronotex/data`, créer ce dossier et donner à ce compte le droit d'y écrire. Le conteneur utilise cette identité non privilégiée ; aucun changement récursif de propriétaire n'est effectué. Le dossier doit exister : Compose refuse de le créer implicitement avec des permissions inadaptées. La base garde son chemin interne `/app/data/pronotex.db`.

## Notifications de nouvelles notes

Le serveur relève les données toutes les cinq minutes (uniquement **entre 07 h et 22 h**). L'envoi des notifications utilise les services Web Push du navigateur (Apple, Google, Mozilla ou Microsoft) et fonctionne même avec l'app fermée ; il n'exige aucun compte Firebase. 

## Licence

Captain Notes est distribué sous [licence MIT](LICENSE). Elle autorise l'utilisation, la modification et la redistribution, y compris commerciales, sous réserve de conserver la notice de copyright et la licence. Le logiciel est fourni sans garantie. Les dépendances et éléments tiers restent soumis à leurs licences respectives.

Ce projet est un développement indépendant, réalisé sans l'accord d'Index Éducation, à des fins personnelles et non commerciales. Il n'est ni affilié à Index Éducation, ni approuvé ou soutenu par cette société.
