# PGDG package payload is checksum-pinned; do not upgrade PostgreSQL while adding an extension.
FROM postgres:18.7-trixie@sha256:64c8b0d31e4ab6ea665e8426ea406a94bf52de3c05b3a4a8bf713704eefa9328 AS extract
USER root
ARG TARGETARCH
ADD --checksum=sha256:512826a6247ad098dae3df7544361de70bc219ccc4585943ca7ad90a4bf68109 https://apt.postgresql.org/pub/repos/apt/pool/main/p/pg-cron/postgresql-18-cron_1.6.8-1.pgdg13+2_amd64.deb /tmp/cron-amd64.deb
ADD --checksum=sha256:fc12361081929e415f08f9c83556f296c8f732872e50be9687bd63d966c7f11a https://apt.postgresql.org/pub/repos/apt/pool/main/p/pg-cron/postgresql-18-cron_1.6.8-1.pgdg13+2_arm64.deb /tmp/cron-arm64.deb
RUN dpkg-deb --extract /tmp/cron-${TARGETARCH}.deb /extension

FROM postgres:18.7-trixie@sha256:64c8b0d31e4ab6ea665e8426ea406a94bf52de3c05b3a4a8bf713704eefa9328
COPY --from=extract /extension/usr/lib/postgresql/18/lib/pg_cron.so /usr/lib/postgresql/18/lib/pg_cron.so
COPY --from=extract /extension/usr/share/postgresql/18/extension/ /usr/share/postgresql/18/extension/
RUN test -f /usr/share/postgresql/18/extension/pg_cron.control && \
    ldd /usr/lib/postgresql/18/lib/pg_cron.so > /tmp/cron-ldd && \
    ! grep -q "not found" /tmp/cron-ldd
