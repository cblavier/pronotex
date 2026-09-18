# Captain Notes

La page de connexion utilise désormais le crâne arrondi coiffé d’un chapeau de
diplômé, variante « Tout en rondeur ». Le symbole et le lettrage « captain / notes »
sont réunis dans une image transparente : la typographie de la proposition est
conservée graphiquement, sans police externe. Le titre reste accessible via le
`h1` nommé « Captain Notes ».

- `captain-notes-skull-lockup.png` : original généré ;
- `captain-notes-skull-login.png` : version 1040 × 400, affichée à 260 × 100.

Les icônes PWA, Apple et le favicon utilisent aussi le crâne arrondi, blanc sur vert.

Fichiers actifs dans `priv/static/images/brand/` :
- `captain-notes-skull-icon.png` : original ;
- `captain-notes-skull-192.png` et `captain-notes-skull-512.png` : icônes de lancement ;
- `captain-notes-skull-180.png` : icône Apple ;
- `captain-notes-skull-32.png` : favicon.

Le manifeste définit le nom Captain Notes.
Aucun cache hors ligne des données scolaires n'est ajouté.
Les fichiers de la première proposition Pronotex sont conservés mais ne sont plus référencés.

Conception : outil intégré ImageGen. Redimensionnements techniques avec sips.
Prompt final de la variante retenue :

> Reproduce ONLY the LEFT notebook symbol in this approved reference as a single final app icon. Preserve its exact design: upright white notebook, separate narrow white spine with rounded left corners, folded upper right page corner separated by green, two short green horizontal writing lines. NO calendar, NO checkmark, NO initials, NO text or captions. Square canvas filled edge-to-edge with opaque solid green RGB(67,150,130) #439682. White notebook centered within the middle 60% of canvas. Full square green outside corners (no rounded tile mask), balanced generous margins for circular cropping by phone OS. Completely flat white and green artwork, sharp clean edges, no shadows, no glow, no gradients, no texture, no transparency, no presentation board. Faithfully use the notebook from the left, do not invent a new symbol.

## Crâne arrondi — logo de connexion

Conception : outil intégré ImageGen, référence à la variante 01 de la planche
validée. Redimensionnement technique avec `sips`.

Prompt de production : crâne arrondi fidèle à la variante « Tout en rondeur »,
yeux circulaires, petit nez triangulaire arrondi, dents courtes arrondies,
chapeau de diplômé avec pompon à droite. Composition horizontale avec symbole
à gauche et le même lettrage géométrique épais en minuscules « captain » puis
« notes » à droite. Vert #3c987f, fond transparent, sans sourire, clin d’œil ni
cache-œil, sans numéro ou légende. Le titre est un lettrage graphique issu de la
proposition, pas une police de caractères identifiée.

## Icônes du crâne

Original : `captain-notes-skull-icon.png`. Déclinaisons PNG : 512 et 192 px pour la PWA, 180 px pour Apple et 32 px pour le favicon. Les champs `name` et `short_name` du manifeste valent « Captain Notes », ainsi que `apple-mobile-web-app-title`.

Outil : ImageGen intégré, avec le logo de connexion comme référence. Prompt : reprendre uniquement le crâne arrondi et son chapeau, en blanc sur fond carré opaque vert #3c987f, centré avec des marges adaptées aux masques PWA ; sans texte, ombre, dégradé ou coins arrondis extérieurs. Redimensionnements techniques avec sips.
