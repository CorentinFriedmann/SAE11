#!/usr/bin/env bash
# Supprime TOUT le wiki du cluster (namespace, volumes, données). Les secrets locaux
# (.secrets/) et les sauvegardes exportées (backups/) ne sont pas touchés.
# Utilisé pour la recette R10 (plateforme vidée, redéployée, restaurée).
source "$(dirname "$0")/lib.sh"
need kubectl

if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Supprimer le namespace ${NS} et TOUTES ses données ? Taper 'oui' : " a
  [[ "$a" == "oui" ]] || die "annulé"
fi
info "suppression du namespace ${NS}"
kubectl delete namespace "$NS" --wait=true --timeout=5m
ok "namespace ${NS} supprimé"
