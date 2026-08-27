// The functional half of both E2E gates, as assertions instead of prose.
//
// Each unit below is one audit row. A unit declares its row id per gate,
// because the two runbooks number the same assertion differently (a token mint
// is A1 on compose and K4.5 on Kind) and some rows exist on only one side (TLS
// rows are meaningless on plain-HTTP compose). A unit with no id for the
// current gate is SKIPPED and counted as such -- the coverage asymmetry between
// the gates is then a number in the summary rather than a thing you notice by
// reading two files side by side.
//
//   GATE=kind    k6 run k6/smoke.js
//   GATE=compose k6 run k6/smoke.js
//
// Exit code is the verdict: a failed assertion breaches its row's threshold and
// k6 exits non-zero.

import http from 'k6/http';
import encoding from 'k6/encoding';
import { target, tlsOptions, identityFor, REALMS } from './lib/config.js';
import { tokenResponse, token, bearer } from './lib/auth.js';
import { rowCheck, rowThresholds, evidenceTable } from './lib/rows.js';
import { promqlScalar, promqlCountBy, logsqlCount } from './lib/vmql.js';
import { liveDatasources, dashboardUids, referenceProblems } from './lib/dashboards.js';

const CATALOG = '/product/v1/public/products';

// The ten deployed services. `auth` is retired (Keycloak replaced it) and its
// continued absence is an assertion, not an omission.
const SERVICES = [
  'cart', 'checkout', 'inventory', 'notification', 'order',
  'payment', 'product', 'review', 'shipping', 'user',
];

function claims(accessToken) {
  return JSON.parse(encoding.b64decode(accessToken.split('.')[1], 'rawurl', 's'));
}

// --- units -----------------------------------------------------------------

