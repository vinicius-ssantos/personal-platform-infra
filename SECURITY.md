# Security Policy

This repository contains infrastructure definitions, deployment automation and operational documentation for a personal platform. It is a public portfolio project, not a hosted service offered to third parties.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability involving:

- credentials, tokens, certificates, kubeconfig data or encrypted-secret handling;
- DNS, tunnels, ingress, access-control or authentication configuration;
- GitHub Actions, deployment automation or supply-chain integrity;
- infrastructure manifests, scripts or operational procedures that could expose a running environment.

Use GitHub private vulnerability reporting when it is available for this repository. Otherwise, send a private report to `viniciusoli2020@gmail.com` with the subject `Security report: personal-platform-infra`.

Include only the minimum information required to reproduce and assess the issue:

- affected path or component;
- impact and expected behavior;
- safe reproduction steps;
- suggested mitigation, when available.

Never include a live secret in the report. If a real credential may have been exposed, revoke or rotate it immediately before continuing the investigation.

## Supported scope

Security reports are accepted for the current `main` branch. Relevant areas include:

- Kubernetes, Docker Compose, Terraform and Ansible definitions;
- SOPS/age secret-management workflows;
- Cloudflare, ingress and access-control configuration;
- CI/CD workflows and deployment scripts;
- repository sandbox and AI-assisted automation boundaries.

Vulnerabilities in upstream applications or third-party services should be reported to their respective maintainers unless this repository introduces the unsafe configuration.

## Disclosure

Please allow time for validation and remediation before publishing details. Confirmed issues may result in configuration changes, credential rotation, documentation updates and a public advisory when disclosure is appropriate.
