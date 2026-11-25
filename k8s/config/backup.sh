#!/bin/bash
# ET8 / B11 : sauvegarde quotidienne cohérente de la base ET des fichiers.
# Exécuté par le CronJob "wiki-backup" (image mariadb, uid 1000).
#  - mariadb-dump --single-transaction : instantané cohérent InnoDB sans bloquer les écritures
#  - archive de /config (pièces jointes, images, .env de l'image) monté en lecture seule
#  - un dossier horodaté par sauvegarde, avec somme de contrôle, et un marqueur DONE
#  - rétention : RETENTION_DAYS jours
# pipefail est indispensable : sans lui, un dump en échec suivi de "| gzip" serait vu comme réussi.
set -euo pipefail

TS=$(date +%Y%m%d-%H%M%S)
DEST="/backup/${TS}"
fail() { echo "[backup] ÉCHEC : $*"; rm -rf "${DEST}"; exit 1; }
trap 'fail "commande en erreur ligne ${LINENO}"' ERR

# Un pod tout juste créé peut attendre quelques secondes que kube-router applique
# les NetworkPolicy à sa nouvelle IP : on attend que MariaDB réponde (60 s max).
for i in $(seq 1 30); do
  mariadb-admin -h "${DB_HOST}" -u "${DB_USERNAME}" --connect-timeout=2 ping >/dev/null 2>&1 && break
  [[ $i -eq 30 ]] && fail "MariaDB injoignable"
  sleep 2
done

mkdir -p "${DEST}"
echo "[backup] début ${TS} -> ${DEST}"

# 1) Base : MYSQL_PWD (variable d'environnement) évite le mot de passe dans la liste des processus
mariadb-dump -h "${DB_HOST}" -u "${DB_USERNAME}" \
  --single-transaction --quick --routines --triggers --hex-blob \
  "${DB_DATABASE}" | gzip -6 > "${DEST}/bookstack.sql.gz"
# contrôle : un dump complet se termine par "-- Dump completed"
zcat "${DEST}/bookstack.sql.gz" | tail -1 | grep -q "Dump completed" || fail "dump incomplet"

# 2) Fichiers : on exclut journaux et caches régénérables
tar -czf "${DEST}/config.tar.gz" -C /config \
  --exclude=./log \
  --exclude=./www/framework/cache \
  --exclude=./www/framework/views \
  .

# 3) Contrôle d'intégrité + métadonnées
( cd "${DEST}" && sha256sum bookstack.sql.gz config.tar.gz > SHA256SUMS )
{
  echo "date=${TS}"
  echo "db_size=$(du -h "${DEST}/bookstack.sql.gz" | cut -f1)"
  echo "files_size=$(du -h "${DEST}/config.tar.gz" | cut -f1)"
  echo "tables=$(zcat "${DEST}/bookstack.sql.gz" | grep -c '^CREATE TABLE')"
} > "${DEST}/META"
touch "${DEST}/DONE"
trap - ERR

# 4) Rétention
find /backup -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +"${RETENTION_DAYS:-7}" \
  -print -exec rm -rf {} + | sed 's/^/[backup] supprimé (rétention) : /'

echo "[backup] OK ${TS}"
cat "${DEST}/META"
