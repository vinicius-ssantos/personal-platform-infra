set dotenv-load := true
set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]

bootstrap-local:
	ansible-playbook -i ansible/inventory/local.ini ansible/playbooks/bootstrap-wsl.yml

bootstrap-vps:
	ansible-playbook -i ansible/inventory/vps.ini ansible/playbooks/bootstrap-vps.yml

terraform-init:
	cd terraform/cloudflare && terraform init

terraform-plan:
	cd terraform/cloudflare && terraform plan

terraform-apply:
	cd terraform/cloudflare && terraform apply

terraform-vps-init:
	cd terraform/vps && terraform init

terraform-vps-plan:
	cd terraform/vps && terraform plan

terraform-vps-apply:
	cd terraform/vps && terraform apply

status-page-init:
	bash scripts/status-page-config.sh init

status-page-check:
	bash scripts/status-page-config.sh check

status-page-dev: status-page-check
	npx wrangler dev --config cloudflare/workers/status-page/wrangler.toml

status-page-deploy: status-page-check
	npx wrangler deploy --config cloudflare/workers/status-page/wrangler.toml

env-init:
	bash scripts/env-init.sh

check-env:
	bash scripts/check-env.sh

compose-up: check-env
	docker compose -f compose/docker-compose.yml --env-file .env --profile all up -d --wait

compose-down:
	docker compose -f compose/docker-compose.yml --env-file .env --profile all down

compose-logs:
	docker compose -f compose/docker-compose.yml --env-file .env --profile all logs -f --tail=200

smoke-github:
	powershell.exe -ExecutionPolicy Bypass -File scripts/smoke-github-unified-mcp.ps1

smoke-deploy:
	powershell.exe -ExecutionPolicy Bypass -File scripts/smoke-deploy-orchestrator-mcp.ps1

smoke-social:
	powershell.exe -ExecutionPolicy Bypass -File scripts/smoke-mcp-social.ps1

smoke-github-bff:
	powershell.exe -ExecutionPolicy Bypass -File scripts/smoke-github-unified-mcp-bff.ps1

smoke-vos:
	powershell.exe -ExecutionPolicy Bypass -File scripts/smoke-vos.ps1

smoke-all:
	just smoke-github
	just smoke-deploy
	just smoke-social
	just smoke-github-bff
	just smoke-vos

smoke-github-sh:
	bash scripts/smoke-github-unified-mcp.sh

smoke-deploy-sh:
	bash scripts/smoke-deploy-orchestrator-mcp.sh

smoke-social-sh:
	bash scripts/smoke-mcp-social.sh

smoke-github-bff-sh:
	bash scripts/smoke-github-unified-mcp-bff.sh

smoke-vos-sh:
	bash scripts/smoke-vos.sh

smoke-all-sh:
	just smoke-github-sh
	just smoke-deploy-sh
	just smoke-social-sh
	just smoke-github-bff-sh
	just smoke-vos-sh

smoke-k3d:
	bash scripts/smoke-k3d.sh

smoke-logs:
	bash scripts/smoke-logs.sh

k8s-local-up:
	k3d cluster create personal-platform --config k8s/overlays/local/k3d-config.yaml || true
	kubectl apply -k k8s/overlays/local
	@echo ""
	@echo "Cluster ready. Run 'just k3d-secrets' to inject real API tokens from .env."

k3d-secrets:
	bash scripts/k3d-secrets.sh

k8s-local-down:
	k3d cluster delete personal-platform

k8s-vps-apply:
	kubectl apply -k k8s/overlays/vps

tunnel:
	./scripts/tunnel.sh

wake-github:
	./scripts/wake-github.sh

wake-vos:
	./scripts/wake-vos.sh

wake-deploy:
	./scripts/wake-deploy.sh

wake-social:
	./scripts/wake-social.sh

wake-all:
	./scripts/wake-all.sh

sleep-all:
	./scripts/sleep-all.sh

logs target="all":
	./scripts/logs.sh {{target}}

logs-ui:
	kubectl port-forward svc/grafana 3000:3000 -n monitoring

grafana-secret:
	bash scripts/create-grafana-admin-secret.sh

clean:
	bash scripts/clean-local.sh

clean-compose:
	docker compose -f compose/docker-compose.yml --env-file .env --profile all down -v

clean-k3d:
	k3d cluster delete personal-platform

secrets-check:
	bash scripts/secrets-check.sh

secrets-edit-local: secrets-check
	SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.age/personal-platform.txt}" sops secrets/local.enc.yaml

secrets-edit-vps: secrets-check
	SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.age/personal-platform.txt}" sops secrets/vps.enc.yaml

status:
	bash scripts/status.sh

status-public:
	bash scripts/status-public.sh

hooks-install:
	pre-commit install

k3s-upgrade:
	bash scripts/k3s-upgrade.sh

keda-http-install:
	bash scripts/keda-http-install.sh

smoke-keda-http:
	bash scripts/smoke-keda-http.sh

create-ghcr-secret:
	bash scripts/create-ghcr-pull-secret.sh

secrets-backup:
	@echo "=== age public key ==="
	@grep "^# public key:" ~/.age/personal-platform.txt 2>/dev/null || age-keygen -y ~/.age/personal-platform.txt 2>/dev/null || echo "(key not found at ~/.age/personal-platform.txt)"
	@echo ""
	@echo "Back up the PRIVATE key at: ~/.age/personal-platform.txt"
	@echo "See docs/secrets.md for backup options."
