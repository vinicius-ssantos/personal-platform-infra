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

check-policy:
	bash scripts/check-policy.sh

compose-up: check-env
	just compose-up-profile all

compose-down:
	just compose-down-profile all

compose-logs:
	just compose-logs-profile all

compose-up-profile profile="all": check-env
	docker compose -f compose/docker-compose.yml --env-file .env --profile {{profile}} up -d --wait

compose-down-profile profile="all":
	docker compose -f compose/docker-compose.yml --env-file .env --profile {{profile}} down

compose-logs-profile profile="all":
	docker compose -f compose/docker-compose.yml --env-file .env --profile {{profile}} logs -f --tail=200

quick-tunnel-up:
	powershell.exe -ExecutionPolicy Bypass -File scripts/quick-tunnel-up.ps1

quick-tunnel-refresh:
	powershell.exe -ExecutionPolicy Bypass -File scripts/quick-tunnel-up.ps1 -ForceRefresh

quick-tunnel-down:
	powershell.exe -ExecutionPolicy Bypass -File scripts/quick-tunnel-down.ps1

ngrok-up:
	powershell.exe -ExecutionPolicy Bypass -File scripts/ngrok-up.ps1

ngrok-down:
	powershell.exe -ExecutionPolicy Bypass -File scripts/ngrok-down.ps1

tailscale-funnel-up:
	powershell.exe -ExecutionPolicy Bypass -File scripts/tailscale-funnel-up.ps1

tailscale-funnel-down:
	powershell.exe -ExecutionPolicy Bypass -File scripts/tailscale-funnel-down.ps1

k3d-ngrok-up:
	powershell.exe -ExecutionPolicy Bypass -File scripts/k3d-ngrok-up.ps1

k3d-ngrok-down:
	powershell.exe -ExecutionPolicy Bypass -File scripts/k3d-ngrok-down.ps1

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

smoke-gateway:
	powershell.exe -ExecutionPolicy Bypass -File scripts/smoke-central-mcp-gateway.ps1

smoke-all:
	just smoke-github
	just smoke-deploy
	just smoke-social
	just smoke-github-bff
	just smoke-vos
	just smoke-gateway

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

smoke-gateway-sh:
	bash scripts/smoke-central-mcp-gateway.sh

smoke-all-sh:
	just smoke-github-sh
	just smoke-deploy-sh
	just smoke-social-sh
	just smoke-github-bff-sh
	just smoke-vos-sh
	just smoke-gateway-sh

smoke-k3d:
	bash scripts/smoke-k3d.sh

smoke-logs:
	bash scripts/smoke-logs.sh

k8s-local-up:
	powershell.exe -ExecutionPolicy Bypass -File scripts/k8s-local-up.ps1

k3d-secrets:
	bash scripts/k3d-secrets.sh

k8s-local-down:
	k3d cluster delete personal-platform

render-vps:
	bash scripts/render-vps-overlay.sh

k8s-vps-apply:
	bash scripts/render-vps-overlay.sh | kubectl apply -f -

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

secrets-edit-vps-k8s: secrets-check
	SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.age/personal-platform.txt}" sops secrets/platform-secrets-vps.enc.yaml

k8s-vps-secrets:
	bash scripts/apply-vps-secrets.sh

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
