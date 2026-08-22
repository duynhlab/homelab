// Drive real orders through the edge, and watch the Temporal task queue build.
//
// Why this exists: `approximate_backlog_count{taskqueue="order_fulfillment"}`
// has never been anything but zero on this platform. ADR-055 proposes scaling
// workers on that signal, and nothing in either gate could move it -- both are
// hand-driven, so the queue is always drained faster than a human types. A
// KEDA trigger cannot be trusted against a metric nobody has seen leave zero.
//
// Every request goes through the edge. Calling a ClusterIP directly would make
// backlog trivially easy and the run worthless as gate evidence: ADR-046 is
// explicit that a tag may never be gated on a path that skips edge policy.
//
// Pacing is therefore bounded by the edge limiter, and the bound is per route,
// not per run: one order costs 2 requests on `cart` and 5 on `checkout`, so the
// checkout bucket is what binds. ORDERS_PER_SEC defaults well inside it.
//
// Identity, not just concurrency: the services hold one active checkout session
// per user, so two VUs driving the same identity evict each other and the
// failure surfaces as an unrelated 409. One VU per identity, four identities,
// four VUs -- that is the ceiling here and it is a data constraint, not a
// tuning choice.
//
//   # 1. take the consumer away so the queue can actually grow
//   kubectl -n order scale deploy -l temporal.io/deployment-name=order-fulfillment --replicas=0
//   # 2. drive orders and watch the backlog
//   GATE=kind k6 run scripts/k6/load.js
//   # 3. give the consumer back and watch it drain
//   kubectl -n order scale deploy -l temporal.io/deployment-name=order-fulfillment --replicas=1

import http from 'k6/http';
import { Counter, Trend } from 'k6/metrics';
import { target, tlsOptions, identityFor } from './lib/config.js';
import { bearer } from './lib/auth.js';
import { rowCheck, rowThresholds } from './lib/rows.js';
import { clearCart, addItem, freshSession, priceSession, confirmSession } from './lib/funnel.js';

const ORDERS_PER_SEC = Number(__ENV.ORDERS_PER_SEC || 2);
const DURATION = __ENV.LOAD_DURATION || '30s';
const TASK_QUEUE = __ENV.TASK_QUEUE || 'order_fulfillment';

const confirmed = new Counter('orders_confirmed');
const rejected = new Counter('orders_rejected');
// Trend, not Gauge: a Gauge keeps only the last reading, and the last reading
// of a queue is usually zero -- the run would report "no backlog" precisely
// because the backlog drained before the test ended.
const backlog = new Trend('temporal_backlog');

const ROWS = ['LD.1', 'LD.2'];

export const options = Object.assign(
  {
    scenarios: {
      orders: {
        executor: 'constant-arrival-rate',
        rate: ORDERS_PER_SEC,
        timeUnit: '1s',
        duration: DURATION,
        preAllocatedVUs: 4,
        maxVUs: 4,
        exec: 'order',
      },
      // Reads the queue while the load is still running, because a backlog that
      // has already drained is indistinguishable from one that never formed.
      backlog: {
        executor: 'constant-arrival-rate',
        rate: 1,
        timeUnit: '3s',
        duration: DURATION,
        preAllocatedVUs: 1,
        exec: 'watch',
        startTime: '5s',
      },
    },
    thresholds: rowThresholds(ROWS),
  },
  tlsOptions
);

function json(extra) {
  return Object.assign({ 'Content-Type': 'application/json' }, extra);
}

export function order() {
  const who = identityFor('customer', __VU - 1);
  const auth = bearer('customer', who);
  const B = target.base;

  // A stale cart carries lines from an earlier iteration and changes the total,
  // so each order starts from an empty one.
  clearCart(B, auth);
  addItem(B, auth, {
    product_id: '1',
    product_name: 'Wireless Mouse',
    product_price: 29.99,
    quantity: 1,
  });

  const opened = freshSession(B, auth);
  const sid = opened.id;
  if (!sid) {
    rejected.add(1);
    return;
  }
  priceSession(B, auth, sid, { address: { full_name: 'Load', line1: '1 Main St', city: 'HN', country: 'VN' } });
  const done = confirmSession(B, auth, sid, `load-${__VU}-${__ITER}-${sid}`);
  if (done.status === 201 || done.status === 200) confirmed.add(1);
  else rejected.add(1);
}

// The oracle. VictoriaMetrics already scrapes the matching service, so the
// signal a KEDA trigger would read is the one asserted here -- note the label
// is `order_fulfillment` with an underscore, not the CRD's `order-fulfillment`.
export function watch() {
  const q = `sum(approximate_backlog_count{taskqueue="${TASK_QUEUE}"})`;
  const res = http.get(`${target.vm}/api/v1/query?query=${encodeURIComponent(q)}`);
  rowCheck('LD.1', res, { 'the backlog series is readable': (r) => r.status === 200 });
  const result = res.json('data') && res.json('data').result;
  if (result && result.length) {
    backlog.add(Number(result[0].value[1]));
  }
}

export function handleSummary(data) {
  const ok = (data.metrics.orders_confirmed && data.metrics.orders_confirmed.values.count) || 0;
  const no = (data.metrics.orders_rejected && data.metrics.orders_rejected.values.count) || 0;
  const peak = (data.metrics.temporal_backlog && data.metrics.temporal_backlog.values.max) || 0;

  const lines = [
    `### Order load — gate \`${target.gate}\``,
    '',
    `| | |`,
    `|---|---|`,
    `| Rate | ${ORDERS_PER_SEC} orders/s for ${DURATION} |`,
    `| Confirmed | ${ok} |`,
    `| Rejected | ${no} |`,
    `| Backlog peak (\`${TASK_QUEUE}\`) | **${peak}** |`,
    '',
  ];
  // A zero peak is the interesting case and must not read as success: it means
  // either the workers kept up (so scale them down and repeat) or the metric is
  // not what a KEDA trigger should watch.
  if (peak > 0) {
    lines.push(
      `The queue left zero: peak **${peak}** tasks. That is the signal ADR-055 ` +
        `proposes to scale on, observed rather than assumed.`,
      ''
    );
  } else {
    lines.push(
      `Backlog never left zero. Either the workers drained it as fast as it ` +
        `arrived -- scale the worker deployment to 0 and run again -- or ` +
        `\`${TASK_QUEUE}\` is the wrong label to trigger on.`,
      ''
    );
  }
  const md = lines.join('\n');
  return { stdout: md, [`scripts/k6/out/load-${target.gate}.md`]: md };
}
