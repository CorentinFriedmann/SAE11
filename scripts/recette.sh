#!/usr/bin/env bash
# Recette R1 à R12 (partie 2 du sujet). Chaque test affiche sa commande/preuve et un verdict,
# et le journal complet est écrit dans docs/recette/journal-AAAAMMJJ-HHMMSS.md.
#   ./scripts/recette.sh            # R1-R9 et R12 (non destructifs)
#   ./scripts/recette.sh --complet  # + R10 (destruction/restauration) et R11 (mise à jour/retour arrière)
source "$(dirname "$0")/lib.sh"
need kubectl curl jq openssl python3 git

COMPLET=0; [[ "${1:-}" == "--complet" ]] && COMPLET=1
UPGRADE_TAG="${UPGRADE_TAG:-v26.09.3-ls301}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; api_token_delete' EXIT
STAMP=$(date +%Y%m%d-%H%M%S)
JOURNAL="${REPO_ROOT}/docs/recette/journal-${STAMP}.md"
URL="https://${WIKI_HOST}"
ACC="${SECRETS_DIR}/comptes-demo.txt"
pw_of() { awk -v e="$1" '$1==e{print $2}' "$ACC" | tail -1; }
code_of() { wcurl -b "$1" -o /dev/null -w '%{http_code}' "$2"; }
csrf() { grep -oE 'name="_token" value="[^"]+"' | head -1 | sed -E 's/.*value="([^"]+)"/\1/'; }

declare -a ROWS
PASS=0; FAIL=0
verdict() {  # code description OK|KO détail
  local c="$1" d="$2" v="$3" det="$4"
  if [[ "$v" == OK ]]; then PASS=$((PASS+1)); echo "${C_OK}[$c OK]${C_END} $d — $det"
  else FAIL=$((FAIL+1)); echo "${C_KO}[$c KO]${C_END} $d — $det"; fi
  ROWS+=("| $c | $d | $(date '+%d/%m %H:%M') | **$v** · ${det//|/\\|} |")
}
is() { [[ "$1" == "$2" ]] && echo OK || echo KO; }

wait_ready >/dev/null
api_token_create "recette"

# ------------------------------------------------------------------- R1
R1_LOC=$(wcurl -o /dev/null -w '%{redirect_url}' "$URL/")
R1_TITLE=$(wcurl "$URL/login" | grep -oE '<title>[^<]*' | sed 's/<title>//')
R1_TLS=$(openssl s_client -connect "$(ingress_ip):443" -servername "$WIKI_HOST" -CAfile "${SECRETS_DIR}/tls/ca.crt" </dev/null 2>/dev/null | grep -E '^ *(Protocol|Verify return code)' | sed 's/^ *//' | sort -u | tr '\n' ' ')
R1_HSTS=$(wcurl -I "$URL/login" | grep -i '^strict-transport' | tr -d '\r')
R1_HTTP=$(wcurl -o /dev/null -w '%{http_code}' "http://${WIKI_HOST}/login")
[[ "$R1_LOC" == "$URL/login" && "$R1_TITLE" == *"Rhénatech"* && "$R1_TLS" == *"(ok)"* && -n "$R1_HSTS" && "$R1_HTTP" == 301 ]] && v=OK || v=KO
verdict R1 "https://wiki.rhenatech.lab affiche la page de connexion" $v "titre « ${R1_TITLE} », ${R1_TLS}, HSTS présent, http→https ${R1_HTTP}"

# ------------------------------------------------------------------- R2
J="$TMP/lecteur"
web_login lecteur@rhenatech.lab "$(pw_of lecteur@rhenatech.lab)" "$J" >/dev/null
P="$URL/books/procedures-reseau/page/basculer-sur-le-lien-wan-de-secours"
BEFORE=$(sql <<<"SELECT updated_at FROM entities WHERE slug='basculer-sur-le-lien-wan-de-secours';")
E=$(code_of "$J" "$P/edit")
TOK=$(wcurl -b "$J" -c "$J" "$P" | csrf)
wcurl -b "$J" -c "$J" -o /dev/null --data-urlencode "_token=$TOK" --data-urlencode _method=PUT \
  --data-urlencode "name=Piraté" --data-urlencode "markdown=modification interdite" "$P"
