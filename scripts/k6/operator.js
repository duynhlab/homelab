// A20 -- the operator resolve path, and the only row that proves a saga can
// park a real order for a human.
//
// Its own file because it is the largest row in either audit: ~24 requests, two
// bounded waits, and an arming sequence threaded through the middle rather than
// hoisted to the top. Nothing is faked with SQL. The order is parked through
// the real compensation path, which is the whole point -- a row that writes
// `manual_review` into the database proves the column exists, not that the saga
// can reach it.
//
// How the park is provoked: mockpay declines a refund whose amount ends in
// certain cents while still allowing the original charge, and `order` maps a
// declined refund to a NON-retryable error, which is what parks the episode.
// So the row must engineer an order total whose cents land on the declining
// suffix, and that means solving for the subtotal rather than picking a price.
//
//   GATE=compose k6 run scripts/k6/operator.js
//
// NOT YET RUN against a live stack -- written from the audit row, verified only
// for parse and imports. Row A20 of local-stack/docs/e2e-audit.md.

import http from 'k6/http';
import { sleep } from 'k6';
import { target, tlsOptions, identityFor } from './lib/config.js';
import { bearer } from './lib/auth.js';
import { rowCheck, rowThresholds, evidenceTable } from './lib/rows.js';
import { clearCart, addItem, freshSession, priceSession, readSession, confirmSession } from './lib/funnel.js';

const STAFF_SUB = 'd0e00000-0000-4000-8000-000000000001';
const DECLINE_SUFFIX = Number(__ENV.DECLINE_SUFFIX || 7); // refund-decline cents
const SHIP_FEE_CENTS = 300; // standard / VN
const TAX_BPS = 800; // 8% for VN
const ROWS = ['A20'];

export const options = Object.assign(
  { vus: 1, iterations: 1, thresholds: rowThresholds(ROWS) },
  tlsOptions
);

function jsonHeaders(extra) {
  return Object.assign({ 'Content-Type': 'application/json' }, extra);
}

// Solve for a subtotal whose ORDER TOTAL ends in the declining cents. Worked in
// integer cents rather than floats, because the thing being matched is two
// decimal digits and float arithmetic is exactly how you lose them.
//
// The solved price is a starting point, not an assertion: the row still checks
// the total the session actually quotes. If shipping or the tax rule ever
// changes, the check fails loudly instead of the row silently testing a refund
// that was never declined.
function solveSubtotal() {
  for (let cents = 1000; cents < 10000; cents++) {
    const taxable = cents + SHIP_FEE_CENTS;
    const tax = Math.round((taxable * TAX_BPS) / 10000);
    const total = taxable + tax;
    if (total % 100 === DECLINE_SUFFIX) return cents / 100;
  }
  return null;
}

