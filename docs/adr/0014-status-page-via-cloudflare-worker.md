# ADR 0014: Status page via Cloudflare Worker

## Status

Accepted

## Context

Operators need a browser-accessible view of service health without SSH access or
manual `kubectl` commands. The current ready services already expose simple
HTTP health endpoints through Cloudflare-managed hostnames.

## Decision

Use a Cloudflare Worker for the first status page. The Worker probes health
endpoints server-side and returns both HTML and JSON responses.

## Consequences

- The status page can run outside the VPS and still report whether public
  service routes are reachable.
- Cloudflare Access should protect the page before public exposure.
- The Worker does not wake scale-to-zero services yet; automatic wake remains a
  separate decision.