AFTER=$(sql <<<"SELECT updated_at FROM entities WHERE slug='basculer-sur-le-lien-wan-de-secours';")
[[ "$E" != 200 && "$BEFORE" == "$AFTER" ]] && v=OK || v=KO
verdict R2 "Un lecteur ne peut pas modifier une page" $v "GET /edit → HTTP $E (redirection), PUT forcé → page inchangée (updated_at ${AFTER})"

# ------------------------------------------------------------------- R3 / R4 : prestataire de recette
info "création d'un prestataire de recette (Prestataire + Accès client – Clinique des Tilleuls)"
RP_EMAIL="recette.prestataire@alpha-reseaux.example"; RP_PW="$(openssl rand -hex 12)"
OLD=$(api GET "users?count=500" | jq -r --arg e "$RP_EMAIL" '.data[]|select(.email==$e)|.id')
[[ -n "$OLD" ]] && api DELETE "users/$OLD" >/dev/null
R_PRESTA=$(api GET "roles?count=500" | jq -r '.data[]|select(.display_name=="Prestataire")|.id')
R_CLIN=$(api GET "roles?count=500" | jq -r '.data[]|select(.display_name=="Accès client – Clinique des Tilleuls")|.id')
api POST users "$(jq -n --arg e "$RP_EMAIL" --arg p "$RP_PW" --argjson r "[$R_PRESTA,$R_CLIN]" \
  '{name:"Prestataire de recette", email:$e, password:$p, roles:$r, send_invite:false}')" >/dev/null

J="$TMP/presta"
L1=$(web_login "$RP_EMAIL" "$RP_PW" "$J")
NOTOTP=$(code_of "$J" "$URL/books/procedures-reseau")     # mot de passe bon, pas encore de TOTP
# enrôlement TOTP (ce que ferait l'utilisateur avec son application)
wcurl -b "$J" -c "$J" -o /dev/null "$URL/mfa/setup"
G=$(wcurl -b "$J" -c "$J" "$URL/mfa/totp/generate")
SECRET=$(grep -oE 'secret=[A-Z2-7]+' <<<"$G" | head -1 | cut -d= -f2)
wcurl -b "$J" -c "$J" -o /dev/null --data-urlencode "_token=$(csrf <<<"$G")" \
  --data-urlencode "code=$(python3 "${REPO_ROOT}/scripts/totp.py" "$SECRET")" "$URL/mfa/totp/confirm"
# nouvelle connexion : mot de passe puis code
J="$TMP/presta2"
L2=$(web_login "$RP_EMAIL" "$RP_PW" "$J")
V=$(wcurl -b "$J" -c "$J" "$URL/mfa/verify")
BAD=$(wcurl -b "$J" -c "$J" -o /dev/null -w '%{redirect_url}' --data-urlencode "_token=$(csrf <<<"$V")" \
  --data-urlencode "code=$(python3 "${REPO_ROOT}/scripts/totp.py" "$SECRET" 120)" "$URL/mfa/totp/verify")
V=$(wcurl -b "$J" -c "$J" "$URL/mfa/verify")
GOOD=$(wcurl -b "$J" -c "$J" -o /dev/null -w '%{redirect_url}' --data-urlencode "_token=$(csrf <<<"$V")" \
  --data-urlencode "code=$(python3 "${REPO_ROOT}/scripts/totp.py" "$SECRET")" "$URL/mfa/totp/verify")

