# 4. Mise en œuvre : le comment

## 4.1 Le dépôt

```
sae11/
├── README.md, Makefile          installer · exploiter · raccourcis make
├── k8s/                         kubectl apply -k k8s/
│   ├── kustomization.yaml       images épinglées, ConfigMaps générées (hachage)
│   ├── namespace.yaml  mariadb.yaml  bookstack.yaml  ingress.yaml
│   ├── networkpolicies.yaml  backup.yaml
│   └── config/                  bookstack.env · php-local.ini · mariadb.cnf · backup.sh · purge-audit.sh · 10-rhenatech-init.sh
├── scripts/                     deploy · gen-secrets · init-bookstack · status · backup-now · backup-export
│                                restore · upgrade · rollback · disable-user · recette · r10-disaster · destroy
├── secrets/secret.exemple.yaml  valeurs factices
└── docs/                        cadrage, ce dossier, journaux de recette, oral
(.secrets/ et backups/ : générés localement, ignorés par Git)
```

## 4.2 Les étapes

```bash
# 1. VM : k3s épinglé + horloge synchronisée (TOTP)
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.35.10+k3s1 sh -
sudo timedatectl set-ntp true
# 2. Poste d'administration : kubeconfig de la VM (/etc/rancher/k3s/k3s.yaml, adresse 192.168.56.10)
# 3. Tout le reste, en une commande :
./scripts/deploy.sh
```

`deploy.sh` enchaîne, en **86 s mesurées** sur un cluster vierge :

1. `gen-secrets.sh` : `APP_KEY` (`base64:` + 32 octets), mots de passe MariaDB, autorité interne et
   certificat `wiki.rhenatech.lab` dans `.secrets/` — rien n'est régénéré s'il existe déjà ;
2. namespace `wiki`, puis Secrets `wiki-secrets` et `wiki-tls` (`kubectl create … --dry-run=client | kubectl apply`) ;
3. `kubectl apply -k k8s/`, attente des sondes (`rollout status`) ;
4. `init-bookstack.sh` : rôles, TOTP, étagères, livres, pages, permissions, comptes.

## 4.3 Ce qui compte dans les manifestes

```yaml
# bookstack.yaml — secrets par référence, sondes adaptées à la migration
envFrom: [{ configMapRef: { name: bookstack-env } }]       # APP_URL, DB_HOST, limites…
env:
  - { name: APP_KEY, valueFrom: { secretKeyRef: { name: wiki-secrets, key: APP_KEY } } }
startupProbe:   { httpGet: { path: /status, port: http }, failureThreshold: 36 }  # 6 min de migration possible
readinessProbe: { httpGet: { path: /status, port: http } }   # base + cache + session
livenessProbe:  { tcpSocket: { port: http } }                # ne dépend PAS de la base
```

La liveness ne teste pas la base : si MariaDB tombe, BookStack devient « non prêt » (retiré du
Service) mais n'est pas redémarré en boucle ; il revient seul avec la base.

```yaml
# ingress.yaml — TLS ≥ 1.2 et HSTS
traefik.ingress.kubernetes.io/router.tls.options: wiki-tls-modern@kubernetescrd
traefik.ingress.kubernetes.io/router.middlewares: wiki-security-headers@kubernetescrd
```

## 4.4 Configuration de BookStack (rôles, permissions, TOTP)

Réalisée par `scripts/init-bookstack.sh` via l'API REST (rejouable sans doublon) :

| Rôle | Permissions de rôle | MFA obligatoire | Comptes de démonstration |
|---|---|---|---|
| Administrateur (rôle système) | toutes | **oui** | admin@rhenatech.lab, claire.fischer@rhenatech.lab |
| Éditeur | créer/modifier/supprimer contenu, pièces jointes, commentaires | non | editeur@rhenatech.lab |
| Lecteur | voir tout, exporter | non | lecteur@rhenatech.lab |
| Prestataire | **aucune** | **oui** | tech1@alpha-reseaux.example, tech1@beta-systemes.example |
| Accès client – X (×3) | **aucune** (sert seulement d'étiquette d'accès) | **oui** | Alpha → Clinique des Tilleuls ; Beta → Commune de Val-d'Ill + Brasserie Lauch |
| Public (anonyme) | **aucune** | — | inscription publique fermée |

| Contenu | Permissions posées (les autres rôles gardent leurs droits de rôle) |
|---|---|
| Étagère Interne et livres Exploitation, RH, Commercial | refus explicite à Prestataire et aux 3 rôles d'accès client |
| Étagère Procédures d'intervention, livre Procédures réseau | lecture seule pour Prestataire |
| Étagère Clients | lecture pour Prestataire (l'étagère, pas les livres) |
| Livre « Client – X » | lecture seule pour « Accès client – X » uniquement |

Résultat calculé par le moteur de BookStack (table `joint_permissions`) et vérifié par l'interface (R3) :
Alpha voit *Procédures réseau* et *Client – Clinique des Tilleuls* ; Beta voit *Procédures réseau*,
*Client – Commune de Val-d'Ill* et *Client – Brasserie Lauch* ; ni l'un ni l'autre ne voit Interne, et la
recherche ne leur renvoie rien de ce qu'ils ne peuvent pas ouvrir.

Équivalent manuel (si besoin de le montrer dans l'interface) : Paramètres › Rôles › *Prestataire* :
décocher toutes les permissions, cocher « Exiger l'authentification multifacteur » ; puis sur chaque
livre : Permissions › ajouter le rôle, cocher « Voir » seulement.

**Ajouter un prestataire** : Paramètres › Utilisateurs › Ajouter (courriel nominatif), rôles
*Prestataire* + *Accès client – <ses clients>*. À sa première connexion il enrôle son application TOTP.
**Ajouter un client** : relancer `init-bookstack.sh` après avoir ajouté le client à la liste `CLIENTS`.
