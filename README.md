# Captain Notes

Client parent PRONOTE en Elixir avec Phoenix, LiveView et Req, sans base de données.
La navigation propose quatre pages : Agenda, Devoirs, Notes et Menu.
L’agenda et les devoirs affichent par défaut sept jours à partir d’aujourd’hui,
avec une navigation par semaine et un bouton pour changer d’enfant.

À chaque ouverture, changement de rubrique, d’enfant ou de période, LiveView
relit uniquement les données de la page sélectionnée via Req. Aucun résultat
n’est stocké en base ; seule la session de connexion est réutilisée. Le chargement
asynchrone démarre après la connexion LiveView, sans double appel au rendu initial.

## Installation et identifiants

```sh
mix setup
# Si .envrc n’existe pas encore :
cp -n .envrc.example .envrc
```

Renseigner `PRONOTE_USERNAME` et `PRONOTE_PASSWORD` dans `.envrc`.
`PRONOTE_URL` pointe déjà vers l’espace parent du collège.
Le fichier `.envrc` est ignoré par Git ; `.envrc.example` ne contient aucun secret.
Les valeurs utilisent la syntaxe shell : échapper correctement toute apostrophe.

Puis charger les variables et démarrer :

```sh
direnv allow
# Sans direnv : source .envrc
iex -S mix phx.server
```

Le fichier n’est pas exécuté par l’application. Il doit être chargé dans le shell
qui lance Elixir. Redémarrer le serveur après un changement d’identifiants.
Phoenix peut démarrer sans identifiants ; la connexion Pronote est établie à la
première demande. Les identifiants et clés restent côté serveur, ne sont pas
persistés sur disque et ne sont pas journalisés par le client.

## API Elixir

```elixir
alias Pronotex.Pronote

{:ok, children} = Pronote.login()
# Pronote.children() se connecte aussi automatiquement si nécessaire.

for child <- children do
  {:ok, lessons} = Pronote.lessons(child.id, ~D[2026-09-14], ~D[2026-09-20])
  {child.name, lessons}
end

{:ok, homework} = Pronote.homework(hd(children).id, ~D[2026-09-14], ~D[2026-09-20])

Pronote.logout()
```

Les dates sont inclusives, dans l’année scolaire courante (366 jours maximum).
Les horaires sont des `NaiveDateTime` dans l’heure locale de l’établissement,
Europe/Paris pour ce collège, et ne doivent pas être interprétés comme UTC.
Les cours annulés restent présents avec `canceled: true`. Les enseignants,
salles, statut, mémo et priorité Pronote sont conservés.

Toutes les fonctions de lecture renvoient `{:ok, result}` ou
`{:error, %Pronotex.Pronote.Error{reason: reason, message: message}}`.
Une seule session supervisée sérialise les requêtes numérotées. Une expiration
signalée par Pronote provoque une reconnexion et une seule nouvelle lecture.
Les erreurs réseau et les refus de connexion ne déclenchent pas de renvoi
automatique. `logout/0` abandonne la session locale.

## Périmètre de connexion

Connexion directe HTTPS à `parent.html` par identifiant et mot de passe.
Pas d’ENT ni de QR code. Si Pronote impose une vérification supplémentaire,
le client renvoie `:additional_authentication_required`. Il n’enregistre pas
de nouvel appareil et ne change pas les paramètres de sécurité.

Le client récupère l’emploi du temps, les devoirs, les notes, les menus et les
événements avec le compte parent. Les lectures utilisent des POST selon le
protocole PRONOTE. Le protocole est privé et peut évoluer.

Dans la page Devoirs, le bouton « À faire / Fait » apparaît uniquement lorsque
les deux variables du compte élève concerné sont renseignées dans `.envrc` :

```sh
export PRONOTE_CHILD_1_FIRST_NAME="Alice"
export PRONOTE_CHILD_1_THEME="blue"
export PRONOTE_CHILD_1_AVATAR=""
export PRONOTE_CHILD_1_USERNAME=""
export PRONOTE_CHILD_1_PASSWORD=""
export PRONOTE_CHILD_2_FIRST_NAME="Basile"
export PRONOTE_CHILD_2_THEME="green"
export PRONOTE_CHILD_2_USERNAME=""
export PRONOTE_CHILD_2_PASSWORD=""
```

