#!/usr/bin/env bash
# ET9 / B2 à B7 : configuration de BookStack par son API, de façon reproductible et idempotente.
#   - rôles : Administrateur, Éditeur, Lecteur, Prestataire + un rôle « Accès client – X » par client
#   - double authentification (TOTP) obligatoire pour Administrateur, Prestataire et rôles d'accès client
#   - structure : étagères « Interne », « Procédures d'intervention », « Clients » ; un livre par client
#   - permissions par livre : un prestataire ne voit que les procédures et les clients qui lui sont attribués
#   - comptes nominatifs de démonstration (mots de passe aléatoires dans .secrets/comptes-demo.txt)
# Relançable : ce qui existe déjà n'est pas recréé.
source "$(dirname "$0")/lib.sh"
need kubectl jq openssl

ACCOUNTS_FILE="${SECRETS_DIR}/comptes-demo.txt"
api_token_create "init-bookstack"

# ------------------------------------------------------------------ utilitaires
check() {  # échoue si la réponse de l'API contient une erreur
  local r="$1"
  if jq -e '.error? // empty' >/dev/null 2>&1 <<<"$r"; then die "API : $(jq -c .error <<<"$r")"; fi
  echo "$r"
}
role_id()  { api GET "roles?count=500" | jq -r --arg n "$1" '.data[] | select(.display_name==$n) | .id' | head -1; }
book_id()  { api GET "books?count=500" | jq -r --arg n "$1" '.data[] | select(.name==$n) | .id' | head -1; }
shelf_id() { api GET "shelves?count=500" | jq -r --arg n "$1" '.data[] | select(.name==$n) | .id' | head -1; }
user_id()  { api GET "users?count=500" | jq -r --arg e "$1" '.data[] | select(.email==$e) | .id' | head -1; }
randpw()   { openssl rand -base64 18 | tr -d '/+=' | cut -c1-20; }

ensure_role() {  # nom description mfa(true/false) permissions-json [ancien nom à renommer]
  local name="$1" desc="$2" mfa="$3" perms="$4" old="${5:-}" id body
  id=$(role_id "$name")
  [[ -z "$id" && -n "$old" ]] && id=$(role_id "$old")
  body=$(jq -n --arg n "$name" --arg d "$desc" --argjson m "$mfa" --argjson p "$perms" \
    '{display_name:$n, description:$d, mfa_enforced:$m, permissions:$p}')
  if [[ -z "$id" ]]; then
    id=$(check "$(api POST roles "$body")" | jq -r .id)
    echo "  + rôle créé : $name (#$id)" >&2
  else
    check "$(api PUT "roles/$id" "$body")" >/dev/null
    echo "  = rôle à jour : $name (#$id)" >&2
  fi
  echo "$id"
}

ensure_book() {  # nom description -> id
  local id
  id=$(book_id "$1")
  if [[ -z "$id" ]]; then
    id=$(check "$(api POST books "$(jq -n --arg n "$1" --arg d "$2" '{name:$n, description:$d}')")" | jq -r .id)
    echo "  + livre : $1 (#$id)" >&2
  fi
  echo "$id"
}

ensure_page() {  # book_id titre markdown
  local exists
  exists=$(api GET "books/$1" | jq -r --arg n "$2" '[.contents[]? | select(.type=="page" and .name==$n)] | length')
  if [[ "$exists" == "0" ]]; then
    check "$(api POST pages "$(jq -n --argjson b "$1" --arg n "$2" --arg m "$3" '{book_id:$b, name:$n, markdown:$m}')")" >/dev/null
    echo "  + page : $2" >&2
  fi
}

ensure_shelf() {  # nom description books-json
  local id body
  id=$(shelf_id "$1")
  body=$(jq -n --arg n "$1" --arg d "$2" --argjson b "$3" '{name:$n, description:$d, books:$b}')
  if [[ -z "$id" ]]; then
    id=$(check "$(api POST shelves "$body")" | jq -r .id)
    echo "  + étagère : $1 (#$id)" >&2
  else
    check "$(api PUT "shelves/$id" "$body")" >/dev/null
  fi
  echo "$id"
}

# permissions type id role_permissions-json : les rôles non listés gardent leurs droits de rôle
set_perms() {
  local body
  body=$(jq -n --argjson rp "$3" '{role_permissions:$rp, fallback_permissions:{inheriting:true}}')
  check "$(api PUT "content-permissions/$1/$2" "$body")" >/dev/null
}
view_only() { jq -n --argjson r "$1" '{role_id:$r, view:true, create:false, update:false, delete:false}'; }
deny()      { jq -n --argjson r "$1" '{role_id:$r, view:false, create:false, update:false, delete:false}'; }

