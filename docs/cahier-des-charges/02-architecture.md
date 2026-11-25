# 2. Architecture

## 2.1 Schéma logique

```mermaid
flowchart LR
  S[Salarié]:::u -- "HTTPS 443" --> T
  P[Prestataire<br/>+ appli TOTP]:::u -- "HTTPS 443" --> T
  subgraph k3s["cluster k3s"]
    subgraph ks[kube-system]
      T["Traefik (Ingress)<br/>wiki.rhenatech.lab<br/>TLS ≥1.2 · HSTS · 80→443"]
      DNS[CoreDNS]
    end
    subgraph wiki["namespace wiki — NetworkPolicy : refus par défaut"]
      B["BookStack<br/>Deployment · 1 réplica · Recreate<br/>/status · PVC bookstack-config 15 Gi"]
      M[("MariaDB 11.8<br/>StatefulSet mariadb-0<br/>PVC data 5 Gi")]
      CB["CronJob wiki-backup<br/>02:00 · PVC wiki-backups 30 Gi"]
      CP["CronJob wiki-audit-purge<br/>dimanche 03:30"]
      SEC{{"Secret wiki-secrets<br/>APP_KEY · mots de passe"}}
      CM{{"ConfigMaps<br/>bookstack-env · php · mariadb.cnf"}}
    end
  end
  T -- "HTTP 80" --> B
  B -- "3306" --> M
  CB -- "3306 (dump)" --> M
  CB -. "lecture seule /config" .-> B
  CP -- "3306" --> M
  CB == "backup-export.sh" ==> X[("Poste d'administration<br/>backups/ + .secrets/")]
  classDef u fill:#eef,stroke:#336
```

## 2.2 Schéma physique

```mermaid
flowchart TB
  subgraph HV["Hyperviseur : VirtualBox sur le poste (ou Proxmox des TP)"]
    subgraph VM["VM k3s-1 — Debian 13 — 2 vCPU / 4 Go / 40 Go"]
      direction TB
      N1["carte 1 : NAT (sortie Internet : images, NTP)"]
      N2["carte 2 : réseau hôte 192.168.56.10/24 (RFC 1918)"]
      K["k3s v1.35.10 (serveur + nœud)<br/>pods 10.42.0.0/16 · services 10.43.0.0/16"]
      D["/var/lib/rancher/k3s/storage<br/>3 volumes local-path"]
    end
    A["Poste d'administration<br/>kubectl · dépôt Git · .secrets/ · backups/"]
    W["Navigateur<br/>hosts : 192.168.56.10 wiki.rhenatech.lab<br/>autorité ca.crt importée"]
  end
  A -- "6443 (API k3s)" --> N2
  W -- "443" --> N2
  N2 --- K
  K --- D
```

Variante à trois nœuds (même dépôt, sans modification) : k3s-1 serveur 192.168.56.11, k3s-2 et k3s-3
agents 192.168.56.12-13. Les pods suivent leur volume local-path (affinité de nœud posée par le provisionneur).

## 2.3 Matrice des flux (= NetworkPolicy de `k8s/networkpolicies.yaml`)

| Source | Destination | Port | Pourquoi | Contrôle |
|---|---|---|---|---|
| Postes | Traefik (nœud) | 443/TCP, 80/TCP | accès au wiki ; 80 ne fait que rediriger | Ingress `wiki`, `wiki-http-redirect` |
| Traefik (kube-system) | bookstack | 80/TCP | proxy inverse (TLS terminé par Traefik) | `bookstack-from-traefik` |
| bookstack | mariadb | 3306/TCP | base de l'application | `bookstack-to-mariadb`, `mariadb-from-clients` |
| jobs `wiki-backup`, `wiki-maintenance` | mariadb | 3306/TCP | sauvegarde, restauration, purge RGPD | `jobs-to-mariadb`, `mariadb-from-clients` |
| tous les pods du namespace | CoreDNS | 53/UDP+TCP | résolution de noms | `allow-dns-egress` |
| tout le reste (entrant et sortant, dont Internet) | — | — | refusé | `default-deny-all` |

BookStack n'a **aucune sortie Internet** : `AVATAR_URL=false` coupe Gravatar, le courriel est journalisé.