Tous les enfants sont découverts depuis le compte parent, sans limite à deux.
Les groupes `PRONOTE_CHILD_1_*`, `PRONOTE_CHILD_2_*`, etc. sont facultatifs et
associés par `FIRST_NAME`, sans tenir compte de l’ordre retourné par Pronote.
Un prénom configuré plusieurs fois est ignoré pour éviter une association ambiguë.
Les thèmes disponibles sont `blue` et `green` ; sans configuration, ils alternent.
Sans avatar, une initiale s’affiche. Placer les photos personnelles dans
`priv/static/images/avatars/` et utiliser une URL `/images/avatars/photo.png`.
Ce dossier et `.envrc` sont ignorés par Git ; ne partager que `.envrc.example`.
`PRONOTE_URL` est obligatoire : aucune adresse de collège n’est prédéfinie.

Renseigner seulement Alice laisse Basile en lecture seule, et inversement.
Après modification, recharger l’environnement et redémarrer Phoenix.
L’URL élève est déduite de `PRONOTE_URL` en remplaçant `parent.html` par
`eleve.html`.

Les lectures habituelles restent sur le compte parent. Au premier clic, une
session élève indépendante est ouverte puis réutilisée pour cet enfant. Le nom
complet est vérifié avant toute écriture. Le devoir est retrouvé dans cette
session par date, matière et description ; une correspondance ambiguë bloque
la modification. Après écriture, son statut est relu avec le compte élève avant
mise à jour de l’affichage. Aucun appel d’écriture ne passe par le compte parent.
Une écriture n’est jamais rejouée automatiquement, même si la session expire.
Les erreurs utilisent la notification flash. Aucune donnée scolaire n’est
stockée en base. La connexion élève reste à valider avec les identifiants réels.

## Validation

```sh
mix precommit
```

Les tests utilisent Req.Test et un serveur simulé indépendant pour vérifier le
challenge, la rotation des clés, les compteurs, les cookies, la compression,
les signatures parent, les deux enfants, le découpage par semaine et l’expiration.
Ils ne lisent pas vos identifiants et n’appellent pas le collège.
La compatibilité complète doit encore être validée avec le compte réel.
Voir THIRD_PARTY_NOTICES.md pour l’attribution à pronotepy.

## Liens directs

La sélection est conservée dans l’URL, par exemple `/alice?week=2026-09-14`
ou `/basile?week=2026-09-21`. `week` est la date ISO du lundi de la semaine.
Le changement d’enfant conserve la semaine ; précédent/suivant dans le navigateur
restaure la sélection. Une semaine absente ou invalide ouvre la vue « Aujourd’hui » sur sept jours glissants.
Une date en milieu de semaine est ramenée au lundi. Un enfant inconnu utilise
le premier enfant accessible et l’URL est corrigée sans ajout à l’historique.

`/alice` ou `/basile` ouvre la vue « Aujourd’hui » : le jour courant et les
six suivants, y compris au-delà du dimanche. Les flèches affichent une semaine calendaire complète et ajoutent
`?week=YYYY-MM-DD`. Depuis la vue par défaut, précédent ouvre le lundi de
la semaine en cours et suivant le lundi de la semaine prochaine. Ensuite,
chaque flèche avance ou recule de sept jours. « Aujourd’hui »
supprime ce paramètre. Changer d’enfant conserve le mode et la période.
Les dates relatives utilisent la date locale de la machine qui héberge l’application.

L’onglet Menu lit les menus publiés dans Pronote à chaque ouverture et changement de période ou d’enfant, sans stockage en base. Il utilise la même session et la même navigation de dates que l’agenda. Un message distingue une période sans menus d’une erreur d’accès.