declare -A EXPECT=(
  [/books/procedures-reseau]=200 [/books/client-clinique-des-tilleuls]=200 [/shelves/procedures-dintervention]=200
  [/books/client-brasserie-lauch]=404 [/books/client-commune-de-val-dill]=404
  [/books/commercial]=404 [/books/ressources-humaines]=404 [/books/exploitation-du-wiki]=404 [/shelves/interne]=404
)
v=OK; det=""
for p in "${!EXPECT[@]}"; do
  c=$(code_of "$J" "$URL$p"); det+="$p=$c "
  [[ "$c" == "${EXPECT[$p]}" ]] || v=KO
done
HITS=$(wcurl -b "$J" "$URL/search?term=tarif" | grep -c 'entity-list-item-name' || true)
[[ "$HITS" == 0 ]] || v=KO
verdict R3 "Un prestataire ne voit que ses procédures et ses clients" $v "${det}; recherche « tarif » : ${HITS} résultat"

[[ "$L1" == *"/mfa/"* && "$NOTOTP" == 302 && "$BAD" == *"/mfa/verify" && "$GOOD" == "$URL/" ]] && v1=OK || v1=KO
"${REPO_ROOT}/scripts/disable-user.sh" "$RP_EMAIL" >/dev/null
L3=$(web_login "$RP_EMAIL" "$RP_PW" "$TMP/presta3")
AFTERDIS=$(code_of "$J" "$URL/books/procedures-reseau")
[[ "$v1" == OK && "$L3" == "$URL/login" && "$AFTERDIS" != 200 ]] && v=OK || v=KO
verdict R4 "Sans code TOTP pas de connexion ; compte désactivé refusé" $v "mot de passe seul → ${L1#$URL}, contenu → HTTP ${NOTOTP} ; code décalé de 120 s → refusé ; bon code → accès ; après disable-user.sh : connexion → ${L3#$URL}, session ouverte → HTTP ${AFTERDIS}"

# ------------------------------------------------------------------- R5
J="$TMP/editeur"
web_login editeur@rhenatech.lab "$(pw_of editeur@rhenatech.lab)" "$J" >/dev/null
E=$(wcurl -b "$J" -c "$J" "$P/edit")
MD=$(python3 -c 'import sys,html,re; s=sys.stdin.read(); m=re.search(r"<textarea[^>]*name=\"markdown\"[^>]*>(.*?)</textarea>", s, re.S); print(html.unescape(m.group(1)) if m else "")' <<<"$E")
MD=$(sed '/^> Recette R5/d' <<<"$MD")
wcurl -b "$J" -c "$J" -o /dev/null --data-urlencode "_token=$(csrf <<<"$E")" --data-urlencode _method=PUT \
  --data-urlencode "name=Basculer sur le lien WAN de secours" --data-urlencode "summary=Recette R5" \
  --data-urlencode "markdown=${MD}
> Recette R5 : relu par l'éditeur le $(date '+%F %T')." "$P"
LAST=$(sql <<<"SELECT CONCAT(a.created_at,' ',u.email,' ',a.type) FROM activities a JOIN users u ON u.id=a.user_id WHERE a.type='page_update' ORDER BY a.id DESC LIMIT 1;")
[[ "$LAST" == *"editeur@rhenatech.lab page_update"* ]] && v=OK || v=KO
verdict R5 "Le journal d'audit montre la modification d'un éditeur" $v "dernière entrée : ${LAST} (visible dans Paramètres › Journal d'audit)"

# ------------------------------------------------------------------- R6
head -c 15728640 /dev/urandom > "$TMP/export-15Mo.bin"
PAGE_ID=$(sql <<<"SELECT id FROM entities WHERE type='page' AND slug='restaurer-le-wiki' LIMIT 1;")
UP=$(wcurl -H "Authorization: Token ${API_TOKEN_ID}:${API_TOKEN_SECRET}" -F "name=Recette R6 export 15 Mo" \
  -F "uploaded_to=${PAGE_ID}" -F "file=@$TMP/export-15Mo.bin" "$URL/api/attachments")
