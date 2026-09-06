# Contributing

Thank you for your interest in improving this repository.

The complete contribution workflow lives in [`docs/contributing.md`](docs/contributing.md). Read it before changing manifests, scripts, automation or operational documentation.

## Before opening a pull request

1. Read [`AGENTS.md`](AGENTS.md) and the ADRs relevant to the area being changed.
2. Follow the validation commands documented in [`docs/contributing.md`](docs/contributing.md).
3. Keep changes focused: one service, operational concern or architectural decision per pull request.
4. Never commit credentials, kubeconfig data, decrypted secrets, private infrastructure details or environment-specific access information.
5. Update the affected runbook, service matrix, architecture document or ADR when behavior or operational contracts change.

## Security-sensitive changes

Do not disclose suspected vulnerabilities or leaked credentials in a public issue or pull request. Follow [`SECURITY.md`](SECURITY.md) for private reporting and rotate any potentially exposed credential immediately.

## Project boundaries

This repository owns infrastructure and deployment contracts. Application code and container-image builds belong to their upstream repositories. Frontends are deployed outside the cluster, and secrets must remain encrypted or referenced through the documented secret-management workflow.