export default function () {
  const B = target.base;
  const staff = bearer('staff', identityFor('staff', 0));
  const staffJson = { headers: jsonHeaders(staff.headers) };
  // carol, so this row does not adopt the checkout session of any other row --
  // one active session per user is a partial unique index.
  const carol = identityFor('customer', 2);
  const auth = bearer('customer', carol);
  const authJson = { headers: jsonHeaders(auth.headers) };

  const price = solveSubtotal();
  if (price === null) {
    rowCheck('A20', null, { 'a declining subtotal exists': () => false });
    return;
  }
  // Seconds, not milliseconds: `order` refuses a product_name of 12+ digits as
  // suspected card data.
  const stamp = Math.floor(Date.now() / 1000);
  const name = `Refund Trap ${stamp}`;

  // --- arm: a product nobody else holds, published, with stock -------------
  const prot = `${B}/product/v1/protected/products`;
  const created = http.post(
    prot,
    JSON.stringify({ name: name, price: price, category: 'Electronics' }),
    staffJson
  );
  const pid = (created.json() || {}).id;
  if (!pid) {
    rowCheck('A20', created, { 'the trap product was created': () => false });
    return;
  }
  http.post(`${prot}/${pid}/publish`, null, staff);
  const receipt = http.post(
    `${B}/inventory/v1/protected/receipts`,
    JSON.stringify({
      command_id: `a20-rcpt-${stamp}`,
      sku_id: pid,
      warehouse_id: 1,
      quantity: 5,
      reason: 'a20 arm',
    }),
    staffJson
  );
  rowCheck('A20', receipt, { 'stock is armed': (r) => r.status === 201 });

  // --- drive the funnel as carol -------------------------------------------
  clearCart(B, auth);
  addItem(B, auth, {
    product_id: pid,
    product_name: name,
    product_price: price,
    quantity: 1,
  });
  const opened = freshSession(B, auth);
  const sid = opened.id;
  if (!sid) {
    rowCheck('A20', opened.res, { 'a session opened': () => false });
    return;
  }
  priceSession(B, auth, sid, { address: { full_name: 'Carol', line1: '1 Main St', city: 'HN', country: 'VN' } });

  // The premise of the whole row: if the total's cents are not the declining
  // suffix, the refund later SUCCEEDS and the order never parks.
  const quoted = readSession(B, auth, sid);
  const total = ((quoted.json() || {}).total !== undefined ? quoted.json().total : null);
  rowCheck('A20', quoted, {
    [`the total's cents are ${DECLINE_SUFFIX} (got ${total})`]: () =>
      total !== null && Math.round(Number(total) * 100) % 100 === DECLINE_SUFFIX,
  });

  const confirm = confirmSession(B, auth, sid, `a20-${stamp}`);
  const oid = (confirm.json() || {}).order_id || (confirm.json() || {}).id;
  if (!oid) {
    rowCheck('A20', confirm, { 'confirm created an order': () => false });
    return;
  }
  const order = `${B}/order/v1/protected/orders/${oid}`;

  // --- wait for a cancellable state ---------------------------------------
  // A user may open a cancellation episode from `confirmed` or `completed`
  // only -- never from `pending`.
  let status = pollStatus(order, staff, ['confirmed', 'completed'], 20);
  rowCheck('A20', null, {
    [`the order becomes cancellable (saw ${status})`]: () =>
      status === 'confirmed' || status === 'completed',
  });

  const cancel = http.post(`${B}/order/v1/private/orders/${oid}/cancel`, null, auth);
  rowCheck('A20', cancel, { 'cancel opens an episode with 202': (r) => r.status === 202 });

  // --- wait for the park ---------------------------------------------------
  status = pollStatus(order, staff, ['manual_review'], 40);
  rowCheck('A20', null, {
    // `failed` means the refund SUCCEEDED (wrong cents, or mockpay stubbed
    // in-memory); `cancelling` means compensation is still retrying;
    // `confirmed` means the cancel never opened an episode.
    [`the order parks in manual_review (saw ${status})`]: () => status === 'manual_review',
  });

  const view = http.get(order, staff);
  const c = view.json() || {};
  const pay = c.payment || {};
  rowCheck('A20', view, {
    'the case view carries a version': () => Number(c.version) > 0,
    'and a status history': () => Array.isArray(c.status_history),
    'and a captured or partially refunded payment': () =>
      pay.status === 'captured' || pay.status === 'partially_refunded',
  });
  const version = Number(c.version);

  // --- the resolve contract, negatives first -------------------------------
  const resolve = (body, who) =>
    http.post(`${order}/resolve`, JSON.stringify(body), {
      headers: jsonHeaders((who || staff).headers),
    });

  rowCheck(
    'A20',
    resolve({ target: 'cancelled', version: 1, reason: 'WRITTEN_OFF', note: 'x' }, auth),
    { 'a customer token cannot resolve': (r) => r.status === 401 }
  );
  rowCheck('A20', resolve({ target: 'cancelled', version: version, reason: 'WRITTEN_OFF', note: '' }), {
    'an empty note is 400': (r) => r.status === 400,
  });
  rowCheck(
    'A20',
    resolve({ target: 'cancelled', version: version, reason: 'CUSTOMER_REQUEST', note: 'n' }),
    {
      // CUSTOMER_REQUEST opens an episode; it does not resolve one.
      'a foreign reason is 400': (r) => r.status === 400,
      'with code VALIDATION_ERROR': (r) => (r.json() || {}).code === 'VALIDATION_ERROR',
    }
  );
  rowCheck('A20', resolve({ target: 'pending', version: version, reason: 'WRITTEN_OFF', note: 'n' }), {
    'an illegal target is 409': (r) => r.status === 409,
    'with code INVALID_TRANSITION': (r) => (r.json() || {}).code === 'INVALID_TRANSITION',
  });
  rowCheck(
    'A20',
    resolve({ target: 'cancelled', version: version + 5, reason: 'WRITTEN_OFF', note: 'n' }),
    {
      'a stale version is 409': (r) => r.status === 409,
      'with code VERSION_CONFLICT': (r) => (r.json() || {}).code === 'VERSION_CONFLICT',
    }
  );

  // --- and the resolve itself ---------------------------------------------
  // actor_id names somebody else on purpose: it must be ignored in favour of
  // the token's subject.
  const body = {
    target: 'cancelled',
    version: version,
    reason: 'WRITTEN_OFF',
    note: 'a20: refund permanently declined by the provider; closing',
    actor_id: 'ignored-by-design',
  };
  const applied = resolve(body);
  rowCheck('A20', applied, {
    'the resolve is 201': (r) => r.status === 201,
    'and reports applied': (r) => (r.json() || {}).applied === true,
  });
  const replay = resolve(body);
  rowCheck('A20', replay, {
    'the replay is 200': (r) => r.status === 200,
    'and reports not applied': (r) => (r.json() || {}).applied === false,
  });
  rowCheck(
    'A20',
    resolve({ target: 'failed', version: version + 1, reason: 'WRITTEN_OFF', note: 'n' }),
    { 'a further resolve is 409 -- no longer parked': (r) => r.status === 409 }
  );

  const after = http.get(order, staff);
  const done = after.json() || {};
  const ops = (done.status_history || []).filter((r) => r.actor_type === 'OPERATOR');
  rowCheck('A20', after, {
    'the order is cancelled': () => done.status === 'cancelled',
    'exactly one OPERATOR entry': () => ops.length === 1,
    'its reason is WRITTEN_OFF': () => ops.length === 1 && ops[0].reason_code === 'WRITTEN_OFF',
    'its actor is the token subject': () => ops.length === 1 && ops[0].actor_id === STAFF_SUB,
    'its note is the one that was sent': () =>
      ops.length === 1 && String(ops[0].note || '').indexOf('permanently declined') !== -1,
  });
}

function pollStatus(orderUrl, staff, wanted, attempts) {
  let status = 'never read';
  for (let i = 0; i < attempts; i++) {
    const res = http.get(orderUrl, staff);
    if (res.status === 200) {
      status = (res.json() || {}).status || 'unknown';
      if (wanted.indexOf(status) !== -1) return status;
    }
    sleep(3);
  }
  return status;
}

export function handleSummary(data) {
  const md = evidenceTable(data, ROWS, `Operator resolve — gate \`${target.gate}\``);
  return { stdout: md, [`scripts/k6/out/operator-${target.gate}.md`]: md };
}
