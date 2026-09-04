# QFieldCloud Change Inspector — 0.1.1

Plugin QField en lecture seule pour consulter les deltas du projet courant.

## Configuration

1. Ouvrir le plugin puis **Configuration**.
2. Conserver `https://app.qfield.cloud/api/v1/` comme serveur.
3. Coller un jeton API QFieldCloud.
4. Cliquer sur **Trouver mes projets**.
5. Sélectionner le projet par son nom; son UUID est rempli automatiquement.
6. Activer facultativement la mémorisation locale du jeton.

Le plugin utilise uniquement la requête `GET /api/v1/deltas/{project_id}/`.
Il ne modifie aucun changement et ne déclenche aucun traitement QFieldCloud.

## Données présentées

- statut du changement;
- utilisateur et date;
- couche et opération;
- identifiants d'entité et de deltafile;
- `last_feedback`, erreurs fournisseur et conflits;
- JSON complet dans la fenêtre **Détails**.
