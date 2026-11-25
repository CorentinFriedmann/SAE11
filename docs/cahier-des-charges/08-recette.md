# 8. Recette

Exécutée par `./scripts/recette.sh --complet` (les tests ouvrent de vraies sessions HTTPS via l'Ingress,
avec de vrais comptes ; le code TOTP est calculé selon la RFC 6238 par `scripts/totp.py`).
Journal brut : [`docs/recette/journal-20261125-082049.md`](../recette/journal-20261125-082049.md).

> Campagne du 25/11/2026 réalisée sur le **cluster de préparation** (k3s v1.35.10, un nœud).
> **À rejouer et à dater sur notre plateforme de rendu** (VM du TP) avant le 20/01 : le script produit un
> nouveau journal qui remplace ce tableau.

| Test | Ce qu'on vérifie | Commande / preuve | Date | Résultat |
|---|---|---|---|---|
| R1 | Page de connexion en HTTPS | `curl` via l'Ingress : titre « Wiki Rhénatech », `openssl s_client` : TLSv1.3, chaîne vérifiée par l'autorité interne, HSTS, HTTP → 301 | 25/11 | **OK** |
| R2 | Un lecteur ne modifie rien | `lecteur@` : `GET …/edit` → 302 ; `PUT` forcé sur la page → `updated_at` inchangé | 25/11 | **OK** |
| R3 | Prestataire cloisonné | prestataire de recette (Prestataire + Accès Clinique) : procédures et sa clinique → 200 ; 2 autres clients, Commercial, RH, Exploitation, étagère Interne → 404 ; recherche « tarif » → 0 | 25/11 | **OK** |
| R4 | TOTP obligatoire ; compte désactivé | mot de passe seul → `/mfa/verify`, contenu inaccessible ; code décalé de 120 s → refusé ; bon code → accès ; `disable-user.sh` → connexion refusée, session ouverte coupée | 25/11 | **OK** |
| R5 | Journal d'audit | `editeur@` modifie « Basculer sur le lien WAN de secours » → entrée `page_update` par editeur@ (Paramètres › Journal d'audit) | 25/11 | **OK** |
| R6 | Pièce jointe 15 Mo | dépôt HTTPS par l'API, relecture identique (sha256), page retrouvée par la recherche ; 25 Mo refusé (422) | 25/11 | **OK** |
| R7 | Pods supprimés sans perte | `kubectl delete pod` BookStack puis `mariadb-0` : empreinte (entités, pièces, comptes, dernière modif.) identique, service revenu seul en **21 s** | 25/11 | **OK** |
| R8 | NetworkPolicy | pod `recette-intrus` → MariaDB:3306 **refusé** ; pod BookStack → joint | 25/11 | **OK** |
| R9 | Aucun secret dans Git | `git grep` des valeurs réelles de `.secrets/` : aucune ; aucune clé privée ; `.secrets/` ignoré | 25/11 | **OK** |
| R10 | Plateforme vidée, restaurée | `r10-disaster.sh` : namespace supprimé, `deploy.sh --no-init` (26 s), restauration de l'export (61 s) : contenus identiques, TOTP toujours valide, pièce de 15 Mo identique ; **remise en service 87 s** | 25/11 | **OK** |
| R11 | Mise à jour puis retour arrière | `upgrade.sh v26.09.3-ls301` : migration, `/status` OK, version v26.09.3 ; `rollback.sh` : v26.09.2 + restauration en **23 s**, contenus identiques | 25/11 | **OK** |
| R12 | État en une minute | `status.sh` en **1,1 s** | 25/11 | **OK** |

Défauts trouvés pendant la mise au point, corrigés puis re-testés (diagnostic dans la partie 5) :

| Date | Symptôme | Diagnostic | Correction |
|---|---|---|---|
| 25/11 | Pod BookStack redémarré par la startupProbe | `nginx: socket() [::]:80 failed (97)` : IPv6 absent sur le nœud | `10-rhenatech-init.sh` retire l'écoute IPv6 si besoin |
| 25/11 | « Permissions could not be set » au démarrage | `php-local.ini` monté en lecture seule dans `/config` | fichier copié par le script d'init au lieu d'un montage subPath |
| 25/11 | Sauvegarde « OK » de 4 Ko | `Can't connect to server on 'mariadb' (115)` : NetworkPolicy pas encore appliquée au pod neuf ; `sh` sans `pipefail` | attente de la base, `bash` + `pipefail`, contrôle « Dump completed » |
| 25/11 | Jeton d'API refusé « expiré » | colonne `api_tokens.expires_at` de type DATE | expiration au lendemain, jeton supprimé en fin de script |
