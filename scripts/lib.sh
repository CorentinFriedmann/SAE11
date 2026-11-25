#!/usr/bin/env bash
# Fonctions communes aux scripts d'exploitation du wiki Rhénatech.
# shellcheck disable=SC2034

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="${NS:-wiki}"
WIKI_HOST="${WIKI_HOST:-wiki.rhenatech.lab}"
SECRETS_DIR="${SECRETS_DIR:-${REPO_ROOT}/.secrets}"     # ignoré par Git
BACKUP_LOCAL_DIR="${BACKUP_LOCAL_DIR:-${REPO_ROOT}/backups}"  # ignoré par Git

if [[ -t 1 ]]; then
  C_OK=$'\e[32m'; C_KO=$'\e[31m'; C_INFO=$'\e[36m'; C_WARN=$'\e[33m'; C_END=$'\e[0m'
else
  C_OK=""; C_KO=""; C_INFO=""; C_WARN=""; C_END=""
fi

info() { echo "${C_INFO}==>${C_END} $*"; }
ok()   { echo "${C_OK}[OK]${C_END} $*"; }
warn() { echo "${C_WARN}[!]${C_END} $*" >&2; }
die()  { echo "${C_KO}[ERREUR]${C_END} $*" >&2; exit 1; }

need() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "commande manquante : $c"
  done
}

k() { kubectl -n "$NS" "$@"; }

# Adresse IP à laquelle joindre l'Ingress (pour curl --resolve, sans dépendre du fichier hosts)
ingress_ip() {
  if [[ -n "${INGRESS_IP:-}" ]]; then echo "$INGRESS_IP"; return; fi
  local ip
  ip=$(kubectl -n kube-system get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -n "$ip" ]] || ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
  echo "$ip"
}

# curl vers le wiki via l'Ingress, en faisant confiance à l'autorité interne si elle existe
wcurl() {
  local ca=()
  if [[ -f "${SECRETS_DIR}/tls/ca.crt" ]]; then ca=(--cacert "${SECRETS_DIR}/tls/ca.crt"); else ca=(-k); fi
  curl -sS --noproxy "*" "${ca[@]}" --resolve "${WIKI_HOST}:443:$(ingress_ip)" --resolve "${WIKI_HOST}:80:$(ingress_ip)" "$@"
}

bookstack_pod() { k get pod -l app=bookstack --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}'; }

wait_ready() {
  info "attente de MariaDB et BookStack…"
  k rollout status statefulset/mariadb --timeout=10m
  k rollout status deployment/bookstack --timeout=10m
}

# Requête SQL dans le pod MariaDB (utilisateur applicatif, mot de passe lu dans l'environnement du pod)
sql() {
  k exec -i mariadb-0 -c mariadb -- sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" mariadb -u "$MARIADB_USER" "$MARIADB_DATABASE" --batch --skip-column-names'
}

# ---------------------------------------------------------------------------
# Jeton d'API temporaire pour l'administrateur (créé en base, supprimé à la fin).
# Évite de cliquer dans l'interface pour obtenir un jeton : le secret ne quitte
# jamais la machine d'administration et est supprimé en fin de script (expiration au plus tard le lendemain).
# ---------------------------------------------------------------------------
API_TOKEN_ID=""
API_TOKEN_SECRET=""

api_token_create() {
  local name="${1:-script-exploitation}" pod hash admin_id
  pod=$(bookstack_pod)
  API_TOKEN_ID="tmp$(openssl rand -hex 12)"
  API_TOKEN_SECRET="$(openssl rand -hex 24)"
  # hachage bcrypt calculé par PHP dans le pod BookStack (compatible Hash::check de Laravel)
  hash=$(k exec -i "$pod" -c bookstack -- php -r 'echo password_hash(trim(fgets(STDIN)), PASSWORD_BCRYPT);' <<<"$API_TOKEN_SECRET")
  admin_id=$(sql <<<"SELECT u.id FROM users u JOIN role_user ru ON ru.user_id=u.id JOIN roles r ON r.id=ru.role_id WHERE r.system_name='admin' ORDER BY u.id LIMIT 1;")
  [[ -n "$admin_id" ]] || die "administrateur introuvable en base"
  sql <<SQL
INSERT INTO api_tokens (name, token_id, secret, user_id, expires_at, created_at, updated_at)
VALUES ('${name}', '${API_TOKEN_ID}', '${hash}', ${admin_id}, DATE_ADD(CURDATE(), INTERVAL 1 DAY), NOW(), NOW());
SQL
  trap api_token_delete EXIT
}

api_token_delete() {
  [[ -n "$API_TOKEN_ID" ]] || return 0
  sql <<<"DELETE FROM api_tokens WHERE token_id='${API_TOKEN_ID}';" || true
  API_TOKEN_ID=""
}

# api METHODE chemin [json]  -> réponse JSON (appel depuis le pod, sans passer par le réseau)
api() {
  local method="$1" path="$2" data="${3:-}" pod
  pod=$(bookstack_pod)
  if [[ -n "$data" ]]; then
    k exec -i "$pod" -c bookstack -- curl -sS -g -X "$method" \
      -H "Authorization: Token ${API_TOKEN_ID}:${API_TOKEN_SECRET}" \
      -H "Content-Type: application/json" -H "Accept: application/json" \
      --data-binary @- "http://localhost/api/${path}" <<<"$data"
  else
    k exec "$pod" -c bookstack -- curl -sS -g -X "$method" \
      -H "Authorization: Token ${API_TOKEN_ID}:${API_TOKEN_SECRET}" \
      -H "Accept: application/json" "http://localhost/api/${path}"
  fi
}

# Tentative de connexion par le formulaire web (via l'Ingress, en HTTPS).
# Affiche l'URL vers laquelle BookStack redirige après le POST :
#   /            -> connecté
#   /mfa/setup   -> mot de passe bon, mais double authentification à enrôler (B5)
#   /mfa/verify  -> mot de passe bon, code TOTP demandé (B5)
#   /login       -> refus
web_login() {
  local email="$1" password="$2" jar="$3" token
  rm -f "$jar"
  token=$(wcurl -c "$jar" -b "$jar" "https://${WIKI_HOST}/login" | grep -oE 'name="_token" value="[^"]+"' | head -1 | sed -E 's/.*value="([^"]+)"/\1/')
  wcurl -c "$jar" -b "$jar" -o /dev/null -w '%{redirect_url}' \
    --data-urlencode "_token=${token}" --data-urlencode "email=${email}" --data-urlencode "password=${password}" \
    "https://${WIKI_HOST}/login"
}
