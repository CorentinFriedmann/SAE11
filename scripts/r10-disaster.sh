#!/usr/bin/env bash
# Recette R10 : plateforme vidée, redéployée, restaurée — contenus revenus, temps mesuré.
#  1. empreinte du contenu (nb de pages, pièces jointes, dernière modification)
#  2. sauvegarde + export hors cluster
#  3. SUPPRESSION du namespace (base, fichiers, volume de sauvegarde)
#  4. redéploiement du socle (deploy.sh --no-init) + restauration de l'export
#  5. comparaison des empreintes ; durée totale = temps de remise en service (B11 : ≤ 4 h)
source "$(dirname "$0")/lib.sh"
need kubectl

fingerprint() {
  sql <<'SQL'
SELECT CONCAT('pages=', (SELECT COUNT(*) FROM entities WHERE type='page' AND deleted_at IS NULL),
              ' livres=', (SELECT COUNT(*) FROM entities WHERE type='book' AND deleted_at IS NULL),
              ' pieces_jointes=', (SELECT COUNT(*) FROM attachments),
              ' utilisateurs=', (SELECT COUNT(*) FROM users),
              ' derniere_maj=', (SELECT MAX(updated_at) FROM entities));
SQL
}

[[ "${1:-}" == "--yes" ]] || { read -r -p "R10 détruit le namespace ${NS}. Taper 'oui' : " a; [[ "$a" == "oui" ]] || die "annulé"; }

BEFORE=$(fingerprint)
info "empreinte avant : ${BEFORE}"
"${REPO_ROOT}/scripts/backup-now.sh" >/dev/null
NAME=$(cat "${SECRETS_DIR}/derniere-sauvegarde")
"${REPO_ROOT}/scripts/backup-export.sh" "$NAME"

T0=$(date +%s)
info "[chrono] destruction de la plateforme"
"${REPO_ROOT}/scripts/destroy.sh" --yes
T1=$(date +%s)
info "[chrono] redéploiement du socle"
"${REPO_ROOT}/scripts/deploy.sh" --no-init
T2=$(date +%s)
info "[chrono] restauration de ${BACKUP_LOCAL_DIR}/${NAME}"
"${REPO_ROOT}/scripts/restore.sh" "${BACKUP_LOCAL_DIR}/${NAME}"
T3=$(date +%s)

AFTER=$(fingerprint)
info "empreinte après : ${AFTER}"
echo "durées : destruction $((T1-T0)) s | redéploiement $((T2-T1)) s | restauration $((T3-T2)) s | remise en service $((T3-T1)) s"
if [[ "$BEFORE" == "$AFTER" ]]; then
  ok "R10 : contenus identiques après restauration (remise en service en $((T3-T1)) s)"
else
  die "R10 : empreintes différentes"
fi
