# P1 disposable developer image, NOT the production workspace runtime.
# Review/pin base image digest and scan before any promotion.
FROM maven:3.9.11-eclipse-temurin-25

RUN apt-get update \
    && apt-get install -y --no-install-recommends git python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Do not register host repositories as globally safe. The Java workspace
# implementation must apply bounded git -c safe.directory=<root> per command.
ENV HOME=/tmp MAVEN_CONFIG=/tmp/.m2
USER 10001:10001
WORKDIR /app
