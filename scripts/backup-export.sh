#!/usr/bin/env bash
# Copie une sauvegarde (par défaut : la plus récente) HORS du cluster, dans backups/ (ignoré par Git).
# Sans cette copie, supprimer le namespace ou perdre le nœud fait perdre aussi les sauvegardes.
#   ./scripts/backup-export.sh [AAAAMMJJ-HHMMSS]
source "$(dirname "$0")/lib.sh"
need kubectl

POD="wiki-backup-browser"
cleanup() { k delete pod "$POD" --wait=false --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Pod utilitaire qui monte le volume des sauvegardes (même image que le CronJob)
IMAGE=$(k get cronjob wiki-backup -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')
k apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD}
  labels: { app: wiki-maintenance }
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 1
  automountServiceAccountToken: false
  securityContext: { runAsNonRoot: true, runAsUser: 1000, runAsGroup: 1000, seccompProfile: { type: RuntimeDefault } }
  containers:
    - name: shell
      image: ${IMAGE}
      command: ["sleep", "3600"]
      securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ["ALL"] } }
      volumeMounts: [{ name: backups, mountPath: /backup }]
  volumes:
    - name: backups
      persistentVolumeClaim: { claimName: wiki-backups }
EOF
k wait --for=condition=Ready "pod/${POD}" --timeout=3m >/dev/null

NAME="${1:-$(k exec "$POD" -- sh -c 'ls -1d /backup/20*/DONE 2>/dev/null | sort | tail -1 | cut -d/ -f3')}"
[[ -n "$NAME" ]] || die "aucune sauvegarde complète sur le volume"
mkdir -p "${BACKUP_LOCAL_DIR}/${NAME}"
info "export de ${NAME} -> ${BACKUP_LOCAL_DIR}/${NAME}"
for f in bookstack.sql.gz config.tar.gz SHA256SUMS META DONE; do
  k cp "${POD}:/backup/${NAME}/${f}" "${BACKUP_LOCAL_DIR}/${NAME}/${f}" >/dev/null
done
( cd "${BACKUP_LOCAL_DIR}/${NAME}" && sha256sum -c SHA256SUMS ) || die "somme de contrôle invalide"
ok "sauvegarde exportée et vérifiée : ${BACKUP_LOCAL_DIR}/${NAME}"
