# 1. Contexte et besoins

Rhénatech (entreprise fictive, Colmar, 140 salariés) maintient réseaux, serveurs et postes de 60 clients
(collectivités, PME, deux cliniques). Ses astreintes de nuit et de week-end reposent sur 25 techniciens
de trois sous-traitants, qui interviennent au nom de Rhénatech avec ses procédures. La documentation
était éparpillée ; une procédure périmée appliquée de nuit a coupé les urgences d'une clinique pendant
quatre heures. La direction veut une base documentaire **unique, hébergée en interne, conteneurisée**,
avec deux publics séparés. Le logiciel est imposé : BookStack.

Notre maquette : BookStack + MariaDB sur un cluster **k3s**, déployé de zéro par `./scripts/deploy.sh`.

| Code | Besoin (priorité) | Notre réponse | Vérifié par |
|---|---|---|---|
| B1 | HTTPS sur wiki.rhenatech.lab (indisp.) | Ingress Traefik, certificat signé par une autorité interne, TLS ≥ 1.2, HSTS, HTTP→HTTPS 301 | R1 |
| B2 | 3 profils internes (indisp.) | rôles Administrateur, Éditeur, Lecteur (rôles par défaut renommés et ajustés par script) | R2 |
| B3 | Prestataire cloisonné (indisp.) | rôle **Prestataire sans aucune permission de rôle** + un rôle « Accès client – X » par client ; droits posés livre par livre | R3 |
| B4 | Comptes nominatifs, désactivables (indisp.) | un compte par technicien ; `disable-user.sh` : rôles retirés, mot de passe invalidé, MFA et sessions supprimés | R4 |
| B5 | TOTP obligatoire prestataires + admins (indisp.) | option « MFA obligatoire » cochée sur Administrateur, Prestataire et rôles d'accès client | R4 |
| B6 | Traçabilité (indisp.) | journal d'audit BookStack (connexions, créations, modifications, suppressions, changements de droits) | R5 |
| B7 | Structure de départ (indisp.) | étagères Interne / Procédures d'intervention / Clients, 3 livres clients fictifs, 9 pages réelles dont « Restaurer le wiki » | init |
| B8 | Recherche, pièces jointes 20 Mo (indisp.) | `FILE_UPLOAD_SIZE_LIMIT=25`, PHP 25 Mo/30 Mo ; Traefik ne limite pas | R6 |
| B9 | Volumes sur 3 ans (indisp.) | PVC fichiers 15 Gi, base 5 Gi, sauvegardes 30 Gi (80 Gi en année 3), requests/limits — calcul en 1.1 | — |
| B10 | Disponibilité, pas de perte au redémarrage (indisp.) | données sur PVC, sondes, redémarrage automatique | R7 |
| B11 | RPO 24 h, RTO 4 h (indisp.) | CronJob quotidien 02:00, export hors cluster, restauration mesurée **< 2 min** | R10 |
| B12 | RGPD (indisp.) | données limitées, pas d'avatar externe, journal purgé à 365 jours, registre en annexe A | annexe A |
| B13 | Mise à jour sans perte, retour arrière, état en 1 min (indisp.) | `upgrade.sh` (sauvegarde puis image), `rollback.sh` (image + restauration), `status.sh` | R11, R12 |
| B14 | Réversibilité (souhaité) | export Markdown/PDF natif de BookStack ; réinstallation complète depuis le dépôt seul (R10) | R10 |
| B15 | Annuaire LDAP/OIDC (souhaité) | non réalisé — partie 9 | — |
| B16 | Courriels (souhaité) | non réalisé : `MAIL_DRIVER=log` ; Mailpit prévu — partie 9 | — |

## 1.1 Dimensionnement (B9)

Hypothèses de l'énoncé à trois ans : 5 000 pages, 10 Go de pièces jointes, 165 comptes, 40 connexions simultanées.

| Ressource | Calcul | Retenu |
|---|---|---|
| Fichiers (`/config` : pièces jointes, images) | 10 Go + 50 % de marge (images des pages, croissance) | **PVC 15 Gi** |
| Base | 5 000 pages × ~20 Ko (HTML + Markdown) × 10 révisions en moyenne (plafond `REVISION_LIMIT=50`) ≈ 1 Go ; index de recherche ≈ 0,5 Go ; journal d'audit ≈ 2 000 évènements/jour × 365 j (purge) × 200 o ≈ 150 Mo | **PVC 5 Gi** (×2 de marge) |
| Sauvegardes | 7 jours × (dump compressé ≤ 0,5 Go + archive fichiers) : ~3 Go de fichiers en année 1 → ≈ 25 Go ; 10 Go en année 3 → ≈ 75 Go | **PVC 30 Gi**, porté à 80 Gi en année 3 |
| BookStack | 40 requêtes PHP simultanées × ~25 Mo ≈ 1 Go au pic | requests 250m/384 Mi, limits 1 CPU/1 Gi |
| MariaDB | buffer pool 256 Mo + 100 connexions max | requests 250m/512 Mi, limits 1 CPU/1 Gi |
| VM | requests totales ≈ 0,6 CPU / 1 Gi + k3s ≈ 0,5 Gi | 2 vCPU, 4 Go RAM, 40 Go disque (maquette) |

Point d'attention : **local-path n'impose pas la taille demandée** ; c'est le disque de la VM qui
plafonne réellement. La surveillance de l'espace disque est donc indispensable (partie 7).
