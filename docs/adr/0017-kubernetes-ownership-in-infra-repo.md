# ADR 0017 - Kubernetes ownership lives in personal-platform-infra

**Date:** 2026-06-01
**Status:** Accepted

## Context

The platform is composed of multiple application repositories:

- `github-unified-mcp`
- `deploy-orchestrator-mcp`
- `mcp-social`
- `central-mcp-gateway`
- BFF and VOS services

Each application repository owns its source code, tests, Dockerfile and image
publishing pipeline. The `personal-platform-infra` repository owns the local and
VPS runtime that connects those applications into one platform.

The open design question is where Kubernetes manifests should live:

1. Each application repository owns its own `k8s/` manifests, and this infra
   repository only references them.
2. This infra repository owns the platform Kubernetes manifests, while
   application repositories publish images and document runtime contracts.

## Decision

Kubernetes manifests for the personal platform live in
`personal-platform-infra`.

Application repositories own:

- application source code;
- unit/integration tests for the application;
- Dockerfile and `.dockerignore`;
- GHCR image publishing;
- exposed ports;
- health/readiness endpoint contract;
- environment variable contract;
- application-level security defaults.

`personal-platform-infra` owns:

- Docker Compose wiring;
- Kubernetes namespaces, service accounts, Deployments, Services and overlays;
- shared secrets wiring;
- image selection for local and VPS runtimes;
- local k3d orchestration;
- VPS k3s deployment wiring;
- tunnels, public routing and DNS/TLS infrastructure;
- platform-level smoke tests and runbooks.

Application repositories may include lightweight deployment examples, but they
are not the source of truth for this platform's Kubernetes runtime.

## Consequences

- **Positive:** the platform can be started, smoked, exposed and deployed from a
  single repository.
- **Positive:** cross-service concerns such as namespaces, secrets, service
  accounts, tunnel routing and overlays stay visible in one place.
- **Positive:** app repositories remain focused on producing correct versioned
  images and stable runtime contracts.
- **Negative:** when an application changes its port, health path, image name or
  required environment variables, a matching infra change is required here.
- **Negative:** manifests are not automatically reusable by third parties that
  consume an application repository by itself.

## Operating Rule

Before changing Compose or Kubernetes wiring in this repository, verify the
application contract in the upstream repository:

- image name and tag;
- container port;
- health and readiness paths;
- required environment variables;
- authentication headers expected by the service;
- read/write safety mode.

Before changing an application repository in a way that affects runtime
contract, update this repository in the same delivery cycle.
