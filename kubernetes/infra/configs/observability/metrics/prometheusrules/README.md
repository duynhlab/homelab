# Archived rule sources

Active static rules moved to the vm-rules 0.2.0 chart in duynhlab/helm-charts.
The platform-rules and temporal-rules HelmReleases select the tested bundles.
This directory is deliberately absent from every Kustomize resource list.

Only disabled/replaced CNPG definitions, retired Tempo YAML and historical
maintenance notes remain here. They are not deployed. Physical replication lag
rules were replaced by the active replication-health bundle; topology rules
remain gated. Do not restore these files into Kustomize during the migration.

See docs/observability/alerting/vm-rules-migration.md for rollout/rollback and the
chart's provenance fixture for the original active sources at homelab 66bc9a56.
