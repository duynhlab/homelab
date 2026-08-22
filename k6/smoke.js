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
import { tokenResponse, token } from './lib/auth.js';
import { rowCheck, rowThresholds, evidenceTable } from './lib/rows.js';

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
    rows: { kind: 'K4.2', compose: 'A11a' },
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
    rows: { kind: 'K4.5s', compose: 'A17a' },
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
    name: 'alert rules are loaded, and nothing urgent is firing',
    rows: { kind: 'K5.8', compose: 'C21' },
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

const planned = UNITS.filter((u) => u.rows[target.gate]).map((u) => u.rows[target.gate]);
const skipped = UNITS.filter((u) => !u.rows[target.gate]);

export const options = Object.assign(
  {
    vus: 1,
    iterations: 1,
    thresholds: rowThresholds(planned),
  },
  tlsOptions
);

export default function () {
  for (const unit of UNITS) {
    const id = unit.rows[target.gate];
    if (!id) continue;
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
    [`k6/out/smoke-${target.gate}.md`]: md,
    [`k6/out/smoke-${target.gate}.json`]: JSON.stringify(data),
  };
}
