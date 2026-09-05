# QFieldCloud Change Inspector — 0.2.1

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

Après application, **Restaurer la dernière application** remet les valeurs `old` dans la même session. La restauration est bloquée si l'une des valeurs a été modifiée entre-temps. Synchroniser seulement après avoir vérifié le résultat sur la base de test.

## Correspondance avec la base actuelle

Lorsqu'un PATCH ne contient pas `id_unique_inv`, le plugin recherche les autres deltas de la même couche portant le même `sourcePk` ou le même `localPk`. S'il y retrouve un seul identifiant durable, il utilise celui-ci pour localiser le bâtiment actuel et affiche la chaîne de correspondance avant validation. Toute ambiguïté, absence d'identifiant ou correspondance multiple bloque l'écriture.