ensure_user() {  # nom email roles-json
  local name="$1" email="$2" roles="$3" id pw
  id=$(user_id "$email")
  if [[ -z "$id" ]]; then
    pw=$(randpw)
    check "$(api POST users "$(jq -n --arg n "$name" --arg e "$email" --arg p "$pw" --argjson r "$roles" \
      '{name:$n, email:$e, password:$p, roles:$r, send_invite:false, language:"fr"}')")" >/dev/null
    printf '%-38s %-22s %s\n' "$email" "$pw" "$name" >> "$ACCOUNTS_FILE"
    echo "  + compte : $email" >&2
  else
    check "$(api PUT "users/$id" "$(jq -n --argjson r "$roles" '{roles:$r}')")" >/dev/null
  fi
}

# ------------------------------------------------------------------ 1. rôles
info "rôles et double authentification"
VIEW_PERMS='["book-view-all","bookshelf-view-all","chapter-view-all","page-view-all","revision-view-all","content-export"]'
EDIT_PERMS=$(api GET "roles/$(role_id Editor)$(role_id Éditeur)" | jq -c '.permissions + ["attachment-create-all","attachment-update-all","attachment-delete-all","comment-create-all","comment-update-own","comment-delete-own","templates-manage"] | unique')
ADMIN_PERMS=$(api GET "roles/$(api GET 'roles?count=500' | jq -r '.data[]|select(.system_name=="admin")|.id')" | jq -c '.permissions')

ROLE_ADMIN=$(ensure_role "Administrateur" "Direction infrastructure : tout, dont comptes, rôles et journal d'audit. TOTP obligatoire." true "$ADMIN_PERMS" "Admin")
ROLE_EDIT=$(ensure_role "Éditeur" "Techniciens Rhénatech : créer et modifier pages internes et procédures." false "$EDIT_PERMS" "Editor")
ROLE_READ=$(ensure_role "Lecteur" "Autres salariés : lire et chercher." false "$VIEW_PERMS" "Viewer")
# Prestataire : AUCUNE permission de rôle. Il ne voit que ce qui lui est ouvert livre par livre.
ROLE_PRESTA=$(ensure_role "Prestataire" "Techniciens sous-traitants : procédures d'intervention uniquement. TOTP obligatoire." true '[]')

declare -A CLIENTS=(
  ["Clinique des Tilleuls"]="Clinique (fictive) : réseau des urgences, 2 sites."
  ["Commune de Val-d'Ill"]="Collectivité (fictive) : mairie, école, médiathèque."
  ["Brasserie Lauch"]="PME (fictive) : production et entrepôt."
)
declare -A CLIENT_ROLE
for c in "${!CLIENTS[@]}"; do
  CLIENT_ROLE["$c"]=$(ensure_role "Accès client – $c" "Ouvre la fiche du client $c aux prestataires qui y interviennent." true '[]')
done

# Le rôle « Public » (visiteurs non connectés) ne voit rien : pas d'accès anonyme
check "$(api PUT "roles/$(api GET 'roles?count=500' | jq -r '.data[]|select(.system_name=="public")|.id')" '{"permissions":[]}')" >/dev/null

# ------------------------------------------------------------------ 2. contenu
info "étagères, livres et pages"
B_EXPLOIT=$(ensure_book "Exploitation du wiki" "Sauvegarde, restauration et mise à jour de la plateforme documentaire.")
B_RH=$(ensure_book "Ressources humaines" "Organisation interne. Réservé aux salariés.")
B_COM=$(ensure_book "Commercial" "Offres et tarifs. Réservé aux salariés.")
B_PROC=$(ensure_book "Procédures réseau" "Procédures d'intervention validées, utilisables par les prestataires d'astreinte.")

ensure_page "$B_EXPLOIT" "Restaurer le wiki" "$(cat <<'MD'
# Restaurer le wiki

**Quand ?** Perte de données, base corrompue, plateforme réinstallée. Objectif : service rendu en moins de 4 h (B11).

