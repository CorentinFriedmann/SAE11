#!/usr/bin/env bash
# Sauvegarde immédiate (avant une mise à jour, une manipulation risquée, ou pour la recette).
# Lance un Job à partir du CronJob wiki-backup et affiche le nom de la sauvegarde produite.
source "$(dirname "$0")/lib.sh"
need kubectl

JOB="wiki-backup-manuel-$(date +%Y%m%d-%H%M%S)"
info "lancement du job ${JOB}"
k create job "$JOB" --from=cronjob/wiki-backup >/dev/null
if ! k wait --for=condition=complete "job/${JOB}" --timeout=30m; then
  k logs "job/${JOB}" --tail=50 || true
  die "la sauvegarde a échoué"
fi
LOGS=$(k logs "job/${JOB}")
echo "$LOGS"
NAME=$(sed -nE 's/^\[backup\] OK ([0-9-]+)$/\1/p' <<<"$LOGS" | tail -1)
[[ -n "$NAME" ]] || die "nom de sauvegarde introuvable dans les journaux"
ok "sauvegarde ${NAME}"
echo "$NAME" > "${SECRETS_DIR}/derniere-sauvegarde"
