#!/usr/bin/env bash
# B4 : fin de contrat d'un prestataire. BookStack n'a pas d'interrupteur « compte désactivé » :
#   1. retrait de TOUS les rôles  -> plus aucun contenu visible, effet immédiat même sur une session ouverte
#   2. mot de passe remplacé par une valeur aléatoire jamais communiquée -> plus de connexion possible
#   3. jetons d'API et facteurs MFA supprimés, sessions en base purgées
#   4. nom préfixé [DÉSACTIVÉ] : le compte reste dans le journal d'audit (traçabilité, B6)
#   ./scripts/disable-user.sh tech1@alpha-reseaux.example
source "$(dirname "$0")/lib.sh"
need kubectl jq openssl

EMAIL="${1:?usage : $0 <courriel>}"
api_token_create "disable-user"
ID=$(api GET "users?count=500" | jq -r --arg e "$EMAIL" '.data[] | select(.email==$e) | .id')
[[ -n "$ID" ]] || die "compte introuvable : $EMAIL"
NAME=$(api GET "users/$ID" | jq -r .name)
[[ "$NAME" == "[DÉSACTIVÉ]"* ]] || NAME="[DÉSACTIVÉ] ${NAME}"
BODY=$(jq -n --arg n "$NAME" --arg p "$(openssl rand -base64 48)" '{name:$n, password:$p, roles:[]}')
api PUT "users/$ID" "$BODY" | jq -e '.id' >/dev/null || die "échec de la mise à jour"
sql <<SQL
DELETE FROM api_tokens WHERE user_id=${ID};
DELETE FROM mfa_values WHERE user_id=${ID};
DELETE FROM sessions WHERE user_id=${ID};
SQL
ok "compte ${EMAIL} (#${ID}) désactivé le $(date '+%F %T') : rôles retirés, mot de passe invalidé, MFA et sessions supprimés"