1. Repérer la sauvegarde à restaurer : `./scripts/restore.sh --list` (sauvegardes du PVC) ou le dossier exporté dans `backups/`.
2. Si la plateforme est vierge : `./scripts/deploy.sh --no-init` (les secrets d'origine de `.secrets/` sont réutilisés : **APP_KEY indispensable**).
3. Restaurer : `./scripts/restore.sh <AAAAMMJJ-HHMMSS>` ou `./scripts/restore.sh backups/<AAAAMMJJ-HHMMSS>`.
   Le script arrête BookStack, recharge la base et les fichiers, redémarre et affiche la durée.
4. Vérifier : `./scripts/status.sh`, connexion d'un compte, présence de la dernière page modifiée.
5. Noter l'incident et la durée mesurée dans le journal d'exploitation.
MD
)"
ensure_page "$B_EXPLOIT" "Sauvegardes et rétention" "$(cat <<'MD'
# Sauvegardes et rétention

- CronJob `wiki-backup` chaque nuit à 02:00 : `mariadb-dump --single-transaction` + archive des fichiers.
- 7 jours conservés sur le volume `wiki-backups`, copie hors cluster par `./scripts/backup-export.sh`.
- Sauvegarde manuelle avant toute mise à jour : `./scripts/backup-now.sh`.
- Journal d'audit purgé au-delà de 365 jours (CronJob `wiki-audit-purge`, RGPD).
MD
)"
ensure_page "$B_RH" "Organisation des astreintes" "$(cat <<'MD'
# Organisation des astreintes

Astreinte de nuit (19 h – 7 h) et de week-end assurée par les techniciens prestataires, sous la responsabilité
du cadre d'astreinte Rhénatech. Les plannings nominatifs sont tenus dans l'outil RH, **pas dans le wiki**.
MD
)"
ensure_page "$B_COM" "Grille tarifaire 2027" "$(cat <<'MD'
# Grille tarifaire 2027 (fictive)

| Prestation | Tarif HT |
|---|---|
| Intervention de nuit (forfait) | 350 € |
| Heure supplémentaire | 95 € |

*Information confidentielle : jamais visible des prestataires (B3).*
MD
)"
ensure_page "$B_PROC" "Redémarrer un commutateur cœur de réseau" "$(cat <<'MD'
# Redémarrer un commutateur cœur de réseau

**Prérequis :** accord du cadre d'astreinte, fiche client consultée, fenêtre validée.

1. Vérifier dans la fiche client que la redondance (second cœur) est opérationnelle.
2. Sauvegarder la configuration courante : `copy running-config startup-config`.
3. Prévenir le contact client d'astreinte (numéro dans la fiche client).
4. Redémarrer : `reload`, puis vérifier le retour des liens agrégés (LACP) et du routage.
5. Consigner l'heure de début et de fin dans le ticket.
MD
)"
ensure_page "$B_PROC" "Basculer sur le lien WAN de secours" "$(cat <<'MD'
# Basculer sur le lien WAN de secours

1. Constater la perte du lien principal (supervision, ping de la passerelle opérateur).
2. Forcer la route par défaut vers le routeur de secours (procédure propre au client : voir sa fiche).
3. Tester l'accès aux applications métier listées dans la fiche client.
4. Ouvrir un ticket opérateur, rebasculer au retour du lien principal.
MD
)"

declare -A CLIENT_BOOK
for c in "${!CLIENTS[@]}"; do
  CLIENT_BOOK["$c"]=$(ensure_book "Client – $c" "${CLIENTS[$c]}")
  ensure_page "${CLIENT_BOOK[$c]}" "Fiche client" "$(cat <<MD
# Fiche client – $c

*Client fictif : aucune donnée réelle (B12).*

| Rubrique | Valeur |
|---|---|
| Contact d'astreinte | standard du client (voir contrat) |
| Équipements critiques | cœur de réseau redondé, pare-feu, lien WAN de secours |
| Particularités | ${CLIENTS[$c]} |
| Procédures applicables | Procédures réseau |
MD
)"
done

CLIENT_BOOKS_JSON=$(for c in "${!CLIENTS[@]}"; do echo "${CLIENT_BOOK[$c]}"; done | jq -sc '.')
S_INT=$(ensure_shelf "Interne" "Documentation réservée aux salariés de Rhénatech." "[$B_EXPLOIT,$B_RH,$B_COM]")
S_PROC=$(ensure_shelf "Procédures d'intervention" "Procédures validées, visibles des prestataires." "[$B_PROC]")
S_CLI=$(ensure_shelf "Clients" "Un livre par client. Chaque prestataire ne voit que ses clients." "$CLIENT_BOOKS_JSON")

