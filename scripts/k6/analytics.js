// The analytics protected surface (RFC-0030 / ADR-069): one row that walks the
// guard chain and the contract of the single overview endpoint.
//
// The chain is the same as every /protected/ route -- edge checks the
// workforce issuer coarsely, the service verifier is authoritative, then the
// backoffice_admin role gate -- plus the part only analytics has: the
// response is certified fresh by three target-observed heartbeats, money is a
// decimal integer string, and every malformed filter is a 400 with the shared
// envelope. duyne-viewer is a valid staff login WITHOUT the role, so the 403
// here is the role gate and nothing else.
//
//   GATE=compose k6 run scripts/k6/analytics.js          # row A25, through the edge
//   GATE=kind    k6 run scripts/k6/analytics.js          # row K4.13, through the edge
//   GATE=kind ANALYTICS_BASE=http://127.0.0.1:18080 k6 run scripts/k6/analytics.js
//       # row K4.12, dark launch: straight at the Service through a port-forward,
//       # where the tokenless answer is the service's own envelope, not Envoy's.
//
// Row A25 of local-stack/docs/e2e-audit.md; K4.12 / K4.13 of
// docs/platform/kind-e2e-audit.md.

import http from 'k6/http';
import { target, tlsOptions, identityFor } from './lib/config.js';
import { bearer, tokenResponse } from './lib/auth.js';
import { rowCheck, rowThresholds, evidenceTable } from './lib/rows.js';

const DIRECT = __ENV.ANALYTICS_BASE || '';
const ROW = DIRECT ? 'K4.12' : target.gate === 'kind' ? 'K4.13' : 'A25';
const ROWS = [ROW];
const PATH = '/analytics/v1/protected/commerce/overview';

export const options = Object.assign(
  { vus: 1, iterations: 1, thresholds: rowThresholds(ROWS) },
  tlsOptions
);

const MINOR = /^(0|-?[1-9][0-9]*)$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

function utcDate(daysAgo) {
  const d = new Date(Date.now() - daysAgo * 86400000);
  return d.toISOString().slice(0, 10);
}

function code(r) {
  try {
    return (r.json() || {}).code;
  } catch (e) {
    return undefined;
  }
}

// Two logins on the SAME realm cannot share one VU's cookie jar: once a staff
// SSO session exists, Keycloak either hands the next authorization request a
// code for that user without a form, or refuses the other user as "already
// authenticated". setup() runs with its own jar, so the role-less token is
// minted there and handed to the VU as data.
export function setup() {
  return { viewer: tokenResponse('staff', identityFor('staff', 1)).access_token };
}

export default function (data) {
  const B = DIRECT || target.base;
  const url = `${B}${PATH}?currency=USD&from=${utcDate(7)}&to=${utcDate(0)}`;
  const viewer = { headers: { Authorization: `Bearer ${data.viewer}` } };
  const staff = bearer('staff', identityFor('staff', 0));
  const customer = bearer('customer', identityFor('customer', 0));

  // --- the guard chain ------------------------------------------------------
  rowCheck(ROW, http.get(url), {
    'tokenless is 401': (r) => r.status === 401,
    'no-store on the refusal': (r) => DIRECT ? r.headers['Cache-Control'] === 'no-store' : true,
  });
  rowCheck(ROW, http.get(url, customer), {
    'a customer token is 401, not 403': (r) => r.status === 401,
  });
  rowCheck(ROW, http.get(url, viewer), {
    'staff without backoffice_admin is 403': (r) => r.status === 403,
    'the role refusal carries FORBIDDEN': (r) => code(r) === 'FORBIDDEN',
  });

  // --- the contract ---------------------------------------------------------
  const ok = http.get(url, staff);
  let body = null;
  try {
    body = ok.json();
  } catch (e) {
    body = null;
  }
  const sources = (body && body.meta && body.meta.sources) || [];
  rowCheck(ROW, ok, {
    'staff is 200': (r) => r.status === 200,
    'no-store on the data': (r) => r.headers['Cache-Control'] === 'no-store',
    'the five sections are present': () =>
      !!body && ['filters', 'kpis', 'trend', 'funnel', 'top_products', 'meta'].every((k) => k in body),
    'money is a decimal integer string': () =>
      !!body && MINOR.test(body.kpis.settled_capture_minor) && MINOR.test(body.kpis.refunded_minor)
      && MINOR.test(body.kpis.net_captured_minor)
      && body.trend.every((d) => MINOR.test(d.settled_capture_minor) && MINOR.test(d.refunded_minor)),
    'the trend covers every UTC day of the interval': () => !!body && body.trend.length === 7
      && body.trend.every((d) => DATE.test(d.date)),
    'three sources, each healthy': () => sources.length === 3
      && ['order', 'checkout', 'payment'].every((n) => sources.some((s) => s.name === n && s.state === 'healthy')),
    'not stale': () => !!body && body.meta.stale === false,
    'counts are safe integers': () => !!body && Number.isSafeInteger(body.kpis.captured_orders)
      && Number.isSafeInteger(body.funnel.checkout_started),
  });

  // --- validation: every malformed filter is 400 with the shared envelope ---
  const bad = [
    ['missing currency', `${B}${PATH}?from=${utcDate(7)}&to=${utcDate(0)}`],
    ['VND is not served', `${B}${PATH}?currency=VND&from=${utcDate(7)}&to=${utcDate(0)}`],
    ['more than 90 days', `${B}${PATH}?currency=USD&from=${utcDate(91)}&to=${utcDate(0)}`],
    ['reversed interval', `${B}${PATH}?currency=USD&from=${utcDate(0)}&to=${utcDate(7)}`],
    ['unknown parameter', `${url}&x=1`],
    ['malformed date', `${B}${PATH}?currency=USD&from=2026-02-30&to=2026-03-02`],
  ];
  for (const [label, u] of bad) {
    rowCheck(ROW, http.get(u, staff), {
      [`${label} is 400`]: (r) => r.status === 400,
      [`${label} says VALIDATION_ERROR`]: (r) => code(r) === 'VALIDATION_ERROR',
    });
  }

  // --- readiness is a real serving-view read, only visible in direct mode --
  if (DIRECT) {
    rowCheck(ROW, http.get(`${B}/ready`), { '/ready is 200': (r) => r.status === 200 });
  }
}

export function handleSummary(data) {
  const out = evidenceTable(data, ROWS, `analytics (${DIRECT ? 'direct' : target.gate})`);
  return { stdout: out, [`scripts/k6/out/analytics-${DIRECT ? 'direct' : target.gate}.md`]: out };
}
