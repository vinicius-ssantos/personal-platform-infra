# Local-only candidate. The Java/Python stage is built from the matching
# reviewed base Dockerfile; this file does not change Compose or production.
# Pin upstream image digests and complete vulnerability review before merge.
FROM node:24-bookworm-slim AS node
FROM mcp-dev-workspace-dogfood:java25-python

USER root
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && npm install -g --ignore-scripts --no-audit --no-fund @fission-ai/openspec@2.1.0 \
    && npm cache clean --force

ENV HOME=/tmp MAVEN_CONFIG=/tmp/.m2 OPENSPEC_TELEMETRY=0
USER 10001:10001
WORKDIR /app
