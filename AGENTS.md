# Interface

Privilégier les function components Phoenix pour construire l'interface. Extraire les éléments partagés (titres, contrôles, blocs de présentation) dans des composants réutilisables plutôt que dupliquer leur HTML et leurs styles entre les pages. Réutiliser les composants existants avant d'en créer de nouveaux.

# Documentation

Ne pas documenter dans le README les nouveaux concepts techniques.
La documentation doit rester succinte et synthétique.

# Commits

Rédiger les messages de commit en anglais.

# Screenshots

- Capturer l'interface réelle avec des données fictives dans un environnement isolé, sans compte Pronote réel. Charger les styles, polices et portraits avant la capture, puis attendre la fin des animations.
- Utiliser Alice, en 5B au collège Jules Ferry, et son frère Marius, en 3A. Réutiliser les portraits fictifs de `screenshots/portraits/`. Garder des cours, devoirs, messages et dates crédibles et cohérents entre les pages ; la série actuelle est datée du 28 septembre 2026.
- Sur l'agenda, afficher un seul bandeau « Nouvelles notes » concernant Marius, avec son portrait. Pour les notes d'Alice, conserver une courbe ascendante terminant à 16,5/20 (moyenne de classe : 13,3/20). Le haut du graphique correspond au maximum des séries élève et classe + 2.
- Produire un PNG séparé pour chaque vue : agenda, emploi du temps hebdomadaire, notes, devoirs et messages en desktop et mobile, plus le Menu mobile. Sur mobile, capturer séparément les onglets « Dernières notes » et « Moyennes » : 12 images au total.
- Utiliser des viewports de 1440 × 1100 en desktop, 430 × 932 en mobile portrait et 932 × 430 pour l'emploi du temps mobile en paysage. Exclure les outils du navigateur et le pointeur ; conserver le cadrage de la page et les proportions.
- Conserver les captures sans cadre dans `screenshots/originaux/alice/`. Appliquer aux images de `screenshots/alice/` le cadre validé dans `screenshots/apercus/mobile-agenda-cadre.png` : fond blanc, marge extérieure, fine bordure gris clair, coins légèrement arrondis et ombre discrète, sans habillage de téléphone. Toujours repartir de l'original pour éviter d'empiler les cadres. Le cadre ne doit pas modifier le contenu de l'interface.
- Vérifier visuellement chaque image : textes et portraits lisibles, données cohérentes, moyenne finale correcte, absence de débordement indésirable. Sur la page Notes desktop, la colonne des dernières notes défile indépendamment ; le tableau des moyennes reste défilable horizontalement sans barre visible.
- Conserver les noms de fichiers et la sélection éditoriale du README, notamment les captures volontairement retirées. Maintenir le lien vers `screenshots/` et actualiser `screenshots/alice-screenshots.zip` avec les images finales ; les archives `screenshots/*.zip` restent ignorées par Git.
