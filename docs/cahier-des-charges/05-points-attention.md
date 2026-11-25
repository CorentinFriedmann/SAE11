# 5. Points d'attention

> **APP_KEY.** Elle chiffre les sessions et les secrets TOTP stockés en base. Perdue ou changée : la
> base se restaure, mais **tous les utilisateurs doivent ré-enrôler leur TOTP**. Générée une seule fois
> par `gen-secrets.sh`, conservée dans `.secrets/wiki-secrets.env` (hors Git, à copier dans un coffre
> hors ligne), jamais régénérée par un redéploiement. Vérifié : après R10, le TOTP du prestataire fonctionne toujours.

> **APP_URL.** Doit être exactement `https://wiki.rhenatech.lab`, sans barre finale. Une autre adresse
> (IP, http, port) donne redirections en boucle, images cassées, liens faux. Changer d'adresse après coup :
> `php artisan bookstack:update-url`. Traefik termine TLS : `APP_PROXIES=10.42.0.0/16` fait confiance à ses en-têtes.

> **Volume lié à un nœud.** local-path écrit sur le disque d'un nœud (RWO) : si ce nœud tombe, le pod
> reste *Pending* jusqu'à son retour ou une restauration ailleurs. Mesuré : restauration complète sur
> plateforme neuve en **87 s** (R10). Limite assumée ; parade : stockage partagé (Longhorn/NFS) et deux réplicas (A3).

> **Sauvegarde cohérente.** `--single-transaction` donne un instantané InnoDB cohérent **sans bloquer
> les écritures** ; les fichiers sont archivés juste après. Une pièce jointe ajoutée entre les deux peut
> manquer à la base restaurée (fichier orphelin, sans gravité) ; l'inverse est impossible dans ce sens.
> Piège rencontré : en `sh`, `mariadb-dump | gzip` « réussit » même si le dump échoue. Le script tourne en
> `bash` avec `pipefail` et vérifie la ligne `-- Dump completed`.

> **NetworkPolicy et pods neufs.** kube-router met quelques secondes à autoriser l'IP d'un pod qui vient
> de naître : notre première sauvegarde n'a pas joint MariaDB. Les jobs attendent désormais que la base
> réponde (`mariadb-admin ping`, 60 s max). Après « tout refusé », penser au **DNS** (port 53 UDP et TCP).

> **Mise à jour de la base.** Au démarrage, une nouvelle version de BookStack migre le schéma ; l'ancienne
> image ne sait pas revenir en arrière. **Retour arrière = ancienne image + restauration de la sauvegarde
> prise juste avant** : `upgrade.sh` la prend et la note, `rollback.sh` l'utilise. Les modifications faites
> entre la mise à jour et le retour arrière sont perdues : on décide vite.

> **Droits sur les étagères.** Les permissions d'une étagère **ne s'appliquent pas** à ses livres (seulement
> à l'affichage de l'étagère). Il faut les poser sur chaque livre — c'est ce que fait le script, et ce que
> vérifie R3 avec un vrai compte prestataire.

> **Horloge et TOTP (RFC 6238).** Le code change toutes les 30 s ; un serveur ou un téléphone décalé de
> plus d'environ 30 s voit tous ses codes refusés. NTP activé sur la VM ; la recette le démontre : un code
> calculé avec 120 s d'avance est refusé, le code à l'heure est accepté. Premier réflexe si un prestataire
> est refusé : `timedatectl` sur la VM, puis l'heure de son téléphone.

> **IPv6 absent.** Sur une VM démarrée avec IPv6 désactivé, nginx (image linuxserver) refuse de démarrer
> sur `listen [::]:80`. Le script d'initialisation `10-rhenatech-init.sh` retire alors l'écoute IPv6.

> **Limites de téléversement.** Trois étages : BookStack (`FILE_UPLOAD_SIZE_LIMIT`, en Mo), PHP
> (`upload_max_filesize`, `post_max_size`) et le proxy (Traefik : pas de limite ; ingress-nginx : `proxy-body-size`).
> Testé : 15 Mo acceptés, 25 Mo refusés proprement (HTTP 422).
