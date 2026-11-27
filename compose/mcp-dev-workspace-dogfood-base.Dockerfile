# P1 isolated local-only candidate; Maven vendor and JDK are separate verified OCI bases.
FROM maven:3.9.14-eclipse-temurin-25@sha256:304ea1e9675d07612c36d5d70d8bd1dbd8aac64c307253bbde4e488857f90faa AS maven
FROM eclipse-temurin:25-jdk-noble@sha256:4ddc1a8bdaf283421df5487411aff10b797ccf1e06a339041005114c8f489b5c
COPY --from=maven /usr/share/maven /usr/share/maven
ENV MAVEN_HOME=/usr/share/maven PATH="/usr/share/maven/bin:${PATH}"
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends git python3 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
# Maven's 3.9.14 bundle includes known HIGH CVEs; replace only the two affected
# compatible libraries and verify upstream artifact SHA-256 before installation.
RUN curl -fsSL --retry 3 -o /tmp/plexus-utils-3.6.1.jar 'https://repo.maven.apache.org/maven2/org/codehaus/plexus/plexus-utils/3.6.1/plexus-utils-3.6.1.jar' \
    && curl -fsSL --retry 3 -o /tmp/guava-33.7.2-jre.jar 'https://repo.maven.apache.org/maven2/com/google/guava/guava/33.7.2-jre/guava-33.7.2-jre.jar' \
    && echo '05a63effd67e2d6b9d610cc82e2bd7473289d34802e57a529b28110f28af5679  /tmp/plexus-utils-3.6.1.jar' | sha256sum -c - \
    && echo 'b530942257fb935f8b2cfaa5f8eb5bd59c555fd8e8d01b8ce98912e077ea606c  /tmp/guava-33.7.2-jre.jar' | sha256sum -c - \
    && rm /usr/share/maven/lib/plexus-utils-3.6.0.jar /usr/share/maven/lib/guava-33.5.0-jre.jar \
    && mv /tmp/plexus-utils-3.6.1.jar /usr/share/maven/lib/ \
    && mv /tmp/guava-33.7.2-jre.jar /usr/share/maven/lib/
# Never register arbitrary global Git safe.directory exceptions.
ENV HOME=/tmp MAVEN_CONFIG=/tmp/.m2
USER 10001:10001
WORKDIR /app
