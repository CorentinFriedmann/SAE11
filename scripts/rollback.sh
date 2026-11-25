#!/usr/bin/env bash
# ET10 / B13 : retour arrière après une mise à jour.
# Revenir à l'ancienne image NE SUFFIT PAS : la nouvelle version a migré le schéma de la base,
# l'ancienne ne sait pas le « dé-migrer ». Retour arrière = ancienne image + restauration
# de la sauvegarde prise juste avant la mise à jour (scripts/upgrade.sh l'a notée).
source "$(dirname "$0")/lib.sh"
need kubectl

[[ -f "${SECRETS_DIR}/avant-mise-a-jour" ]] || die "aucune mise à jour enregistrée (.secrets/avant-mise-a-jour)"
read -r BACKUP OLD < "${SECRETS_DIR}/avant-mise-a-jour"
info "retour à ${OLD} avec la sauvegarde ${BACKUP}"
warn "les modifications faites depuis la mise à jour seront perdues"

START=$(date +%s)
k scale deployment/bookstack --replicas=0 >/dev/null
k set image deployment/bookstack "bookstack=${OLD}"
k annotate deployment/bookstack kubernetes.io/change-cause="retour arrière vers ${OLD} (restauration ${BACKUP})" --overwrite
"${REPO_ROOT}/scripts/restore.sh" "$BACKUP"
ok "retour arrière terminé en $(( $(date +%s) - START )) s"
k exec "$(bookstack_pod)" -c bookstack -- sh -c 'cat /app/www/version 2>/dev/null' | sed 's/^/version BookStack : /'
