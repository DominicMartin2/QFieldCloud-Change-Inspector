# QFieldCloud Change Inspector — 0.1.3

Plugin QField en lecture seule pour consulter les deltas du projet courant.

## Configuration

1. Ouvrir le plugin puis **Configuration**.
2. Conserver `https://app.qfield.cloud/api/v1/` comme serveur.
3. Coller un jeton API QFieldCloud.
4. Cliquer sur **Trouver mes projets**.
5. Le plugin compare le projet QField ouvert aux projets accessibles et sélectionne automatiquement une correspondance non ambiguë. Sinon, sélectionner le projet manuellement.
6. Enregistrer et actualiser. Le jeton reste seulement en mémoire jusqu'à la fermeture de QField.

Le plugin utilise uniquement la requête `GET /api/v1/deltas/{project_id}/`.
Il ne modifie aucun changement et ne déclenche aucun traitement QFieldCloud.
Les pages de 200 deltas sont récupérées successivement, jusqu'à 5 000 changements.

## Données présentées

- statut du changement;
- utilisateur et date;
- couche et opération;
- identifiants d'entité et de deltafile;
- `last_feedback`, erreurs fournisseur et conflits;
- JSON complet dans la fenêtre **Détails**.
