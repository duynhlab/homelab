// Put demo stock back, through the write path the service actually supports.
//
// Why this exists: `scripts/kind-seed.sh` cannot do it. The inventory seed is
//
//   INSERT INTO inventory_balances (...) ... ON CONFLICT (sku_id, warehouse_id) DO NOTHING;
//
// so once the rows exist, re-running the seed is a no-op -- and the load row
// drains them. A gate run that rejects 56 of 60 orders reads like a broken
// platform when it is only an empty warehouse.
//
// Why not SQL: the seed file says it outright -- "a real balance now arrives one
// way only, an explicit RECEIVE movement through the normal write path, which
// keeps on_hand == SUM(on_hand_delta) intact". An UPDATE on inventory_balances
// breaks that invariant, and the repo has a test asserting it
// (checkLedgerInvariant, reservations_integration_test.go). So this posts
// receipts, exactly as audit row A17 already does.
//
// Why k6: the realms do not accept a password grant, so a staff token needs
// auth-code + PKCE. lib/auth.js already implements it, and A17 already proves
// the receipts call works through the edge with that token. Nothing else in this
// repo can mint one in a shell.
//
// Deficit, not a flat top-up: re-running must not inflate stock. This reads the
// balances first and receives only what is missing against the seed baseline, so
// a second run posts nothing and the gate returns to a state comparable with
// earlier rounds.
//
//   GATE=kind    k6 run scripts/k6/restock.js
//   GATE=compose k6 run scripts/k6/restock.js
//
// Demo data only. It travels the normal write path, so unlike the `seed`
// subcommand -- which refuses anything but ENV=development -- nothing in the
// service will stop this. Do not point it at an environment that matters.

import http from 'k6/http';
import { Counter, Gauge } from 'k6/metrics';
import { target, tlsOptions, identityFor } from './lib/config.js';
import { bearer } from './lib/auth.js';

// The baseline is the seed's own numbers, copied from
// inventory-service/db/seed/sql/000002_seed_demo_stock.up.sql so a restored
// cluster matches a freshly seeded one. Keep them in step with that file.
const BASELINE = {
  '1': 50, '2': 30, '3': 25, '4': 40, '5': 20, '6': 15, '7': 35,
  '8': 18, '9': 28, '10': 60, '11': 75, '12': 120, '13': 38,
};
const WAREHOUSE_ID = Number(__ENV.WAREHOUSE_ID || 1);

const received = new Counter('stock_units_received');
const receipts = new Counter('stock_receipts_posted');
const failures = new Counter('stock_receipts_failed');

// One gauge per SKU per side. `handleSummary` runs in its own context, so a
// value stashed on globalThis during the iteration never reaches it -- the
// first version of this script printed a table of `?` for exactly that reason.
// Metrics are the supported channel, and they must be created in init context,
// which is fine because the SKU list is a constant.
const gBefore = {};
const gAfter = {};
for (const sku of Object.keys(BASELINE)) {
  gBefore[sku] = new Gauge(`stock_before_${sku}`);
  gAfter[sku] = new Gauge(`stock_after_${sku}`);
}

export const options = Object.assign(
  {
    scenarios: { restock: { executor: 'per-vu-iterations', vus: 1, iterations: 1, exec: 'restock' } },
  },
  tlsOptions
);

// `on_hand` is what the seed sets, so `on_hand` is what the baseline compares
// against. `atp` (on_hand - reserved) is availability and moves with in-flight
// reservations -- topping up against it would over-receive.
function readOnHand(inv, auth) {
  const byId = {};
  // The list is paginated; ask per SKU instead of walking pages. Untracked SKUs
  // answer 404 by contract ("never an empty 200"), which is a real answer here:
  // it means the seed never ran, so the full baseline is the deficit.
  for (const sku of Object.keys(BASELINE)) {
    const res = http.get(`${inv}/balances/${sku}`, auth);
    if (res.status === 404) {
      byId[sku] = 0;
      continue;
    }
    if (res.status !== 200) {
      byId[sku] = null; // unknown -- reported, not guessed at
      continue;
    }
    const rows = ((res.json() || {}).items) || [];
    const row = rows.find((r) => Number(r.warehouse_id) === WAREHOUSE_ID);
    byId[sku] = row ? Number(row.on_hand) : 0;
  }
  return byId;
}

export function restock() {
  const inv = `${target.base}/inventory/v1/protected`;
  const staff = bearer('staff', identityFor('staff', 0));
  const staffJson = { headers: Object.assign({ 'Content-Type': 'application/json' }, staff.headers) };

  const before = readOnHand(inv, staff);

  for (const [sku, want] of Object.entries(BASELINE)) {
    const have = before[sku];
    if (have === null) {
      failures.add(1);
      continue;
    }
    gBefore[sku].add(have);
    const deficit = want - have;
    if (deficit <= 0) {
      gAfter[sku].add(have);
      continue;
    }
    // A fresh command_id every run: the same key with a different payload is a
    // 409 IDEMPOTENCY_CONFLICT, and the same key with the same payload is a
    // 200 applied:false replay. Neither is what a top-up wants.
    const body = JSON.stringify({
      command_id: `restock-${sku}-wh${WAREHOUSE_ID}-${Date.now()}`,
      sku_id: sku,
      warehouse_id: WAREHOUSE_ID,
      quantity: deficit,
      reason: 'restock to seed baseline',
    });
    const res = http.post(`${inv}/receipts`, body, staffJson);
    const applied = res.status === 201 && ((res.json() || {}).applied === true);
    if (applied) {
      receipts.add(1);
      received.add(deficit);
      gAfter[sku].add(want);
    } else {
      failures.add(1);
      gAfter[sku].add(have);
      console.error(`restock ${sku}: HTTP ${res.status} ${String(res.body || '').slice(0, 200)}`);
    }
  }
}

export function handleSummary(data) {
  const g = (name) => {
    const m = data.metrics[name];
    return m && m.values && m.values.value !== undefined ? m.values.value : null;
  };
  const units = (data.metrics.stock_units_received && data.metrics.stock_units_received.values.count) || 0;
  const posted = (data.metrics.stock_receipts_posted && data.metrics.stock_receipts_posted.values.count) || 0;
  const failed = (data.metrics.stock_receipts_failed && data.metrics.stock_receipts_failed.values.count) || 0;

  const lines = [
    `### Stock restock — gate \`${target.gate}\``,
    '',
    '| SKU | on_hand before | baseline | on_hand after |',
    '|---|---:|---:|---:|',
  ];
  for (const sku of Object.keys(BASELINE)) {
    const b = g(`stock_before_${sku}`);
    const a = g(`stock_after_${sku}`);
    lines.push(`| ${sku} | ${b === null ? '?' : b} | ${BASELINE[sku]} | ${a === null ? '?' : a} |`);
  }
  lines.push('', `Receipts posted: **${posted}** · units received: **${units}** · failed: **${failed}**`, '');

  if (posted === 0 && failed === 0) {
    lines.push('Nothing to do — every SKU already sits at or above the seed baseline.', '');
  }
  if (failed > 0) {
    lines.push(
      `**${failed} SKU could not be topped up.** A 401/403 means the staff token or the ` +
        `edge JWT filter, not stock; a 400 means the baseline names a SKU this warehouse ` +
        `does not track.`,
      ''
    );
  }

  const md = lines.join('\n');
  return { stdout: md, [`scripts/k6/out/restock-${target.gate}.md`]: md };
}
