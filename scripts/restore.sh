#!/usr/bin/env bash
# B11 / ET8 : restauration complète (base + fichiers), chronométrée.
#   ./scripts/restore.sh --list                    # sauvegardes présentes sur le volume
#   ./scripts/restore.sh AAAAMMJJ-HHMMSS           # restaure une sauvegarde du volume wiki-backups
#   ./scripts/restore.sh backups/AAAAMMJJ-HHMMSS   # restaure une sauvegarde exportée (plateforme neuve)
#
# Déroulé : arrêt de BookStack (plus aucune écriture) -> (envoi de l'export) -> Job de restauration :
#   base supprimée/recréée puis rechargée, /config vidé puis réextrait -> redémarrage -> contrôle /status
source "$(dirname "$0")/lib.sh"
need kubectl

POD="wiki-backup-browser"
JOB="wiki-restore-$(date +%Y%m%d-%H%M%S)"
IMAGE=$(k get cronjob wiki-backup -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')

browser_up() {
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
}
browser_down() { k delete pod "$POD" --wait=true --ignore-not-found >/dev/null 2>&1 || true; }

[[ $# -ge 1 ]] || die "usage : $0 --list | AAAAMMJJ-HHMMSS | backups/AAAAMMJJ-HHMMSS"

if [[ "$1" == "--list" ]]; then
  browser_up
  k exec "$POD" -- sh -c 'for d in /backup/20*; do [ -f "$d/DONE" ] && echo "$(basename "$d")  $(cat "$d/META" | tr "\n" " ")"; done' || true
  browser_down
  exit 0
fi

START=$(date +%s)
SRC="$1"
if [[ -d "$SRC" ]]; then
  NAME=$(basename "$SRC")
  ( cd "$SRC" && sha256sum -c SHA256SUMS >/dev/null ) || die "somme de contrôle invalide dans ${SRC}"
  info "envoi de la sauvegarde locale ${NAME} sur le volume wiki-backups"
  browser_up
  k exec "$POD" -- mkdir -p "/backup/${NAME}"
  for f in bookstack.sql.gz config.tar.gz SHA256SUMS META DONE; do
    k cp "${SRC}/${f}" "${POD}:/backup/${NAME}/${f}" >/dev/null
  done
  browser_down
else
  NAME="$SRC"
fi

info "arrêt de BookStack (plus aucune écriture pendant la restauration)"
k scale deployment/bookstack --replicas=0 >/dev/null
k wait --for=delete pod -l app=bookstack --timeout=3m >/dev/null 2>&1 || true

info "job de restauration ${JOB} (sauvegarde ${NAME})"
k apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB}
  labels: { app: wiki-maintenance }
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels: { app: wiki-maintenance }
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext: { runAsNonRoot: true, runAsUser: 1000, runAsGroup: 1000, fsGroup: 1000, seccompProfile: { type: RuntimeDefault } }
      containers:
        - name: restore
          image: ${IMAGE}
          securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ["ALL"] } }
          env:
            - name: MYSQL_PWD
              valueFrom: { secretKeyRef: { name: wiki-secrets, key: MARIADB_ROOT_PASSWORD } }
          command:
            - /bin/bash
            - -c
            - |
              set -euo pipefail
              D=/backup/${NAME}
              # attendre que les NetworkPolicy s'appliquent à ce nouveau pod
              for i in \$(seq 1 30); do mariadb-admin -h mariadb -u root --connect-timeout=2 ping >/dev/null 2>&1 && break; sleep 2; done
              test -f "\$D/DONE" || { echo "sauvegarde incomplète : \$D"; exit 1; }
              cd "\$D" && sha256sum -c SHA256SUMS
              echo "[restore] base de données"
              mariadb -h mariadb -u root -e "DROP DATABASE IF EXISTS bookstack; CREATE DATABASE bookstack CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
              gunzip -c "\$D/bookstack.sql.gz" | mariadb -h mariadb -u root bookstack
              echo "[restore] fichiers (/config)"
              find /config -mindepth 1 -delete
              tar -xzf "\$D/config.tar.gz" -C /config
              echo "[restore] OK"
          volumeMounts:
            - { name: config, mountPath: /config }
            - { name: backups, mountPath: /backup, readOnly: true }
      volumes:
        - name: config
          persistentVolumeClaim: { claimName: bookstack-config }
        - name: backups
          persistentVolumeClaim: { claimName: wiki-backups }
EOF
if ! k wait --for=condition=complete "job/${JOB}" --timeout=60m; then
  k logs "job/${JOB}" --tail=50 || true
  die "restauration en échec : BookStack reste arrêté (corriger puis relancer, ou kubectl -n ${NS} scale deploy/bookstack --replicas=1)"
fi
k logs "job/${JOB}"

info "redémarrage de BookStack"
k scale deployment/bookstack --replicas=1 >/dev/null
k rollout status deployment/bookstack --timeout=10m
k exec "$(bookstack_pod)" -c bookstack -- php /app/www/artisan cache:clear >/dev/null 2>&1 || true

DUR=$(( $(date +%s) - START ))
ok "restauration de ${NAME} terminée en ${DUR} s ($(date -u -d @${DUR} +%Hh%Mm%Ss))"
echo "$(date '+%F %T') restauration ${NAME} ${DUR}s" >> "${SECRETS_DIR}/journal-restaurations.log"
