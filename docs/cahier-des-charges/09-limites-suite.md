# 9. Limites et suite

- **Un seul pod BookStack, un seul MariaDB, volumes locaux** : la panne du nœud arrête le service jusqu'à
  restauration (87 s mesurées, plus le temps de décision). Production : 3 nœuds, stockage répliqué
  (Longhorn) ou NFS, 2 réplicas BookStack + PodDisruptionBudget (A3), MariaDB répliqué (Galera ou opérateur).
- **Sauvegardes sur le même disque** que les données tant que l'export n'est pas fait : automatiser l'export
  vers un stockage objet hors plateforme (MinIO, A2) et chiffrer les archives (elles contiennent le `.env` de l'image).
- **Image BookStack lancée en root** (s6) : Pod Security « baseline » seulement. Parade : image non-root (O5).
- **Pas d'annuaire** (B15) : comptes locaux. Suite : OIDC avec Keycloak (RFC 6749) ou LDAP (LLDAP, RFC 4511) pour
  les salariés, en gardant des comptes locaux + TOTP pour les prestataires.
- **Pas de courriel** (B16) : `MAIL_DRIVER=log`. Suite : Mailpit comme serveur de test, puis le relais SMTP de l'entreprise
  (la NetworkPolicy devra ouvrir la sortie vers ce relais).
- **Certificat renouvelé à la main** (397 j) : cert-manager avec un ClusterIssuer CA (O6) le ferait seul.
- **Supervision minimale** (`status.sh`) : Prometheus + Grafana + alerte sur l'échec de sauvegarde (O4).
- **Désactivation de compte par script** : BookStack n'a pas d'état « désactivé » natif.
- **Tests faits sur un cluster k3s mononœud** ; la variante trois nœuds n'a pas été chronométrée.

**Usage de l'IA.** Une IA nous a aidés à écrire le premier jet des manifestes, des scripts et de ce dossier.
Nous avons relu chaque ligne et tout testé sur un vrai cluster ; la recette a révélé trois erreurs que nous
avons corrigées : une sauvegarde déclarée réussie alors que le dump avait échoué (absence de `pipefail`), un
pod de sauvegarde bloqué par la NetworkPolicy dans ses premières secondes, une colonne `expires_at` de type DATE
pour les jetons d'API. Aucun secret ni donnée réelle n'a été transmis à l'IA.
