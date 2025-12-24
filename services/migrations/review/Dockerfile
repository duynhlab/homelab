# Flyway Migration Image for Review Service
FROM alpine:3.19

# Install Java and required tools
RUN apk add --no-cache \
    bash \
    openjdk17 \
    wget \
    tar \
    && rm -rf /var/cache/apk/*

# Install Flyway from GitHub releases
ENV FLYWAY_VERSION=11.19.0
RUN wget -qO- https://github.com/flyway/flyway/releases/download/flyway-${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz | tar -xvz \
    && mv flyway-${FLYWAY_VERSION} /opt/flyway \
    && ln -s /opt/flyway/flyway /usr/local/bin/flyway \
    && rm -rf /tmp/*

RUN mkdir -p /flyway/sql
COPY sql/ /flyway/sql/
WORKDIR /flyway
CMD ["flyway", "migrate"]
