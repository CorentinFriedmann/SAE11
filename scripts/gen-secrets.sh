#!/usr/bin/env bash
# ET4 : génère (une seule fois) les secrets du wiki dans .secrets/ (ignoré par Git).
#  - APP_KEY : chiffre sessions et secrets TOTP en base. À NE JAMAIS PERDRE NI CHANGER :
#              perdue = tous les utilisateurs doivent ré-enrôler leur TOTP.
#  - mots de passe MariaDB (applicatif et root)
#  - autorité de certification interne + certificat serveur wiki.rhenatech.lab (RFC 5280)
# Relancer le script ne régénère rien d'existant (idempotent).
source "$(dirname "$0")/lib.sh"
need openssl

mkdir -p "${SECRETS_DIR}/tls"
chmod 700 "${SECRETS_DIR}"

ENV_FILE="${SECRETS_DIR}/wiki-secrets.env"
if [[ -f "$ENV_FILE" ]]; then
  ok "secrets applicatifs déjà présents : ${ENV_FILE}"
else
  umask 077
  {
    echo "APP_KEY=base64:$(openssl rand -base64 32)"
    echo "DB_PASSWORD=$(openssl rand -hex 24)"
    echo "MARIADB_ROOT_PASSWORD=$(openssl rand -hex 24)"
  } > "$ENV_FILE"
  ok "secrets applicatifs générés : ${ENV_FILE} (à sauvegarder hors ligne, ex. coffre KeePass)"
fi

TLS="${SECRETS_DIR}/tls"
if [[ -f "${TLS}/tls.crt" && -f "${TLS}/tls.key" ]]; then
  ok "certificat TLS déjà présent : ${TLS}/tls.crt"
else
  umask 077
  # Autorité interne (10 ans), clé ECDSA P-256
  if [[ ! -f "${TLS}/ca.key" ]]; then
    openssl ecparam -name prime256v1 -genkey -noout -out "${TLS}/ca.key"
    openssl req -x509 -new -key "${TLS}/ca.key" -sha256 -days 3650 \
      -subj "/O=Rhenatech/OU=Infrastructure/CN=Rhenatech Lab Root CA" \
      -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
      -addext "keyUsage=critical,keyCertSign,cRLSign" \
      -out "${TLS}/ca.crt"
  fi
  # Certificat serveur (397 jours, limite des navigateurs), SAN obligatoire
  openssl ecparam -name prime256v1 -genkey -noout -out "${TLS}/tls.key"
  openssl req -new -key "${TLS}/tls.key" -subj "/O=Rhenatech/CN=${WIKI_HOST}" -out "${TLS}/tls.csr"
  cat > "${TLS}/ext.cnf" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=DNS:${WIKI_HOST}
EOF
  openssl x509 -req -in "${TLS}/tls.csr" -CA "${TLS}/ca.crt" -CAkey "${TLS}/ca.key" -CAcreateserial \
    -days 397 -sha256 -extfile "${TLS}/ext.cnf" -out "${TLS}/tls.crt"
  rm -f "${TLS}/tls.csr" "${TLS}/ext.cnf"
  chmod 644 "${TLS}/ca.crt" "${TLS}/tls.crt"
  ok "autorité interne : ${TLS}/ca.crt (à importer dans les navigateurs / postes)"
  ok "certificat serveur : ${TLS}/tls.crt"
fi
