# Flyway Migration Image for Shipping-v2 Service
FROM alpine:3.19

RUN apk add --no-cache \
    openjdk17-jre \
    flyway \
    && rm -rf /var/cache/apk/*

RUN mkdir -p /flyway/sql
COPY sql/ /flyway/sql/
WORKDIR /flyway
CMD ["flyway", "migrate"]
