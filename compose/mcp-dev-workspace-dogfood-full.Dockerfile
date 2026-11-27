# Local-only security candidate; never wired to production Compose.
ARG BASE_IMAGE=mcp-dev-workspace-dogfood:java25-python
FROM node:24-bookworm-slim@sha256:873f586f3794f52281bd039bf02c048a0be08fde619338f9941bad1eb6b34530 AS node
FROM ${BASE_IMAGE}
USER root
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && npm install -g --ignore-scripts --no-audit --no-fund npm@12.2.3 @fission-ai/openspec@2.1.0 \
    && npm cache clean --force
ENV HOME=/tmp MAVEN_CONFIG=/tmp/.m2 OPENSPEC_TELEMETRY=0
USER 10001:10001
WORKDIR /app