AID=$(jq -r '.id // empty' <<<"$UP")
SUM_OK=KO
if [[ -n "$AID" ]]; then
  [[ "$(api GET "attachments/$AID" | jq -r .content | base64 -d | sha256sum | cut -d' ' -f1)" == "$(sha256sum < "$TMP/export-15Mo.bin" | cut -d' ' -f1)" ]] && SUM_OK=OK
fi
FOUND=$(api GET "search?query=restaurer" | jq -r '[.data[]|select(.name=="Restaurer le wiki")]|length')
[[ "$SUM_OK" == OK && "$FOUND" -ge 1 ]] && v=OK || v=KO
verdict R6 "Pièce jointe de 15 Mo déposée, retrouvée par la recherche" $v "dépôt HTTPS → pièce #${AID:-?}, relue à l'identique (sha256) ; recherche → page « Restaurer le wiki »"
[[ -n "$AID" ]] && api DELETE "attachments/$AID" >/dev/null

# ------------------------------------------------------------------- R7
fp() { sql <<<"SELECT CONCAT((SELECT COUNT(*) FROM entities WHERE deleted_at IS NULL),'/',(SELECT COUNT(*) FROM attachments),'/',(SELECT COUNT(*) FROM users),'/',(SELECT MAX(updated_at) FROM entities));"; }
F1=$(fp); T=$(date +%s)
k delete pod -l app=bookstack --wait=false >/dev/null
k delete pod mariadb-0 --wait=false >/dev/null
sleep 3
wait_ready >/dev/null
until [[ "$(wcurl -o /dev/null -w '%{http_code}' "$URL/status" 2>/dev/null)" == 200 ]]; do sleep 2; done
DT=$(( $(date +%s) - T )); F2=$(fp)
verdict R7 "Pods BookStack puis MariaDB supprimés : contenus intacts" "$(is "$F1" "$F2")" "empreinte ${F1} → ${F2}, service revenu seul en ${DT} s"

# ------------------------------------------------------------------- R8
k delete pod recette-intrus --ignore-not-found >/dev/null 2>&1
IMG=$(k get sts mariadb -o jsonpath='{.spec.template.spec.containers[0].image}')
k run recette-intrus --image="$IMG" --restart=Never --labels=app=recette-intrus \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":999,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"recette-intrus","image":"'"$IMG"'","command":["bash","-c","sleep 10; timeout 5 bash -c \"</dev/tcp/mariadb/3306\" && echo JOINT || echo REFUSE"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' >/dev/null
k wait --for=jsonpath='{.status.phase}'=Succeeded pod/recette-intrus --timeout=90s >/dev/null 2>&1 || true
INTRUS=$(k logs recette-intrus 2>/dev/null | tail -1)
k delete pod recette-intrus --wait=false >/dev/null 2>&1
BS=$(k exec "$(bookstack_pod)" -c bookstack -- php -r '$s=@fsockopen("mariadb",3306,$e,$m,3); echo $s?"JOINT":"REFUSE";')
[[ "$INTRUS" == REFUSE && "$BS" == JOINT ]] && v=OK || v=KO
verdict R8 "Un pod de test ne joint pas MariaDB ; BookStack y accède" $v "pod sans label autorisé → ${INTRUS:-pas de réponse} ; pod BookStack → ${BS}"

# ------------------------------------------------------------------- R9
cd "$REPO_ROOT"
G1=$(git grep -n -I -i -E 'password|app_key' -- . ':!docs' ':!*.md' | grep -v -E 'secretKeyRef|MYSQL_PWD|_PASSWORD"?$|DB_PASSWORD|PASSWORD:|password:\$p|password_hash|--data-urlencode|valeur factice|CHANGEZ-MOI|"password"|pw_of|RP_PW|\$pw|password=|key: |APP_KEY \(|APP_KEY=base64:\$\(' | head -5 || true)
G2=""
if [[ -f "${SECRETS_DIR}/wiki-secrets.env" ]]; then
  while IFS='=' read -r key val; do
    [[ -n "$val" ]] && git grep -q -F -- "$val" && G2+="$key "
  done < "${SECRETS_DIR}/wiki-secrets.env"
