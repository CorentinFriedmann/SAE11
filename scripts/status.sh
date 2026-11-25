#!/usr/bin/env bash
# B13 / R12 : état du service en moins d'une minute.
source "$(dirname "$0")/lib.sh"
need kubectl curl

echo "== Pods, volumes, Ingress =="
k get pods,pvc,ingress -o wide
echo; echo "== Consommation (metrics-server) =="
k top pods 2>/dev/null || warn "kubectl top indisponible (metrics-server)"
echo; echo "== Santé applicative (https://${WIKI_HOST}/status) =="
wcurl -m 10 -w '  (HTTP %{http_code}, %{time_total}s)\n' "https://${WIKI_HOST}/status" || warn "wiki injoignable"
echo; echo "== Certificat =="
openssl s_client -connect "$(ingress_ip):443" -servername "$WIKI_HOST" </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -enddate 2>/dev/null || warn "certificat illisible"
echo; echo "== Dernières sauvegardes =="
k get jobs -l app=wiki-backup --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -4
echo; echo "== Journaux BookStack (10 dernières lignes) =="
k logs deploy/bookstack --tail=10 2>/dev/null || true
echo; echo "== Événements récents =="
k get events --sort-by=.lastTimestamp 2>/dev/null | tail -8
