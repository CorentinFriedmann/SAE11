#!/bin/bash
# B12 (RGPD) : durée de conservation du journal d'audit.
# BookStack conserve le journal indéfiniment ; on purge ce qui dépasse
# AUDIT_RETENTION_DAYS (365 jours, voir le registre de traitement).
set -euo pipefail
for i in $(seq 1 30); do mariadb-admin -h "${DB_HOST}" -u "${DB_USERNAME}" --connect-timeout=2 ping >/dev/null 2>&1 && break; sleep 2; done
echo "[purge] suppression des entrées du journal d'audit de plus de ${AUDIT_RETENTION_DAYS} jours"
mariadb -h "${DB_HOST}" -u "${DB_USERNAME}" "${DB_DATABASE}" -e "
  SELECT COUNT(*) AS a_supprimer FROM activities
    WHERE created_at < NOW() - INTERVAL ${AUDIT_RETENTION_DAYS} DAY;
  DELETE FROM activities
    WHERE created_at < NOW() - INTERVAL ${AUDIT_RETENTION_DAYS} DAY;
  SELECT COUNT(*) AS restant FROM activities;"
echo "[purge] OK"
