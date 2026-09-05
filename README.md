# QFieldCloud Change Inspector — 0.3.4

Plugin QField pour consulter les deltas du projet courant et réappliquer localement un PATCH en erreur après validation explicite.

## Configuration

1. Ouvrir le plugin puis **Configuration**.
2. Conserver `https://app.qfield.cloud/api/v1/` comme serveur.
3. Coller un jeton API QFieldCloud.
4. Cliquer sur **Trouver mes projets**.
5. Le plugin compare le projet QField ouvert aux projets accessibles et sélectionne automatiquement une correspondance non ambiguë. Sinon, sélectionner le projet manuellement.
6. Enregistrer et actualiser. Le jeton reste seulement en mémoire jusqu'à la fermeture de QField.

Le jeton sert uniquement à la requête `GET /api/v1/deltas/{project_id}/`.
L'application d'un PATCH modifie l'entité du projet QField local; la synchronisation crée ensuite un nouveau delta. Le delta en erreur d'origine reste intact dans l'historique QFieldCloud.
Les pages de 200 deltas sont récupérées successivement, jusqu'à 50 000 changements. Les champs de date filtrent l'affichage au format `AAAA-MM-JJ`.

## Données présentées

- statut du changement;
- utilisateur et date;
- couche et opération;
- identifiants d'entité et de deltafile;
- `last_feedback`, erreurs fournisseur et conflits;
- JSON complet dans la fenêtre **Détails**.

## Validation et restauration

Le bouton **Valider…** est proposé pour les opérations `PATCH` en erreur, en conflit ou non appliquées. Avant toute écriture, le plugin affiche les valeurs ancienne, demandée et actuelle. Il refuse l'opération si la couche ou l'entité n'est pas retrouvée de façon unique et protège les identifiants.

Après application, **Restaurer la dernière application** remet les valeurs `old` et la géométrie locale antérieure dans la même session. La restauration des attributs est bloquée si l'une des valeurs a été modifiée entre-temps. Synchroniser seulement après avoir vérifié le résultat sur la base de test.

## Correspondance avec la base actuelle

Lorsqu'un PATCH ne contient pas `id_unique_inv`, le plugin recherche les autres deltas de la même couche portant le même `sourcePk` ou le même `localPk`. S'il y retrouve un seul identifiant durable, il utilise celui-ci pour localiser le bâtiment actuel et affiche la chaîne de correspondance avant validation. Toute ambiguïté, absence d'identifiant ou correspondance multiple bloque l'écriture.

## Historique d'une entité

Le bouton **Historique** regroupe les deltas du même enregistrement grâce à `id_unique_inv`, puis à `sourcePk` ou `localPk` lorsque nécessaire. Ils sont affichés du plus ancien au plus récent avec la date, l'utilisateur, le statut et les valeurs modifiées. Un delta en erreur est présenté comme une tentative et non comme une modification nécessairement présente dans la base.

## Aperçu des déplacements

Lorsque `old.geometry` et `new.geometry` diffèrent, **Voir déplacement** ferme temporairement l'inspecteur et affiche sur la carte l'ancien point en rouge, le nouveau en vert et une ligne entre les deux. Cet aperçu n'enregistre aucune géométrie. Le filtre d'enregistrement est retiré uniquement durant la recherche interne, puis restauré immédiatement.

Le plugin lit directement les coordonnées WKT `Point (…)` et les transforme du CRS de la couche vers le CRS de la carte au moyen du moteur d'expressions déjà intégré à QField. Il ne requiert aucun module QML supplémentaire. Les géométries linéaires et polygonales ne sont pas encore prises en charge par l'aperçu.

La version 0.3.3 prend également en charge les `PATCH` dont `old.geometry` est absent. Le marqueur rouge correspond alors à la géométrie actuelle du bâtiment local, tandis que le marqueur vert représente `new.geometry`. Le nouveau point est interprété à partir de `localLayerCrs` ou `sourceLayerCrs` indiqué dans le delta.

La version 0.3.4 applique aussi réellement `new.geometry` à l'entité locale lors de la validation. Le WKT du delta est transformé vers le CRS de la couche avant l'enregistrement. Un PATCH ne contenant qu'un déplacement, sans attribut modifié, peut donc également être validé. La géométrie locale présente avant l'application est conservée pour permettre **Restaurer la dernière application** durant la session.
