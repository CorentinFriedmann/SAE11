#!/usr/bin/env bash
# ET10 / B13 : mise à jour de version de BookStack SANS PERTE.
#   ./scripts/upgrade.sh v26.09.3-ls301
# 1) sauvegarde immédiate (la nouvelle version migre le schéma : seul un retour
#    à cette sauvegarde permet de revenir en arrière proprement)
# 2) changement d'image, attente des sondes (la startupProbe couvre la migration)
# 3) contrôle /status et version affichée
# Pour pérenniser : reporter la nouvelle étiquette dans k8s/kustomization.yaml et commiter.
source "$(dirname "$0")/lib.sh"
need kubectl

TAG="${1:?usage : $0 <étiquette, ex. v26.09.3-ls301>}"
[[ "$TAG" != "latest" ]] || die "latest est interdit : donner une version précise"
IMG="lscr.io/linuxserver/bookstack:${TAG}"
OLD=$(k get deploy bookstack -o jsonpath='{.spec.template.spec.containers[0].image}')
info "version actuelle : ${OLD} -> cible : ${IMG}"

"${REPO_ROOT}/scripts/backup-now.sh"
BACKUP=$(cat "${SECRETS_DIR}/derniere-sauvegarde")
echo "${BACKUP} ${OLD}" > "${SECRETS_DIR}/avant-mise-a-jour"
info "point de retour : sauvegarde ${BACKUP} (image ${OLD})"

START=$(date +%s)
k set image deployment/bookstack "bookstack=${IMG}"
k annotate deployment/bookstack kubernetes.io/change-cause="mise à jour ${TAG} (sauvegarde ${BACKUP})" --overwrite
if ! k rollout status deployment/bookstack --timeout=10m; then
  warn "la nouvelle version ne démarre pas : retour arrière conseillé -> ./scripts/rollback.sh"
  exit 1
fi
STATUS=$(wcurl "https://${WIKI_HOST}/status" || true)
ok "mise à jour en $(( $(date +%s) - START )) s ; /status = ${STATUS}"
k exec "$(bookstack_pod)" -c bookstack -- sh -c 'cat /app/www/version 2>/dev/null' | sed 's/^/version BookStack : /'
k rollout history deployment/bookstack