L’onglet Notes utilise `Pronotex.Pronote.grades(child_id, period_name)` pour lire les notes, leurs statistiques de classe, les moyennes par matière et la moyenne générale publiées dans Pronote. Le sélecteur présente uniquement les périodes autorisées pour l’enfant ; la période courante est sélectionnée par défaut. Chaque ouverture, changement de période ou d’enfant relit les données, sans stockage en base. Les moyennes manquantes ne sont pas recalculées ; les notes non numériques (absence, dispense…) restent explicites et les barèmes sont conservés.

La rubrique est conservée dans le chemin : `/alice` (agenda), `/alice/devoirs`, `/alice/notes` et `/alice/menu`. Les paramètres `week` et `period` sont conservés lors des changements de rubrique et d’enfant, par exemple `/alice/notes?week=2026-09-21&period=semester1`. Les périodes utilisent des clés stables (`semester1`, `trimester1`, etc.), indépendantes des identifiants de session Pronote. Une période indisponible pour l’enfant revient à sa période par défaut.

La page Agenda affiche l’emploi du temps (2/3) et les événements « À venir » (1/3), empilés sur mobile. `Pronotex.Pronote.events(child_id)` lit `PageAgenda` (onglet 9) avec les événements passés exclus. Pronote renvoyant les événements de la famille, les destinataires `listeEleves` sont comparés au prénom ou au nom complet de l’enfant ; les événements sans destinataire explicite restent visibles pour les deux enfants. Les échéances à venir restent indépendantes de la semaine de l’emploi du temps. Titres, dates, horaires et commentaires sont affichés en texte échappé, sans stockage en base.

## Avatars sans fichier sur le serveur

Définir `PRONOTE_CHILD_1_AVATAR_BASE64`, `PRONOTE_CHILD_2_AVATAR_BASE64`, etc.
dans `.envrc` ou dans les variables du PaaS. La valeur contient uniquement le
Base64 brut d’une image PNG, JPEG ou WebP, sans préfixe `data:`. Préférer une
image de 160 × 160 pixels et vérifier la limite des variables de l’hébergeur.
L’application accepte au maximum 256 Kio de Base64 par avatar.

Les images sont décodées en mémoire et servies par `/avatars/:index`, sans
écriture sur disque ni base de données. Le Base64 valide est prioritaire sur
`PRONOTE_CHILD_n_AVATAR` ; sinon le chemin local ou l’initiale est utilisé.
Ces URL nécessitent une session authentifiée par PIN, comme les pages de l’application. Les valeurs personnelles restent dans
`.envrc`, exclu de Git.

## Déploiement sur Synology DS918+ — DSM 7.4.1

Le DS918+ utilise une image Linux **amd64**, même si elle est construite sur
un Mac Apple Silicon. Cette procédure cible le NAS mis à jour en DSM 7.4.1
avec le paquet **Container Manager**, qui remplace l'ancien paquet Docker.
Vérifier dans le Centre de paquets que Container Manager est installé et démarré
après la mise à jour de DSM. Le fichier `docker-compose.yml` reste utilisable.

La construction et le déploiement sont déclenchés manuellement avec les commandes
ci-dessous, uniquement lorsque vous souhaitez publier une nouvelle version.
Modifier le code ne construit ni ne déploie automatiquement une image.

Un conteneur suffit. Aucun volume de base de données n'est nécessaire.
L'accès est protégé par le PIN décrit ci-dessous. Pour cette installation, limiter l'accès
au réseau local, sans redirection de port Internet sur la box.

### 1. Construire l'image sur le Mac

Démarrer Docker Desktop, puis depuis le dossier du projet :

```sh
docker buildx build --platform linux/amd64 --load -t pronotex:local .
docker save -o pronotex-image.tar pronotex:local
```

La construction compile les assets et une release de production. Les secrets,
`.envrc` et les photos locales sont exclus du contexte de construction.
La construction en émulation sur Apple Silicon peut prendre plusieurs minutes.

