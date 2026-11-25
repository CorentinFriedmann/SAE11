#!/usr/bin/env bash
# ET2 : déploiement complet DE ZÉRO EN UNE COMMANDE.
#   ./scripts/deploy.sh            # socle + configuration BookStack (rôles, étagères, comptes)
#   ./scripts/deploy.sh --no-init  # socle seul (utilisé avant une restauration, recette R10)
#
# Étapes : secrets locaux -> namespace -> Secrets Kubernetes -> kubectl apply -k
#          -> attente des sondes -> initialisation de BookStack (scripts/init-bookstack.sh)
source "$(dirname "$0")/lib.sh"
need kubectl openssl curl

INIT=1
[[ "${1:-}" == "--no-init" ]] && INIT=0

START=$(date +%s)
kubectl version --request-timeout=5s >/dev/null 2>&1 || die "cluster injoignable (kubeconfig ?)"

info "1/5 secrets locaux (.secrets/, hors Git)"
"${REPO_ROOT}/scripts/gen-secrets.sh"

info "2/5 namespace ${NS}"
kubectl apply -f "${REPO_ROOT}/k8s/namespace.yaml"

info "3/5 Secrets Kubernetes (wiki-secrets, wiki-tls)"
kubectl -n "$NS" create secret generic wiki-secrets \
  --from-env-file="${SECRETS_DIR}/wiki-secrets.env" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret tls wiki-tls \
  --cert="${SECRETS_DIR}/tls/tls.crt" --key="${SECRETS_DIR}/tls/tls.key" --dry-run=client -o yaml | kubectl apply -f -

info "4/5 manifestes (kubectl apply -k k8s/)"
kubectl apply -k "${REPO_ROOT}/k8s"
wait_ready

if [[ $INIT -eq 1 ]]; then
  info "5/5 configuration de BookStack (rôles, TOTP, étagères, comptes de démonstration)"
  "${REPO_ROOT}/scripts/init-bookstack.sh"
else
  info "5/5 initialisation de BookStack ignorée (--no-init)"
fi

ok "déployé en $(( $(date +%s) - START )) s"
cat <<EOF

  URL           : https://${WIKI_HOST}
  Fichier hosts : $(ingress_ip)  ${WIKI_HOST}
  Autorité TLS  : ${SECRETS_DIR}/tls/ca.crt   (à importer comme autorité de confiance)
  Comptes démo  : ${SECRETS_DIR}/comptes-demo.txt
  État          : ./scripts/status.sh
EOF
