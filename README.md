# Pronotex

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
