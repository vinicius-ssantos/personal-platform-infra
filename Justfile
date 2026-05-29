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

compose-up:
	docker compose -f compose/docker-compose.yml --env-file .env up -d

compose-down:
	docker compose -f compose/docker-compose.yml --env-file .env down

compose-logs:
	docker compose -f compose/docker-compose.yml --env-file .env logs -f --tail=200

smoke-github:
	powershell.exe -ExecutionPolicy Bypass -File scripts/smoke-github-unified-mcp.ps1

k8s-local-up:
	k3d cluster create personal-platform --config k8s/overlays/local/k3d-config.yaml || true
	kubectl apply -k k8s/overlays/local

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

sleep-all:
	./scripts/sleep-all.sh

logs:
	./scripts/logs.sh