const UNITS = [
  {
    name: 'plain HTTP is redirected, not served',
    rows: { kind: 'K4.1' },
    run(id) {
      const res = http.get(`http://gateway.duynh.me${CATALOG}`, { redirects: 0 });
      rowCheck(id, res, {
        'is 301': (r) => r.status === 301,
        'sends no body': (r) => !r.body || r.body.length === 0,
      });
    },
  },
  {
    name: 'TLS serves the seeded catalog',
    rows: { kind: 'K4.2' },
    run(id) {
      const res = http.get(`${target.base}${CATALOG}`);
      rowCheck(id, res, {
        'is 200': (r) => r.status === 200,
        'body is a non-empty array': (r) => {
          const b = r.json();
          return Array.isArray(b) ? b.length > 0 : Array.isArray(b && b.items) && b.items.length > 0;
        },
      });
    },
  },
  {
    name: 'routing is by Host header, not by whatever answers the socket',
    rows: { kind: 'K4.3' },
    run(id) {
      // The runbook drove this as `https://127.0.0.1/...` and wanted 404. That
      // request cannot reach HTTP at all: SNI may not carry an IP literal, so
      // no TLS filter chain matches and Envoy drops the connection -- curl
      // reports exit 35 and http_code 000, k6 an EOF. The row therefore could
      // not pass as written, and its failure looked like a broken edge.
      //
      // Keep the intent, fix the mechanism: reach the real listener with a
      // valid SNI, then send a Host header no HTTPRoute claims. Now the
      // request is routed -- and answered 404 by the routing layer, which is
      // the thing the row means to prove.
      const res = http.get(`${target.base}${CATALOG}`, { headers: { Host: 'nope.invalid' } });
      rowCheck(id, res, { 'an unrouted Host is 404': (r) => r.status === 404 });
    },
  },
  {
    name: 'both realms exist and answer as themselves',
    rows: { kind: 'K4.4' },
    run(id) {
      for (const kind of ['customer', 'staff']) {
        const want = REALMS[kind].realm;
        const res = http.get(`${target.kc}/realms/${want}`);
        rowCheck(id, res, {
          [`${want} is 200`]: (r) => r.status === 200,
          [`${want} names itself`]: (r) => r.json() && r.json().realm === want,
        });
      }
    },
  },
  {
    name: 'a customer token mints, and its claims are the contract',
    rows: { kind: 'K4.5', compose: 'A1' },
    run(id) {
      const t = tokenResponse('customer', identityFor('customer', 0));
      const c = claims(t.access_token);
      const aud = Array.isArray(c.aud) ? c.aud : [c.aud];
      rowCheck(id, t, {
        'iss is the customer realm': () => c.iss === `${target.kc}/realms/${REALMS.customer.realm}`,
        'sub is a UUID string': () => typeof c.sub === 'string' && /^[0-9a-f-]{36}$/.test(c.sub),
        'aud includes duynhlab-platform': () => aud.indexOf('duynhlab-platform') !== -1,
        'carries a refresh token': (r) => !!r.refresh_token,
        'expires_in is 900': (r) => r.expires_in === 900,
      });
    },
  },
  {
    name: 'a staff token mints through the workforce realm',
    // The Kind runbook has no staff mint anywhere -- K4.7 exercises staff
    // identity in a browser only -- so this closes a real hole rather than
    // restating a row.
    rows: { kind: 'K4.5s' },
    run(id) {
      const t = tokenResponse('staff', identityFor('staff', 0));
      const c = claims(t.access_token);
      rowCheck(id, t, {
        'iss is the staff realm': () => c.iss === `${target.kc}/realms/${REALMS.staff.realm}`,
        'sub is a UUID string': () => typeof c.sub === 'string' && /^[0-9a-f-]{36}$/.test(c.sub),
      });
    },
  },
  {
    name: 'the realm fence holds at the edge',
    rows: { kind: 'K4.8' },
    run(id) {
      // A customer token on a /protected/ route must die as wrong-issuer at the
      // edge. 403 would mean the edge passed it and a service caught it -- a
      // weaker contract than the one documented, so it is a finding.
      const res = http.get(`${target.base}/inventory/v1/protected/balances`, {
        headers: { Authorization: `Bearer ${token('customer', identityFor('customer', 0))}` },
      });
      rowCheck(id, res, {
        'is 401, not 403': (r) => r.status === 401,
      });
    },
  },
  {
    name: 'traces cover every service and the edge',
    rows: { kind: 'K5.2', compose: 'C6' },
    group: 'telemetry',
    run(id) {
      const res = http.get(`${target.vtraces}/select/jaeger/api/services`);
      const names = (res.json('data') || []).map(String);
      rowCheck(id, res, {
        'is 200': (r) => r.status === 200,
        'all ten services present': () => SERVICES.every((s) => names.some((n) => n === s || n.indexOf(s) === 0)),
        'the edge is present': () => names.some((n) => n.indexOf('envoy') !== -1 || n.indexOf('gateway') !== -1),
        'auth is absent': () => !names.some((n) => n === 'auth'),
      });
    },
  },
  {
    name: 'profiles cover every service',
    rows: { kind: 'K5.6', compose: 'C16' },
    group: 'telemetry',
    run(id) {
      // Connect-RPC, and the window is milliseconds since epoch.
      const end = Date.now();
      const res = http.post(
        `${target.pyroscope}/querier.v1.QuerierService/LabelValues`,
        JSON.stringify({ name: 'service_name', matchers: ['{}'], start: end - 3600000, end: end }),
        { headers: { 'Content-Type': 'application/json' } }
      );
      const names = (res.json('names') || []).map(String);
      rowCheck(id, res, {
        'is 200': (r) => r.status === 200,
        'all ten services present': () => SERVICES.every((s) => names.some((n) => n === s || n.indexOf(s) === 0)),
        'auth is absent': () => !names.some((n) => n === 'auth'),
      });
    },
  },
  {
    name: 'private routes answer through the edge JWT filter',
    rows: { compose: 'A2' },
    run(id) {
      const auth = bearer('customer', identityFor('customer', 0));
      for (const p of [
        '/user/v1/private/users/profile',
        '/cart/v1/private/cart',
        '/order/v1/private/orders',
        '/notification/v1/private/notifications',
      ]) {
        const res = http.get(`${target.base}${p}`, auth);
        rowCheck(id, res, { [`${p} is 200`]: (r) => r.status === 200 });
      }
    },
  },
  {
    name: 'a missing or unverifiable token dies at the edge',
    rows: { compose: 'A3' },
    run(id) {
      // Three claims, all required: the status, the plain-text reason the
      // jwt_authn filter writes, and the challenge header. The realm value is
      // the REQUEST URL rather than an identity-provider URL -- Envoy echoes
      // back what was asked for.
      const url = `${target.base}/cart/v1/private/cart`;
      const none = http.get(url);
      const wa = none.headers['Www-Authenticate'] || none.headers['WWW-Authenticate'] || '';
      rowCheck(id, none, {
        'no token is 401': (r) => r.status === 401,
        'body says Jwt is missing': (r) => String(r.body || '').indexOf('Jwt is missing') !== -1,
        'content-type is text/plain': (r) =>
          String(r.headers['Content-Type'] || '').indexOf('text/plain') !== -1,
        'www-authenticate names the requested URL': () =>
          wa.indexOf(`Bearer realm="${url}"`) === 0,
      });

      const broken = http.get(url, { headers: { Authorization: 'Bearer x.y.z' } });
      const wa2 = broken.headers['Www-Authenticate'] || broken.headers['WWW-Authenticate'] || '';
      rowCheck(id, broken, {
        'a broken token is 401': (r) => r.status === 401,
        'the challenge adds error="invalid_token"': () =>
          wa2.indexOf('error="invalid_token"') !== -1,
      });
    },
  },
  {
    name: 'the collection-noun shipping paths serve, and the old alias still does',
    rows: { compose: 'A7' },
    run(id) {
      // Expand phase: the v3 paths and the deprecated alias must both answer.
      // The retired auth alias is deliberately not probed -- it certified a
      // token layer that no longer has a backend.
      const trk = '1Z999AA10123456784';
      const cases = [
        [`/shipping/v1/public/shipments/track?tracking_number=${trk}`, 'shipments/track'],
        ['/shipping/v1/public/shipments/estimate?origin=HN&destination=SG&weight=1', 'shipments/estimate'],
        [`/shipping/v1/public/track?tracking_number=${trk}`, 'deprecated alias'],
      ];
      for (const [path, label] of cases) {
        const res = http.get(`${target.base}${path}`);
        rowCheck(id, res, { [`${label} is 200`]: (r) => r.status === 200 });
      }
    },
  },
  {
    name: 'product details fans out across the fleet',
    rows: { compose: 'A11' },
    run(id) {
      const res = http.get(`${target.base}/product/v1/public/products/1/details`);
      const d = res.json() || {};
      const p = d.product || {};
      const a = d.availability || {};
      const reviews = d.reviews;
      const summary = d.reviews_summary || {};
      rowCheck(id, res, {
        // The id is a STRING in this contract, not a number.
        'product.id is "1"': () => p.id === '1',
        'availability carries available_to_promise': () =>
          a.available_to_promise !== undefined && a.available_to_promise !== null,
        'reviews is a non-empty list': () => Array.isArray(reviews) && reviews.length > 0,
        'reviews_summary.total matches the list': () =>
          Array.isArray(reviews) && summary.total === reviews.length,
      });
    },
  },
  {
    name: 'both log legs carry what only they can carry',
    rows: { kind: 'K5.3' },
    group: 'telemetry',
    run(id) {
      // The OTLP leg is a service's own tee; the Vector leg is a container with
      // NO SDK. Both examples changed, for different reasons.
      //
      // OTLP: `product`, not `cart`. Nothing in this gate's drive step touches
      // cart -- it needs an authenticated session -- so the row only passed when
      // the saga or staff suite happened to have run in the last 45 minutes.
      // Same defect as K5.2 had with user-service: a row must drive what it
      // asserts. drive() calls product.
      //
      // Vector: a database container, not the edge. ADR-060 gave Envoy Gateway
      // an OpenTelemetry access-log sink and labelled its pods
      // platform.duynhlab.dev/otlp-logs=true, so Vector no longer tails the edge
      // at all -- it is now an example of the OTLP leg, not the Vector one.
      // CloudNativePG has no OTel SDK, which is exactly what this leg is for.
      // Selected by namespace + container_name because Vector sets `service`
      // from pod_labels.app and falls back to the pod name.
      const otlp = logsqlCount(target.logs, '_time:45m _stream:{"service.name"="product"} | count()');
      const vector = logsqlCount(
        target.logs,
        '_time:45m _stream:{namespace="product",container_name="postgres"} | count()'
      );
      rowCheck(id, null, {
        'the OTLP leg has product logs': () => otlp !== null && otlp > 0,
        'the Vector leg has database logs': () => vector !== null && vector > 0,
      });
    },
  },
  {
    name: 'each worker is its own telemetry identity',
    rows: { kind: 'K5.4' },
    group: 'telemetry',
    run(id) {
      const byService = promqlCountBy(
        target.vm,
        'count by (service_name) (go_goroutine_count)',
        'service_name'
      );
      for (const svc of ['order', 'order-worker', 'checkout', 'checkout-worker']) {
        rowCheck(id, null, {
          [`${svc} is its own service_name`]: () => (byService[svc] || 0) >= 1,
        });
      }
      // More than one worker process is EXPECTED while a version is inside
      // its sunset window -- two versions of one worker share a service_name,
      // which is exactly what service_version exists to split. Since ADR-064
      // BOTH workers run under the controller, so both must split.
      for (const w of ['order-worker', 'checkout-worker']) {
        const byVersion = promqlCountBy(
          target.vm,
          `count by (service_name, service_version) (go_goroutine_count{service_name="${w}"})`,
          'service_version'
        );
        const versions = Object.keys(byVersion).filter((v) => v && v !== 'undefined');
        rowCheck(id, null, {
          [`${w} splits by service_version`]: () => versions.length >= 1,
        });
      }
    },
  },
  {
    name: 'the five metric legs fail independently',
    rows: { kind: 'K5.5' },
    group: 'telemetry',
    run(id) {
      // Five legs, five ways to lose telemetry without losing the others.
      const legs = [
        ['app HTTP semconv', 'sum(http_server_request_duration_seconds_count)'],
        ['app gRPC semconv', 'sum(rpc_server_call_duration_seconds_count{service_name="inventory"})'],
        // ONE spelling again. The 2026-08-25 straddle (two workers on two
        // SDKs emitting two names for one family) ended with ADR-063: both
        // workers run temporalx v0.38.0, and the fleet's 49-name temporal_*
        // set was measured identical per worker on the compose gate
        // (2026-08-27) — histograms uniformly `_seconds`, counters `_total`.
        ['Temporal SDK', 'count(temporal_workflow_endtoend_latency_seconds_bucket)'],
        ['edge Envoy stats', 'sum(envoy_http_downstream_rq_total)'],
        // The connector leg. Derived from spans by the collector rather than
        // emitted by an SDK, so it is the one leg that survives an SDK metrics
        // outage and dies with the collector's traces pipeline -- which is the
        // whole point of listing legs separately. Cluster-side since ADR-057;
        // it was compose-only before, which is why this leg did not exist.
        ['span_metrics connector', 'sum(spanmetrics_calls_total{span_kind="SPAN_KIND_SERVER"})'],
      ];
      for (const [label, q] of legs) {
        const v = promqlScalar(target.vm, q);
        rowCheck(id, null, { [`${label} has series`]: () => v !== null && v > 0 });
      }
    },
  },
  {
    name: 'every dashboard reference resolves',
    // K5.7's third assertion only. Its first two -- that every GrafanaDashboard
    // CR reconciled, and that the url-sourced ones actually fetched -- are
    // kubectl-and-git work and stay in the runbook.
    rows: { kind: 'K5.7' },
    group: 'telemetry',
    run(id) {
      // The uid list comes from Grafana rather than a literal: the cluster
      // provisions through operator CRs, so its set differs from local-stack's
      // and a hard-coded list here would rot on the next dashboard.
      const uids = dashboardUids(target.graf);
      rowCheck(id, null, { 'the dashboard list is readable': () => uids !== null });
      if (!uids) return;
      const live = liveDatasources(target.graf);
      const broken = [];
      for (const uid of uids) {
        const ref = referenceProblems(target.graf, uid, live);
        if (ref.status !== 200 || ref.problems.length) {
          broken.push(`${uid}: ${ref.problems.join(', ') || ref.status}`);
        }
      }
      rowCheck(id, null, {
        [`all ${uids.length} dashboards resolve${broken.length ? ` (${broken.slice(0, 3).join('; ')})` : ''}`]: () =>
          broken.length === 0,
      });
    },
  },
  {
    name: 'the identity provider emits its own signals',
    // K5.9's HTTP half. The ServiceMonitor and PrometheusServiceLevel checks
    // stay kubectl rows -- an identity provider can serve tokens perfectly
    // while emitting nothing, which is why this is asserted separately from
    // K4.4/K4.5.
    rows: { kind: 'K5.9' },
    group: 'telemetry',
    run(id) {
      const up = promqlScalar(target.vm, 'max(up{job=~".*keycloak.*"})');
      rowCheck(id, null, { 'the Keycloak scrape target is up': () => up === 1 });

      const rules = http.get(`${target.vmalert}/api/v1/rules`);
      const names = [];
      for (const g of (rules.json('data') || {}).groups || []) {
        for (const r of g.rules || []) names.push(r.name);
      }
      for (const alert of [
        'KeycloakDown',
        'KeycloakRestartLoop',
        'KeycloakLoginFailureRatioHigh',
        'KeycloakTokenLatencyHigh',
        'KeycloakDbPoolExhausted',
      ]) {
        rowCheck(id, null, { [`${alert} is loaded`]: () => names.indexOf(alert) !== -1 });
      }

      rowCheck(id, http.get(`${target.graf}/api/dashboards/uid/keycloak-identity`), {
        'the identity dashboard loads': (r) => r.status === 200,
      });
    },
  },
  {
    name: 'alert rules are loaded, and nothing urgent is firing',
    rows: { kind: 'K5.8', compose: 'C21' },
    group: 'telemetry',
    run(id) {
      const res = http.get(`${target.vmalert}/api/v1/rules`);
      const groups = (res.json('data') && res.json('data').groups) || [];
      const rules = [];
      for (const g of groups) for (const r of g.rules || []) rules.push(r);
      const firing = rules.filter((r) => r.state === 'firing');
      const urgent = firing.filter(
        (r) => r.labels && (r.labels.severity === 'page' || r.labels.severity === 'critical')
      );
      // Deliberately no total-rule count: the alert catalog marks a subset
      // inactive on Kind, so a number here would fail for platform reasons.
      // `ticket` severity firing on a young cluster is expected, not a finding.
      rowCheck(id, res, {
        'is 200': (r) => r.status === 200,
        'rules are loaded': () => rules.length > 0,
        'no page or critical firing': () => urgent.length === 0,
        'Watchdog is present': () => rules.some((r) => r.name === 'Watchdog'),
      });
      if (urgent.length) {
        console.warn(`${id} urgent firing: ${urgent.map((r) => r.name).join(', ')}`);
      }
    },
  },
];

