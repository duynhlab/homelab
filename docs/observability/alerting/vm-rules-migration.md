# Native VMRule migration

This is a staged packaging migration. Rule behavior is unchanged: the baseline
is homelab `66bc9a56`, with 71 active resources, 255 alert entries and 60 recording
entries across monitoring, product, platform and cloudnative-pg. Counts come from
Kustomize output plus Temporal, not a glob including disabled files. The earlier
Kind validation of the homelab expressions remains the behavioral baseline.

## Ownership and rollout order

The target is vm-rules chart 0.2.0, published by duynhlab/helm-charts. Its platform
release owns 70 native VMRules; the separate Temporal release owns one and remains
under temporal-config's dependency on the Temporal server. Sloth and the slo
chart keep their PrometheusRules and converter path. Compose is unchanged.

**Current repository stage: finish.** Broad rule discovery is restored. Merge
only after cleanup has reconciled and all old converted static VMRules are absent.
The stages below remain the required rollout and rollback sequence.

Apply the stages as separate GitOps changes, never squash all stages into one
live reconciliation. Updating manifests in one commit does not impose an order
between Helm reconciliation and Kustomize pruning.

| Stage | Change | Required gate before advancing |
|---|---|---|
| Prepare | Label only static sources `rules.duynhlab.dev/source=manifests`; select all namespaces and exclude `chart` | All 71 converted VMRules carry the source label, existing rules remain loaded |
| Stage | Install pinned platform-rules and temporal-rules releases with source label `chart` | Both HelmReleases Ready; 71 native specs equal the source baseline; VMAlert still evaluates only the old static set |
| Cutover | Change the selector exclusion to `manifests` | VMAlert selector has reconciled to native rules, 255 alerts + 60 recordings still selected once, other/SLO rules unchanged; no new evaluation errors |
| Cleanup | Remove the old static sources from Kustomize, retain the exclusion | Converted old objects disappear through converter owner references; native releases and SLO rules remain healthy |
| Finish | Restore `selectAllByDefault: true` and remove migration selectors | Old converted objects are absent before broad selection is restored |

The old and new objects have different names. Do not adopt converted VMRules into
Helm: VM Operator owns them, and `enable_converter_ownership: true` deletes them
when their PrometheusRule sources disappear. SLO resources have no migration label
and match both NotIn selectors. Always pair ruleSelector with
`ruleNamespaceSelector: {}`; a selector alone narrows discovery to monitoring.

Before staging, confirm chart publication:

```bash
helm show chart oci://ghcr.io/duynhlab/helm-charts/vm-rules --version 0.2.0
```

Inspect both sources (run these against the intended Kind context):

```bash
kubectl get vmrule -A -l rules.duynhlab.dev/source=manifests
kubectl get vmrule -A -l rules.duynhlab.dev/source=chart
kubectl get helmrelease -n monitoring platform-rules temporal-rules
kubectl get vmalert -n monitoring victoria-metrics -o yaml
```

Check VMAlert `/api/v1/rules`, not just CR counts. Compare rule name, expression,
labels, annotations, interval and multiplicity; intentional same-name rules are
not duplicates to drop. Verify Watchdog, pending/firing states, recording series
and configuration-reload/evaluation errors. A resource/file identity change can
reset pending alert state; equality of expression text alone does not prove state
continuity. Measure this during the migration gate rather than promising it.

## Reproducible validation

In helm-charts, `make test-vm-rules` compares every imported spec with the frozen
baseline. `make check-rules` runs VMAlert dryRun for all rendered rules and promtool
for PromQL-compatible rules. Four CNPG logical-replication error/stopped alert
types use MetricsQL operations; they retain their tested expressions and are
validated by VMAlert instead of being rewritten for Prometheus's parser.

The dedicated Kind test is `scripts/e2e/test_vm_rules_migration.py` in helm-charts.
It uses an isolated context, the real VM operator/converter and VMAlert/VMSingle,
a notifier with no external receiver, plus unlabelled SLO/recording sentinels. It
checks staging, cutover, rollback, garbage collection and recording output. This
is a configuration/evaluation migration test, not a reproduction of application
traffic or a new qualification of every alert threshold.

Run `make validate` for each homelab stage before push. Keep runtime evidence with
the PR/release record. Do not advance solely because a HelmRelease is Ready.

## Rollback

Before cleanup, exclude `chart` again and wait for the converted rules to be
loaded. Keep both Helm releases installed but unselected while investigating.
After cleanup, restore the old PrometheusRules while excluding `manifests`, wait
for conversion and compare specs, then switch the exclusion to `chart`. Never
restore old sources while broad selection would evaluate both sets.

## Source maintenance

The chart holds domain bundles and a shared set of 15 CNPG definitions. Cluster
name and namespace are explicit parameters; product-db additionally excludes the
single-instance product-db-replica job from its two HA alerts. Backup, DR and
role-membership expressions keep their site-specific selectors. extraRules adds
new local definitions without changing bundled Prometheus annotation templates.

Disabled/replaced CNPG files and retired Tempo files stay inactive. Do not enable
them through the migration. Preserve their operational rationale in the catalog
and CNPG notes; new expressions or threshold changes require a separate review.

## Migration test evidence

2026-10-20, disposable Kind Kubernetes 1.37.0, VM Operator 0.75.0 (chart 0.68.1),
VMAlert 1.152.0: each baseline/stage/cutover/rollback/cleanup snapshot held 319
rules (315 original plus four test sentinels), all health=ok. The selector canary
proved source changes; old converted VMRules were garbage-collected. The SLO
sentinel kept its activeAt and the recording sentinel returned 7. This test used
an isolated datasource and does not replace the original Kind behavioral audit.
The test cluster was removed and Podman stopped. Reproduce using the chart's
Kind integration script; CI runs the same gate on Kubernetes 1.35.8.
