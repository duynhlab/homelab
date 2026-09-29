# The ClickHouse OTel schema as an image volume (ADR-077). Nothing runs from it:
# the clickhouse-schema Job mounts /sql read-only. Build it only through
# `make ddl-image` / the clickhouse-ddl workflow, which pin BuildKit so the same
# SQL always yields the same digest.
FROM scratch
# --chmod pins the mode: a checkout's mode follows the local umask (0664 on one
# machine, 0644 on a CI runner), and a different mode is a different layer, i.e.
# a different digest. Symbolic, with a capital X: directories get 0755 (the Job
# runs as uid 101 and must traverse /sql), files get 0644 -- an octal 0644 left
# /sql itself untraversable.
COPY --chmod=u=rwX,go=rX sql/ /sql/