// --- wiring ----------------------------------------------------------------

const forGate = (u) => u.rows[target.gate];
const planned = UNITS.filter(forGate).map(forGate);
const skipped = UNITS.filter((u) => !forGate(u));

// Two scenarios rather than one, because the telemetry rows assert on a store
// that lags the traffic. Coverage rows ask "does every service appear in the
// trace store" -- a question about the cluster, not about this run, but one
// this run can still spoil: a service nothing has called since bring-up has no
// span to find. `drive` therefore touches the surfaces that are otherwise never
// exercised, and `telemetry` starts late enough for those spans to land.
const SETTLE = '50s';

export const options = Object.assign(
  {
    scenarios: {
      drive: { executor: 'per-vu-iterations', vus: 1, iterations: 1, exec: 'drive' },
      functional: { executor: 'per-vu-iterations', vus: 1, iterations: 1, exec: 'functional' },
      telemetry: {
        executor: 'per-vu-iterations',
        vus: 1,
        iterations: 1,
        exec: 'telemetry',
        startTime: SETTLE,
      },
    },
    thresholds: rowThresholds(planned),
  },
  tlsOptions
);

function runGroup(kinds) {
  for (const unit of UNITS) {
    const id = forGate(unit);
    if (!id || kinds.indexOf(unit.group || 'functional') === -1) continue;
    // Isolate units. An uncaught throw ends the whole iteration, which would
    // leave every later row with no verdict -- one broken row would hide the
    // state of all the others, and a gate that reports less the worse things
    // are is the wrong shape.
    try {
      unit.run(id);
    } catch (e) {
      rowCheck(id, null, { [`did not raise: ${e.message}`]: () => false });
    }
  }
}