fi
G3=$(git grep -l -E 'BEGIN (EC |RSA )?PRIVATE KEY' || true)
IGN=$(git check-ignore -q .secrets/wiki-secrets.env && echo ignoré || echo NON-ignoré)
[[ -z "$G2" && -z "$G3" && "$IGN" == ignoré ]] && v=OK || v=KO
verdict R9 "git grep : aucun secret dans le dépôt" $v "valeurs réelles retrouvées : ${G2:-aucune} ; clés privées : ${G3:-aucune} ; .secrets/ ${IGN} ; lignes « password|app_key » restantes : $(wc -l <<<"${G1:-}" | tr -d ' ') (références à des Secrets, revues)"

# ------------------------------------------------------------------- R10 / R11
if [[ $COMPLET -eq 1 ]]; then
  api_token_delete
  OUT=$("${REPO_ROOT}/scripts/r10-disaster.sh" --yes 2>&1 | tail -3); echo "$OUT"
  [[ "$OUT" == *"R10 : contenus identiques"* ]] && v=OK || v=KO
  verdict R10 "Plateforme vidée, redéployée, restaurée" $v "$(grep -E '^durées' <<<"$OUT")"
  OUT=$("${REPO_ROOT}/scripts/upgrade.sh" "$UPGRADE_TAG" 2>&1); V1=$(grep 'version BookStack' <<<"$OUT")
  OUT2=$("${REPO_ROOT}/scripts/rollback.sh" 2>&1); V2=$(grep 'version BookStack' <<<"$OUT2")
  [[ "$OUT" == *"mise à jour en"* && "$OUT2" == *"retour arrière terminé"* ]] && v=OK || v=KO
  verdict R11 "Mise à jour de BookStack sans perte, puis retour arrière" $v "après mise à jour : ${V1#version BookStack : } ; après retour arrière : ${V2#version BookStack : } ($(grep -oE 'retour arrière terminé en [0-9]+ s' <<<"$OUT2"))"
else
  ROWS+=("| R10 | Plateforme vidée, redéployée, restaurée | — | non lancé (./scripts/recette.sh --complet ou ./scripts/r10-disaster.sh) |")
  ROWS+=("| R11 | Mise à jour sans perte puis retour arrière | — | non lancé (./scripts/upgrade.sh puis ./scripts/rollback.sh) |")
fi

# ------------------------------------------------------------------- R12
T=$(date +%s.%N)
"${REPO_ROOT}/scripts/status.sh" > "$TMP/status.txt" 2>&1 || true
DT=$(awk -v a="$T" -v b="$(date +%s.%N)" "BEGIN{printf \"%.1f\", b-a}")
grep -q '"database":true' "$TMP/status.txt" && (( ${DT%.*} < 60 )) && v=OK || v=KO
verdict R12 "État du service en moins d'une minute" $v "./scripts/status.sh en ${DT} s (pods, PVC, Ingress, kubectl top, /status, certificat, sauvegardes, journaux, événements)"

# ------------------------------------------------------------------- journal
{
  echo "# Journal de recette du $(date '+%d/%m/%Y %H:%M')"
  echo
  echo "Cluster : $(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}') · BookStack : $(k get deploy bookstack -o jsonpath='{.spec.template.spec.containers[0].image}') · MariaDB : ${IMG}"
  echo
  echo "| Test | Ce qu'on vérifie | Date | Résultat |"
  echo "|---|---|---|---|"
  printf '%s\n' "${ROWS[@]}"
  echo
  echo "**${PASS} OK, ${FAIL} KO.** Produit par \`./scripts/recette.sh$([[ $COMPLET -eq 1 ]] && echo ' --complet')\`."
} > "$JOURNAL"
echo; ok "${PASS} OK, ${FAIL} KO — journal : ${JOURNAL#$REPO_ROOT/}"
[[ $FAIL -eq 0 ]]