Si la construction échoue dès `mix local.hex` avec `prim_tty:isatty`,
`erlang:nif_error` et `nouser`, cela correspond à un problème connu du JIT Erlang
sous émulation amd64 sur Apple Silicon. Le Dockerfile définit
`ERL_FLAGS="+JMsingle true"` dans l'étape de construction pour le contourner,
selon la [recommandation des mainteneurs Erlang](https://github.com/erlang/otp/issues/10355#issuecomment-3510018425).
Ce réglage n'est pas transmis au conteneur final qui tourne nativement sur le NAS.
Après récupération de ce correctif, relancer la même commande de construction ;
il n'est pas nécessaire de supprimer le cache Docker.

### 2. Préparer les fichiers du NAS

Installer ou mettre à jour **Container Manager** depuis le Centre de paquets. Créer, par exemple,
`/volume1/docker/pronotex` et y transférer via File Station :

- `pronotex-image.tar` ;
- `docker-compose.yml` ;
- `.env.docker.example`, renommé en `.env`.

Compléter `.env` avec les valeurs de `.envrc`, **sans le mot `export`**.
Ce fichier est au format Compose : entourer les valeurs sensibles de quotes
simples si elles contiennent notamment `$` ou `#`, et échapper une apostrophe
dans une valeur ainsi : `PASSWORD='exemple\'suite'`.
Ne pas simplement copier la syntaxe shell de `.envrc`.

Générer `SECRET_KEY_BASE` sur le Mac avec `mix phx.gen.secret`, puis copier
le résultat dans `.env`. Conserver cette clé lors des mises à jour.
Définir `PHX_HOST` avec le nom DNS choisi pour l'application, sans protocole
ni chemin. Les avatars Base64 existants peuvent être recopiés dans `.env`.
Les avatars utilisant un chemin local nécessitent un montage séparé ; préférer
les variables Base64 pour ce déploiement.

### 3. Démarrer sur le NAS

La procédure SSH ci-dessous sert au premier déploiement et aux mises à jour.
Activer SSH dans DSM et se connecter avec un compte administrateur.
À chaque nouvelle session SSH, se placer dans le dossier du projet et définir
ce raccourci, qui sélectionne la commande Compose disponible sur le NAS :

```sh
cd /volume1/docker/pronotex
compose() {
  if sudo docker compose version >/dev/null 2>&1; then
    sudo docker compose "$@"
  elif sudo docker-compose version >/dev/null 2>&1; then
    sudo docker-compose "$@"
  elif [ -x /var/packages/ContainerManager/target/usr/bin/docker-compose ]; then
    sudo /var/packages/ContainerManager/target/usr/bin/docker-compose "$@"
  else
    echo "Compose introuvable : vérifier l’installation de Container Manager." >&2
    return 1
  fi
}
```

Puis importer l'image et démarrer :

```sh
chmod 600 .env
sudo docker load -i pronotex-image.tar
compose up -d
compose ps
```

Le conteneur est visible dans **Container Manager → Conteneur**.
Le nom de la commande Compose dépend de la version du paquet installé ;
le raccourci accepte `docker compose` et `docker-compose`.

Il est également possible de faire le premier démarrage depuis l'interface DSM :
importer `pronotex-image.tar` dans **Container Manager → Image → Ajouter → Ajouter
à partir d'un fichier**, puis créer un **Projet** nommé `pronotex`, avec le chemin
`/volume1/docker/pronotex` et le fichier `docker-compose.yml` fourni. Garder `.env`
dans ce même dossier et démarrer le projet. Choisir une seule méthode pour le
premier démarrage, afin de ne pas créer deux instances concurrentes.

Documentation Synology : [images](https://kb.synology.com/en-global/DSM/help/ContainerManager/docker_image)
et [projets Compose](https://kb.synology.com/en-global/DSM/help/ContainerManager/docker_project).

Le port est lié à `127.0.0.1:4000` **sur le NAS**, accessible au reverse proxy
DSM uniquement. `http://IP_DU_NAS:4000` n'est donc pas une URL d'accès.

### 4. Configurer le reverse proxy HTTPS de DSM

Dans **Panneau de configuration → Portail de connexion → Avancé → Proxy inversé**,
créer une règle :

| Paramètre | Valeur |
| --- | --- |
| Source | HTTPS, nom identique à `PHX_HOST`, port 443 |
| Destination | HTTP, `127.0.0.1`, port 4000 |
| En-têtes personnalisés | Ajouter les en-têtes WebSocket via « Créer → WebSocket » |
| `X-Forwarded-Proto` | `https` |

Associer un certificat valide pour ce nom dans **Sécurité → Certificat**.
Faire résoudre ce nom vers l'adresse locale du NAS via le DNS local.
Ne pas ouvrir de port Internet pour cette première installation.
La configuration de production impose HTTPS : le proxy doit transmettre
`X-Forwarded-Proto: https` pour éviter une boucle de redirections.

Ouvrir `https://<PHX_HOST>` depuis le réseau local. Vérifier l'affichage de l'agenda,
le changement d'enfant et de rubrique, puis les heures et les avatars.

### Diagnostic et mises à jour

Sur le NAS, depuis `/volume1/docker/pronotex`, avec le raccourci `compose`
défini à l’étape 3 :

```sh
compose logs --tail=100 pronotex
compose ps
```

Le contrôle de santé vérifie le serveur web, pas la connexion à Pronote.
Le fuseau du conteneur est `Europe/Paris` pour les horaires et les dates relatives.

Pour mettre à jour, reconstruire et exporter l'image sur le Mac, transférer
le nouveau fichier, puis sur le NAS, dans le même dossier et avec le même
raccourci `compose` :

```sh
sudo docker load -i pronotex-image.tar
compose up -d --force-recreate
```

Conserver `.env` ; le rechargement de l'image n'y touche pas. Après une modification
de `.env`, exécuter aussi `up -d --force-recreate` (un simple redémarrage ne relit
pas les variables). Aucun paramètre de connexion personnel n'est intégré à l'image.


## Authentification par PIN

Définir `PINCODE` dans `.envrc` (développement) ou `.env` (Docker) avec exactement
8 chiffres. Garder la valeur comme une chaîne pour conserver les zéros initiaux.
Aucun PIN par défaut n'est prévu. Sans variable ou avec une valeur vide, l'accès
est libre, sans écran de connexion. Une valeur non vide au format invalide bloque
l'accès. L'ancien nom `PIN_CODE` reste accepté ; `PINCODE` est prioritaire si défini. Recharger `.envrc` et redémarrer Phoenix ; pour Docker,
utiliser `compose up -d --force-recreate` après modification de `.env`
(depuis le dossier du déploiement, avec le raccourci de l’étape 3).

Une connexion est valable **12 heures à partir de la saisie réussie**, sans
prolongation automatique à l'utilisation. Les pages ouvertes reviennent à la
connexion à l'expiration. Changer le PIN et redémarrer invalide les sessions existantes.
Les pages, les avatars Base64 et les avatars locaux sont protégés.
En production, le cookie est réservé à HTTPS ; utiliser le reverse proxy décrit plus haut.

Après 3 erreurs, la 4e tentative doit attendre 1 minute. Si elle échoue, la 5e
attend 2 minutes, puis 3 minutes avant la 6e, etc. Les tentatives pendant l'attente
sont refusées, même avec le bon PIN, sans augmenter le compteur ni prolonger le délai.
Une connexion réussie remet le compteur à zéro.

Le compteur est partagé entre tous les navigateurs de cette instance : supprimer
les cookies ou changer d'adresse IP ne contourne pas l'attente. Il est conservé
en mémoire et se réinitialise au redémarrage de l'application. Le PIN est filtré
des journaux de paramètres et n'est pas stocké dans le cookie.


## Identité visuelle

Captain Notes utilise le vert `#439682`, un crâne arrondi coiffé d’un chapeau de diplômé et une
signature « captain / notes » sur deux lignes. Les icônes sont dans
`priv/static/images/brand/` ; le manifeste déclare les formats de lancement
192 et 512 px, avec une icône Apple 180 px et un favicon 32 px.
Les noms techniques Elixir et Docker restent `pronotex`.
