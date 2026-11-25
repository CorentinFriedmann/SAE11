# 6. Sécurité et RGPD

## 6.1 Mesures

| Domaine | Mesure | Où |
|---|---|---|
| Flux | Refus par défaut (entrant + sortant) dans `wiki` ; seuls les flux de la matrice 2.3 sont ouverts. Testé : un pod sans label autorisé ne joint pas MariaDB (R8). | `networkpolicies.yaml` |
| Chiffrement | HTTPS seul : HTTP redirigé en 301 ; TLS 1.2 minimum, 1.3 négocié (RFC 8446) ; HSTS 1 an (RFC 6797) ; `sniStrict` | `ingress.yaml` |
| Certificats | Autorité interne ECDSA P-256 (contrainte `CA:TRUE, pathlen:0`), certificat serveur 397 j avec SAN, EKU serverAuth (RFC 5280) ; clé privée hors Git | `gen-secrets.sh` |
| Secrets | Secret Kubernetes référencé par `secretKeyRef` ; root MariaDB connu seulement de MariaDB et du job de restauration ; mots de passe passés par `MYSQL_PWD` (absents de `ps`) ; `.secrets/` en 0700, ignoré par Git ; contrôle R9 | `deploy.sh`, `.gitignore` |
| Authentification | Comptes nominatifs ; **TOTP obligatoire** pour Administrateur, Prestataire, rôles d'accès client (RFC 6238) ; compte `admin@admin.com` par défaut supprimé (renommé, mot de passe aléatoire) ; inscription publique et accès anonyme fermés ; cookie `Secure` | `init-bookstack.sh` |
| Autorisation | Prestataire sans droit de rôle, accès livre par livre ; refus explicite sur Interne (défense en profondeur) | `init-bookstack.sh` |
| Fin de contrat | `disable-user.sh` : effet immédiat (rôles retirés, sessions supprimées) ; le compte reste lisible dans le journal | R4 |
| Traçabilité | Journal d'audit BookStack (connexions, contenus, droits, comptes), visible des administrateurs | R5 |
| Pods | `seccomp RuntimeDefault`, `allowPrivilegeEscalation: false`, jeton de compte de service non monté ; MariaDB et jobs en non-root, `capabilities: drop ALL` ; namespace en Pod Security **baseline** imposé, **restricted** en audit | manifestes |
| Images | Officielles, épinglées (`v26.09.2-ls296`, `11.8.9`), jamais `latest` | `kustomization.yaml` |

Écart assumé : l'image linuxserver démarre en root (s6) avant de lancer nginx/php-fpm sous l'uid 1000 ;
elle ne passe pas « restricted ». Parade : image BookStack non-root construite par nos soins (partie 9).

## 6.2 Données personnelles (résumé — registre complet en annexe A)

Le wiki contient : nom, courriel professionnel, rôles, empreinte du mot de passe (bcrypt), secret TOTP
(chiffré par l'`APP_KEY`), adresse IP et date des connexions et actions (journal d'audit), sessions.
Aucune donnée client sensible dans les pages d'exemple (clients fictifs, aucun nom de personne, aucun numéro).
Durées : journal d'audit **365 jours** (purge hebdomadaire automatique) ; compte prestataire désactivé
le jour de la fin de contrat et supprimé après 1 an ; sauvegardes 7 jours sur le cluster.
