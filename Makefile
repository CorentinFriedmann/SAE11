# Raccourcis : make deploy | status | backup | recette | recette-complete | destroy
.PHONY: deploy status backup export recette recette-complete upgrade rollback destroy lint

deploy:            ; ./scripts/deploy.sh
status:            ; ./scripts/status.sh
backup:            ; ./scripts/backup-now.sh
export:            ; ./scripts/backup-export.sh
recette:           ; ./scripts/recette.sh
recette-complete:  ; ./scripts/recette.sh --complet
upgrade:           ; ./scripts/upgrade.sh $(TAG)
rollback:          ; ./scripts/rollback.sh
destroy:           ; ./scripts/destroy.sh

# Validation statique des manifestes (sans cluster) et des scripts
lint:
	kubectl kustomize k8s > /dev/null && echo "kustomize OK"
	bash -n scripts/*.sh && echo "scripts OK"
	@! git grep -n -I -E 'BEGIN (EC |RSA )?PRIVATE KEY' && echo "aucune clé privée versionnée"
