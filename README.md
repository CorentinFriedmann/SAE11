# Wiki Rhénatech — BookStack sur Kubernetes (SAÉ5.DevCloud.03)

Base documentaire unique de Rhénatech : **BookStack + MariaDB sur k3s**, accès
**https://wiki.rhenatech.lab**, rôles cloisonnés (Administrateur, Éditeur, Lecteur, Prestataire),
**TOTP obligatoire** pour les prestataires et les administrateurs, journal d'audit, sauvegarde
quotidienne avec restauration testée, mise à jour avec retour arrière.

**Tout se déploie de zéro en une commande :**

```bash
./scripts/deploy.sh
```

| Où | Quoi |
|---|---|
| [`docs/00-cadrage.md`](docs/00-cadrage.md) | Note de cadrage : ce que nous allons faire, architecture, planning par jalon |
| [`docs/cahier-des-charges/`](docs/cahier-des-charges/) | Le dossier rendu (10 parties + annexes), écrit au fil de l'eau |
| [`docs/recette/`](docs/recette/) | Journaux de recette R1 à R12 produits par `scripts/recette.sh` |
| [`docs/demo-oral.md`](docs/demo-oral.md) | Déroulé de la démonstration et réponses préparées aux questions du jury |

## Prérequis

- Une VM Debian/Ubuntu (2 vCPU, 4 Go RAM, 40 Go disque) avec **k3s** (Traefik, local-path,
  metrics-server et NetworkPolicy sont fournis par défaut) et l'horloge synchronisée (NTP : le TOTP en dépend).
- Sur le poste d'administration : `kubectl` (kubeconfig du cluster), `openssl`, `curl`, `jq`, `python3`, `git`.

```bash
# Sur la VM (une seule fois)
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.35.10+k3s1 sh -
sudo timedatectl set-ntp true
```

## Déployer, utiliser, exploiter

```bash
./scripts/deploy.sh             # secrets + certificat + manifestes + rôles/étagères/comptes (≈ 1 min 30)
```

Puis, sur le poste qui ouvre le wiki :

1. ajouter `IP_DE_LA_VM  wiki.rhenatech.lab` dans le fichier hosts ;
2. importer `.secrets/tls/ca.crt` comme autorité de confiance (sinon : avertissement de certificat) ;
3. se connecter avec un compte de `.secrets/comptes-demo.txt` (l'administrateur par défaut
   `admin@admin.com` n'existe plus : il est renommé et reçoit un mot de passe aléatoire).

| Besoin | Commande |
|---|---|
| État du service en moins d'une minute | `./scripts/status.sh` |
| Sauvegarde immédiate | `./scripts/backup-now.sh` |
| Copier une sauvegarde hors du cluster | `./scripts/backup-export.sh` |
| Lister / restaurer une sauvegarde | `./scripts/restore.sh --list` · `./scripts/restore.sh AAAAMMJJ-HHMMSS` |
| Mettre à jour BookStack / revenir en arrière | `./scripts/upgrade.sh v26.09.3-ls301` · `./scripts/rollback.sh` |
| Fin de contrat d'un prestataire | `./scripts/disable-user.sh courriel@prestataire.example` |
| Recette R1 à R12 | `./scripts/recette.sh` (non destructif) · `./scripts/recette.sh --complet` |
| Tout supprimer | `./scripts/destroy.sh` |

## Structure du dépôt

```
k8s/                    manifestes (kubectl apply -k k8s/)
  kustomization.yaml    versions des images épinglées, ConfigMaps générées
  namespace.yaml        namespace wiki (Pod Security baseline)
  mariadb.yaml          StatefulSet + Service headless + PVC 5 Gi
  bookstack.yaml        Deployment (Recreate) + Service + PVC 15 Gi
  ingress.yaml          Ingress Traefik HTTPS, redirection HTTP, HSTS, TLS ≥ 1.2
  networkpolicies.yaml  refus par défaut + flux autorisés
  backup.yaml           CronJob de sauvegarde (02:00) + purge RGPD du journal + PVC
  config/               fichiers des ConfigMaps (variables BookStack, PHP, MariaDB, scripts)
scripts/                déploiement, configuration BookStack, exploitation, recette
secrets/secret.exemple.yaml   forme des Secrets, valeurs factices
docs/                   cadrage, cahier des charges, recette, oral
.secrets/  backups/     générés localement, IGNORÉS PAR GIT (secrets, comptes, sauvegardes exportées)
```

## Règles du dépôt

- **Aucun secret dans Git** : les secrets sont générés par `scripts/gen-secrets.sh` dans `.secrets/`
  (ignoré). Avant chaque push : `git grep -n -i -E 'password|app_key'` (recette R9).
- **Jamais `latest`** : les images sont épinglées dans `k8s/kustomization.yaml`.
- **`.secrets/wiki-secrets.env` doit être sauvegardé hors ligne** : sans l'`APP_KEY` d'origine,
  une restauration fonctionne mais tous les utilisateurs doivent ré-enrôler leur TOTP.
