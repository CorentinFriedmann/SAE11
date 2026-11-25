# 10. Références

| Référence | Utilisée pour |
|---|---|
| RFC 8446 — TLS 1.3 | chiffrement de l'accès HTTPS, TLS 1.2 minimum (TLSOption) |
| RFC 9110 — Sémantique HTTP | redirection permanente 301, codes 302/404/422 lus dans la recette |
| RFC 6797 — HSTS | forcer HTTPS côté navigateur (Middleware `security-headers`) |
| RFC 5280 — Certificats X.509 | autorité interne, chaîne de confiance, SAN, contraintes de base |
| RFC 8555 — ACME | pourquoi Let's Encrypt ne convient pas à un nom en `.lab` |
| RFC 6238 — TOTP | double authentification, piège de l'horloge (code décalé refusé) |
| RFC 4226 — HOTP | algorithme sous-jacent au TOTP (`scripts/totp.py`) |
| RFC 1918 — Adressage privé | réseau des VM (192.168.56.0/24) et du cluster (10.42/10.43) |
| RFC 2606 — Noms réservés | domaines `.example` des comptes prestataires fictifs |
| RFC 4511 / RFC 6749 | LDAP et OAuth 2.0 (OIDC) — suite B15 |
| RGPD, art. 5 et 30 | minimisation, durée de conservation, registre de traitement |
| Documentation | bookstackapp.com/docs (API, permissions, MFA, sauvegarde) · docs.linuxserver.io/images/docker-bookstack · hub.docker.com/_/mariadb · docs.k3s.io (Traefik, local-path, NetworkPolicy) · kubernetes.io/docs (StatefulSet, CronJob, NetworkPolicy, Pod Security) · doc.traefik.io (Middlewares, TLSOption) |
