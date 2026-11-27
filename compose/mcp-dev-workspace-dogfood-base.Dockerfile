# P1 disposable developer image, NOT the production workspace runtime.
# OCI multi-platform manifest digest verified 2026-11-27 via docker buildx imagetools inspect.
FROM maven:3.9.11-eclipse-temurin-25@sha256:407c4423cec0cf2981055bc2c6c0dc211d9605b6669279b95997f2d1c7e91e2c

RUN apt-get update \
    && apt-get install -y --no-install-recommends git python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Do not register host repositories as globally safe. The Java workspace
# implementation must apply bounded git -c safe.directory=<root> per command.
ENV HOME=/tmp MAVEN_CONFIG=/tmp/.m2
USER 10001:10001
WORKDIR /app
