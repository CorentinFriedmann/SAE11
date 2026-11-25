#!/usr/bin/with-contenv bash
# Script d'initialisation personnalisé de l'image linuxserver (/custom-cont-init.d),
# exécuté en root à chaque démarrage, avant nginx et php-fpm.
# 1) B8 : copie la surcharge PHP (limites de téléversement) depuis la ConfigMap.
#    On copie plutôt que monter en subPath dans /config : un fichier en lecture
#    seule dans /config fait échouer la remise des droits de l'image.
# 2) Si le noyau n'a pas IPv6 (VM avec ipv6.disable=1), nginx refuse de démarrer
#    sur "listen [::]:80" : on retire alors l'écoute IPv6.
set -e
install -o abc -g abc -m 0644 /rhenatech/php-local.ini /config/php/php-local.ini
echo "[rhenatech] php-local.ini installé"
if [ ! -f /proc/net/if_inet6 ]; then
  for f in /config/nginx/site-confs/*.conf; do
    [ -f "$f" ] && sed -i '/listen \[::\]/d' "$f"
  done
  echo "[rhenatech] IPv6 absent : écoute IPv6 de nginx désactivée"
fi
