// C17-C20 -- the observability plumbing the other rows depend on.
//
// These four rows exist because a dashboard can load with a green 200 and then
// render "Datasource not found" on every panel, and a rule can evaluate against
// nothing forever without saying so. Health checks are not enough: a health
// probe proves the plugin can reach the store, not that it can run a query and
// shape a frame. So C17 checks wiring, C18 checks that every panel's datasource
// reference actually resolves, C19 runs a real query through the panel path, and
// C20 checks that the scraper has the targets the rules are written against.
//
// Grafana runs with anonymous Admin on both gates, so nothing here carries a
// token.
//
//   GATE=compose k6 run scripts/k6/observability.js
//
// NOT YET RUN against a live stack -- written from the audit rows, verified only
// for parse and imports. Rows C17-C20 of local-stack/docs/e2e-audit.md.

import http from 'k6/http';
import { target, tlsOptions } from './lib/config.js';
import { rowCheck, rowThresholds, evidenceTable } from './lib/rows.js';
import { promFrame, clickhouseFrame } from './lib/vmql.js';
import { liveDatasources, referenceProblems } from './lib/dashboards.js';

// Exact expected wiring. Derived from
// local-stack/observability/grafana/provisioning/datasources/*.yaml -- five
// files, and the comparison below is equality in both directions, so an extra
// datasource is a finding too.
const DATASOURCES = {
  victoriametrics: 'prometheus',
  victoriatraces: 'jaeger',
  clickhouse: 'grafana-clickhouse-datasource',
  pyroscope: 'grafana-pyroscope-datasource',
  victorialogs: 'victoriametrics-logs-datasource',
};

// The provisioned dashboard uids. A constant rather than a glob because k6
// cannot read the dashboard directory, and because five filenames differ from
// the uid inside them while three carry upstream's opaque ids.
const DASHBOARDS = [
  'microservices-otel-local',
  'business-otel-local',
  'temporal-worker-local',
  'red-spanmetrics',
  'otel-collector-health-local',
  'inventory-overview',
  'rfc0021-baseline',
  'clickhouse-otel-sql',
  'clickhouse-service-deepdive',
  'clickhouse-otel-overview',
  'clickhouse-logs-explorer',
  'clickhouse-traces-explorer',
  'clickhouse-server-engine',
  'heHhNSFf6Na8vIZWRs8H',
  '8WkEOMnANKE6PW5hhpVv',
  'bdn8lriao7myoa',
  'eg-edge',
  'keycloak-identity',
];

// Scrape jobs the alert rules are written against. Derived from
// observability/vmagent/prometheus.yml. Subset comparison: an extra job is
// fine, a missing one means rules evaluate against nothing.
const SCRAPE_JOBS = ['clickhouse', 'otel-collector', 'envoy-gateway', 'envoy', 'temporal', 'keycloak'];

const ROWS = ['C17', 'C18', 'C19', 'C20'];

// Compose-only, and the guard is not pedantry: the expected sets above come
// from local-stack's own provisioning. The cluster provisions dashboards as
// GrafanaDashboard CRs through the operator -- a different delivery path with a
// different count -- so running this against Kind would report a dozen false
// failures that look like broken dashboards.
if (target.gate !== 'compose') {
  throw new Error(
    `observability.js asserts local-stack's provisioned set; GATE=${target.gate} is not supported ` +
      `(the cluster's equivalent is K5.7, which is partly a kubectl row)`
  );
}

export const options = Object.assign(
  {
    scenarios: {
      wiring: { executor: 'per-vu-iterations', vus: 1, iterations: 1, exec: 'wiring' },
      // C19 and C20 read stores that lag traffic by 15-45s, so they run after a
      // settle window rather than racing the export.
      lagging: {
        executor: 'per-vu-iterations',
        vus: 1,
        iterations: 1,
        exec: 'lagging',
        startTime: __ENV.SETTLE || '50s',
      },
    },
    thresholds: rowThresholds(ROWS),
  },
  tlsOptions
);

export function wiring() {
  c17();
  c18();
}

export function lagging() {
  c19();
  c20();
}

// --- C17: the five datasources, and their health ----------------------------

function c17() {
  const res = http.get(`${target.graf}/api/datasources`);
  const got = {};
  for (const d of res.json() || []) got[d.uid] = d.type;

  const wantKeys = Object.keys(DATASOURCES).sort();
  const gotKeys = Object.keys(got).sort();
  rowCheck('C17', res, {
    'the datasource set matches exactly': () =>
      gotKeys.join(',') === wantKeys.join(',') &&
      wantKeys.every((k) => got[k] === DATASOURCES[k]),
  });

  for (const uid of wantKeys) {
    const h = http.get(`${target.graf}/api/datasources/uid/${uid}/health`);
    rowCheck('C17', h, {
      [`${uid} health is OK`]: (r) => r.status === 200 && (r.json() || {}).status === 'OK',
    });
  }
}

// --- C18: every dashboard loads, and every reference resolves ---------------

function c18() {
  const search = http.get(`${target.graf}/api/search?type=dash-db`);
  const found = (search.json() || []).map((d) => d.uid).sort();
  const want = DASHBOARDS.slice().sort();
  rowCheck('C18', search, {
    [`all ${DASHBOARDS.length} dashboards are present`]: () =>
      found.join(',') === want.join(','),
  });

  const live = liveDatasources(target.graf);

  for (const uid of DASHBOARDS) {
    const ref = referenceProblems(target.graf, uid, live);
    rowCheck('C18', null, { [`${uid} loads`]: () => ref.status === 200 });
    const bad = ref.problems;
    rowCheck('C18', null, {
      [`${uid} references resolve${bad.length ? ` (${bad.join(', ')})` : ''}`]: () =>
        bad.length === 0,
    });
  }
}

// --- C19: the panel path returns a frame, not just a healthy plugin ---------

function c19() {
  const vm = promFrame(target.graf, 'sum(spanmetrics_calls_total)');
  rowCheck('C19', null, {
    // A Prometheus instant frame puts timestamps in column 0 and the value in
    // column 1.
    'victoriametrics returns a value': () =>
      vm.ok && Array.isArray(vm.values) && vm.values[1] && vm.values[1][0] !== undefined,
  });

  const ch = clickhouseFrame(target.graf, 'SELECT count() AS spans FROM otel.otel_traces');
  rowCheck('C19', null, {
    // A ClickHouse table frame puts the selected column first.
    'clickhouse returns a value': () =>
      ch.ok && Array.isArray(ch.values) && ch.values[0] && ch.values[0][0] !== undefined,
  });
}

// --- C20: the scraper has every target the rules assume ---------------------

function c20() {
  const res = http.get(`${target.vmagent}/api/v1/targets`);
  const health = {};
  const data = res.json('data');
  for (const t of (data && data.activeTargets) || []) {
    const job = t.labels && t.labels.job;
    if (job) health[job] = t.health;
  }
  rowCheck('C20', res, {
    'the targets endpoint answers': (r) => r.status === 200,
  });
  for (const job of SCRAPE_JOBS) {
    rowCheck('C20', null, {
      [`${job} is up (got ${health[job] || 'absent'})`]: () => health[job] === 'up',
    });
  }
}

export function handleSummary(data) {
  const md = evidenceTable(data, ROWS, `Observability plumbing — gate \`${target.gate}\``);
  return { stdout: md, [`scripts/k6/out/observability-${target.gate}.md`]: md };
}