# ------------------------------------------------------------------ 3. cloisonnement
info "permissions : cloisonnement des prestataires"
ALL_PRESTA_ROLES=$( { echo "$ROLE_PRESTA"; for c in "${!CLIENTS[@]}"; do echo "${CLIENT_ROLE[$c]}"; done; } | jq -sc '.')
# Interne : refus explicite à tous les rôles prestataires (défense en profondeur, en plus de l'absence de droits de rôle)
DENY_ALL=$(jq -c '[.[] | {role_id:., view:false, create:false, update:false, delete:false}]' <<<"$ALL_PRESTA_ROLES")
for b in "$B_EXPLOIT" "$B_RH" "$B_COM"; do set_perms book "$b" "$DENY_ALL"; done
set_perms bookshelf "$S_INT" "$DENY_ALL"
# Procédures : lecture seule pour le rôle Prestataire
set_perms book "$B_PROC" "[$(view_only "$ROLE_PRESTA")]"
set_perms bookshelf "$S_PROC" "[$(view_only "$ROLE_PRESTA")]"
# Clients : l'étagère est visible des prestataires, chaque livre seulement du rôle d'accès du client
set_perms bookshelf "$S_CLI" "[$(view_only "$ROLE_PRESTA")]"
for c in "${!CLIENTS[@]}"; do
  set_perms book "${CLIENT_BOOK[$c]}" "[$(view_only "${CLIENT_ROLE[$c]}")]"
  echo "  livre « Client – $c » : visible du rôle « Accès client – $c » uniquement (côté prestataires)" >&2
done

# ------------------------------------------------------------------ 4. comptes nominatifs (B4)
info "comptes de démonstration"
if [[ ! -f "$ACCOUNTS_FILE" ]]; then
  umask 077
  echo "# Comptes de démonstration – NE PAS VERSIONNER – générés le $(date '+%F %T')" > "$ACCOUNTS_FILE"
fi
# L'administrateur par défaut (admin@admin.com / password) est renommé et reçoit un mot de passe aléatoire
DEFAULT_ADMIN=$(user_id "admin@admin.com")
if [[ -n "$DEFAULT_ADMIN" ]]; then
  pw=$(randpw)
  check "$(api PUT "users/$DEFAULT_ADMIN" "$(jq -n --arg p "$pw" --argjson r "[$ROLE_ADMIN]" \
    '{name:"Administrateur technique", email:"admin@rhenatech.lab", password:$p, roles:$r}')")" >/dev/null
  printf '%-38s %-22s %s\n' "admin@rhenatech.lab" "$pw" "Administrateur technique (ex admin@admin.com)" >> "$ACCOUNTS_FILE"
  echo "  ~ compte par défaut admin@admin.com sécurisé -> admin@rhenatech.lab" >&2
fi
ensure_user "Claire Fischer (démo)" "claire.fischer@rhenatech.lab" "[$ROLE_ADMIN]"
ensure_user "Technicien Éditeur (démo)" "editeur@rhenatech.lab" "[$ROLE_EDIT]"
ensure_user "Salarié Lecteur (démo)" "lecteur@rhenatech.lab" "[$ROLE_READ]"
ensure_user "Prestataire Alpha (démo)" "tech1@alpha-reseaux.example" "[$ROLE_PRESTA, ${CLIENT_ROLE["Clinique des Tilleuls"]}]"
ensure_user "Prestataire Beta (démo)" "tech1@beta-systemes.example" "[$ROLE_PRESTA, ${CLIENT_ROLE["Commune de Val-d'Ill"]}, ${CLIENT_ROLE["Brasserie Lauch"]}]"

# Paramètres généraux : nom de l'application, inscription publique fermée
sql <<'SQL'
INSERT INTO settings (setting_key, value, type, created_at, updated_at) VALUES
  ('app-name', 'Wiki Rhénatech', 'string', NOW(), NOW()),
  ('registration-enabled', 'false', 'string', NOW(), NOW()),
  ('app-public', 'false', 'string', NOW(), NOW())
ON DUPLICATE KEY UPDATE value=VALUES(value), updated_at=NOW();
SQL
k exec "$(bookstack_pod)" -c bookstack -- php /app/www/artisan cache:clear >/dev/null 2>&1 || true

ok "BookStack configuré. Comptes : ${ACCOUNTS_FILE}"
