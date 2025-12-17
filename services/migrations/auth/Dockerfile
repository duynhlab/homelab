# Flyway Migration Image for Auth Service
# Uses Alpine + apk add flyway (simplest approach)

FROM alpine:3.19

# Install Java and Flyway from Alpine repositories
RUN apk add --no-cache \
    openjdk17-jre \
    flyway \
    && rm -rf /var/cache/apk/*

# Create migration directory
RUN mkdir -p /flyway/sql

# Copy migration SQL files
COPY sql/ /flyway/sql/

# Set working directory
WORKDIR /flyway

# Default command (can be overridden in Kubernetes)
CMD ["flyway", "migrate"]
