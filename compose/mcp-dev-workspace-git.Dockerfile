# Local Java 25 MCP workspace runtime with Git for bounded repository inspection.
# Digest matches the reviewed Eclipse Temurin 25 JRE base used in the local probe.
FROM eclipse-temurin:25-jre@sha256:bb036ed6cfdc57e3da7c22634d15f1b840d2caf76183861c80e81ca4b5104abb

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

USER 10001:10001
WORKDIR /app