// Not assertions -- traffic. Every service must have been called at least once
// in the cluster's life for the coverage rows to mean anything, and the two
// read surfaces below are the ones no other row touches: `review` is only ever
// reached through product's fan-out, so a run that lists products never gives
// it a span.
export function drive() {
  // `product_id` is required on the review list -- a bare GET answers 400, and
  // a drive step that manufactures 400s is worse than none: it fired
  // ReviewHighOverallErrorRate and then failed the alert row two scenarios
  // later, which reads as a platform fault caused by the test.
  http.get(`${target.base}/review/v1/public/reviews?product_id=1`);
  http.get(`${target.base}/product/v1/public/products/1/details`);
  // `user` gets a span from nothing else on this gate. The private-routes row
  // that calls its profile endpoint declares only a compose id (A2), and the
  // storefront sign-in that would otherwise touch it is a Phase B *browser*
  // row. K5.2 asserts every service has a span, so the drive step has to
  // create this one -- the same reason `review` is driven above. It must be the
  // authenticated 200 path: a bare public GET answers 404 here (users are not
  // keyed by a small integer), and manufacturing 404s is what the note above
  // warns about.
  http.get(`${target.base}/user/v1/private/users/profile`, bearer('customer', identityFor('customer', 0)));
}

export function functional() {
  runGroup(['functional']);
}

export function telemetry() {
  runGroup(['telemetry']);
}

export function handleSummary(data) {
  let md = evidenceTable(data, planned, `Smoke — gate \`${target.gate}\``);
  if (skipped.length) {
    md +=
      `\nNo row on this gate (${skipped.length}): ` +
      skipped.map((u) => u.name).join('; ') +
      '\n';
  }
  return {
    stdout: md,
    [`scripts/k6/out/smoke-${target.gate}.md`]: md,
    [`scripts/k6/out/smoke-${target.gate}.json`]: JSON.stringify(data),
  };
}
