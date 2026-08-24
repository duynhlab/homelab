// The /protected/ Backoffice surface: five rows that share one staff token.
//
// A17 mints it and A18/A19/A21/A22 spend it, which is why they live together. The
// shape of every row here is the same three-part guard chain: the edge checks
// the workforce issuer coarsely, the service's own verifier is authoritative,
// and only then does a role gate apply. A customer token is wrong-issuer at the
// EDGE and never reaches the role gate -- that is asserted, not assumed,
// because a 403 instead of a 401 would mean the edge let it through.
//
// Every command surface here is idempotent on a body field rather than on an
// `Idempotency-Key` header: inventory uses `command_id`, the catalog uses
// `version`. The command ids below are unique per run on purpose. With a fixed
// id, the "201 applied:true" half only holds on a never-audited stack and every
// re-run replays instead -- which reads as a broken create path when it is the
// idempotency working.
//
//   GATE=compose k6 run scripts/k6/staff.js
//
// Rows A17, A18, A19, A21 and A22 of local-stack/docs/e2e-audit.md.

import http from 'k6/http';
import { target, tlsOptions, identityFor } from './lib/config.js';
import { bearer } from './lib/auth.js';
import { rowCheck, rowThresholds, evidenceTable } from './lib/rows.js';
import { clearCart, addItem, freshSession, deleteSession } from './lib/funnel.js';

// duyne's subject in the workforce realm. Three rows assert that the actor
// recorded in a ledger is the TOKEN's subject and never the body's.
const STAFF_SUB = 'd0e00000-0000-4000-8000-000000000001';

const ROWS = ['A17', 'A18', 'A19', 'A21', 'A22'];

export const options = Object.assign(
  { vus: 1, iterations: 1, thresholds: rowThresholds(ROWS) },
  tlsOptions
);

function jsonHeaders(extra) {
  return Object.assign({ 'Content-Type': 'application/json' }, extra);
}

// Seconds, not milliseconds. `order` refuses a product_name carrying 12 or
// more digits as suspected card data, and Date.now() is already 13.
const stamp = () => Math.floor(Date.now() / 1000);

export default function () {
  const B = target.base;
  const staff = bearer('staff', identityFor('staff', 0));
  const customer = bearer('customer', identityFor('customer', 0));
  const staffJson = { headers: jsonHeaders(staff.headers) };

  a17(B, staff, customer, staffJson);
  a18(B, staff, customer);
  a19(B, staff, customer, staffJson);
  a21(B, staff, staffJson);
  a22(B, staff);
}

// --- A17: the protected surface, and its first command -----------------------

function a17(B, staff, customer, staffJson) {
  const inv = `${B}/inventory/v1/protected`;

  rowCheck('A17', http.get(`${inv}/balances`), {
    'tokenless is 401 at the edge': (r) => r.status === 401,
  });
  // Audience scoping: nothing but /protected is routed for inventory, so the
  // /private path is not a weaker door -- it is not a door.
  rowCheck('A17', http.get(`${B}/inventory/v1/private/balances`, customer), {
    'the bare /private route is 404': (r) => r.status === 404,
  });
  rowCheck('A17', http.get(`${inv}/balances`, customer), {
    'a customer token is 401, not 403': (r) => r.status === 401,
  });

  const balances = http.get(`${inv}/balances?page_size=3`, staff);
  rowCheck('A17', balances, {
    'staff can list balances': (r) => r.status === 200,
    'the list carries items': (r) => Array.isArray((r.json() || {}).items),
  });

  const body = JSON.stringify({
    command_id: `a17-rcpt-${stamp()}`,
    sku_id: 'A17-SKU',
    warehouse_id: 1,
    quantity: 7,
    reason: 'PO-A17',
  });
  const receipt = http.post(`${inv}/receipts`, body, staffJson);
  rowCheck('A17', receipt, {
    'a new receipt is 201': (r) => r.status === 201,
    'and reports applied': (r) => (r.json() || {}).applied === true,
  });
  // The exact same body again -- this run's id, so both halves hold on a fresh
  // stack and on a re-run.
  const replay = http.post(`${inv}/receipts`, body, staffJson);
  rowCheck('A17', replay, {
    'the replay is 200': (r) => r.status === 200,
    'and reports not applied': (r) => (r.json() || {}).applied === false,
  });

  const over = http.post(
    `${inv}/adjustments`,
    JSON.stringify({
      command_id: `a17-adj-${stamp()}`,
      sku_id: 'A17-SKU',
      warehouse_id: 1,
      delta: -9999,
      reason: 'a17',
    }),
    staffJson
  );
  rowCheck('A17', over, {
    'an over-adjustment is 409': (r) => r.status === 409,
    'with code STOCK_UNAVAILABLE': (r) => (r.json() || {}).code === 'STOCK_UNAVAILABLE',
  });

  const moves = http.get(`${inv}/movements?sku_id=A17-SKU`, staff);
  rowCheck('A17', moves, {
    'the ledger records the token subject as actor': (r) => {
      const items = (r.json() || {}).items || [];
      return items.length > 0 && items.every((m) => m.actor === STAFF_SUB);
    },
  });
}

// --- A18: the protected read fan-out ----------------------------------------

function a18(B, staff, customer) {
  const surfaces = [
    ['order', 'orders'],
    ['payment', 'payments'],
    ['shipping', 'shipments'],
    ['user', 'users'],
  ];
  for (const [svc, resource] of surfaces) {
    const path = `${B}/${svc}/v1/protected/${resource}`;
    rowCheck('A18', http.get(`${path}?page_size=1`, staff), {
      [`${svc} staff list is 200`]: (r) => r.status === 200,
    });
    rowCheck('A18', http.get(path, customer), {
      [`${svc} customer token is 401 wrong-issuer`]: (r) => r.status === 401,
    });
  }
  rowCheck('A18', http.get(`${B}/payment/v1/protected/reconciliations/runs?page_size=1`, staff), {
    'reconciliation runs list is 200': (r) => r.status === 200,
  });
}

// --- A19: the first protected surface that WRITES ---------------------------

function a19(B, staff, customer, staffJson) {
  const prot = `${B}/product/v1/protected/products`;
  const name = `Audit Widget ${stamp()}`;

  rowCheck('A19', http.get(`${prot}?page_size=1`, staff), {
    'staff can list the catalog': (r) => r.status === 200,
  });
  rowCheck('A19', http.get(prot, customer), {
    'a customer token is 401 wrong-issuer': (r) => r.status === 401,
  });

  // actor_sub is supplied and must be ignored: the audit trail carries the
  // token's subject, never the body's.
  const created = http.post(
    prot,
    JSON.stringify({
      name: name,
      price: 19.99,
      category: 'Electronics',
      actor_sub: 'ignored-by-design',
    }),
    staffJson
  );
  const p = created.json() || {};
  const id = p.id;
  rowCheck('A19', created, {
    'a new product is DRAFT': () => p.status === 'DRAFT',
    'and starts at version 1': () => p.version === 1,
  });
  if (!id) return;

  rowCheck('A19', http.get(`${B}/product/v1/public/products/${id}`), {
    'a DRAFT is invisible publicly': (r) => r.status === 404,
  });
  // A duplicate name is the conflict that makes a retried create safe.
  rowCheck('A19', http.post(prot, JSON.stringify({ name: name, price: 1 }), staffJson), {
    'a duplicate name is 409': (r) => r.status === 409,
  });

  rowCheck('A19', http.post(`${prot}/${id}/publish`, null, staff), {
    'publish is 200': (r) => r.status === 200,
  });
  rowCheck('A19', http.get(`${B}/product/v1/public/products/${id}`), {
    'the product is now public': (r) => r.status === 200,
  });
  // A second publish is a refused edge, not a no-op.
  rowCheck('A19', http.post(`${prot}/${id}/publish`, null, staff), {
    're-publish is 409': (r) => r.status === 409,
    'with code INVALID_TRANSITION': (r) => (r.json() || {}).code === 'INVALID_TRANSITION',
  });

  rowCheck(
    'A19',
    http.put(
      `${prot}/${id}`,
      JSON.stringify({
        name: `${name} edited`,
        price: 21.5,
        category: 'Electronics',
        version: 2,
        reason: 'audit',
      }),
      staffJson
    ),
    { 'an edit at the current version is 200': (r) => r.status === 200 }
  );
  // Optimistic concurrency: the same version cannot win twice.
  rowCheck(
    'A19',
    http.put(
      `${prot}/${id}`,
      JSON.stringify({ name: 'overwrite', price: 99, version: 2 }),
      staffJson
    ),
    {
      'a stale edit is 409': (r) => r.status === 409,
      'with code VERSION_CONFLICT': (r) => (r.json() || {}).code === 'VERSION_CONFLICT',
    }
  );

  rowCheck('A19', http.post(`${prot}/${id}/archive`, null, staff), {
    'archive is 200': (r) => r.status === 200,
  });
  // The deliberate asymmetry: the page is gone, but a cart still holding this
  // product must keep pricing correctly.
  rowCheck('A19', http.get(`${B}/product/v1/public/products/${id}`), {
    'the archived page is 404': (r) => r.status === 404,
  });

  const audit = http.get(`${prot}/${id}/audit`, staff);
  const rows = (audit.json() || {}).items || [];
  const actions = rows.map((r) => r.action);
  const actors = rows.map((r) => r.actor_sub);
  rowCheck('A19', audit, {
    'the newest audit action is ARCHIVE': () => actions[0] === 'ARCHIVE',
    'the trail includes CREATE': () => actions.indexOf('CREATE') !== -1,
    'every actor is the token subject': () =>
      actors.length > 0 && actors.every((a) => a === STAFF_SUB),
  });

  rowCheck('A19', http.get(`${B}/product/v1/protected/categories?page_size=5`, staff), {
    'categories list is 200': (r) => r.status === 200,
  });
  // GAP: the audit's own comment promises "list + create + the unique-name
  // conflict" for categories, but only the list was ever coded. Not invented
  // here -- recorded in docs/testing/k6.md so it is decided rather than
  // silently filled in.
}

// --- A21: an untracked SKU is a conflict, not an outage ---------------------

function a21(B, staff, staffJson) {
  const david = identityFor('customer', 3);
  const auth = bearer('customer', david);
  const name = `Untracked Widget ${stamp()}`;
  const prot = `${B}/product/v1/protected/products`;

  const created = http.post(
    prot,
    JSON.stringify({ name: name, price: 12.5, category: 'Electronics' }),
    staffJson
  );
  const pid = (created.json() || {}).id;
  if (!pid) {
    rowCheck('A21', created, { 'the trap product was created': () => false });
    return;
  }
  http.post(`${prot}/${pid}/publish`, null, staff);
  // No receipt. That omission IS the row: the SKU is published and orderable
  // in the catalog while inventory has never heard of it.

  clearCart(B, auth);
  addItem(B, auth, { product_id: pid, product_name: name, product_price: 12.5, quantity: 1 });

  const blocked = http.post(`${B}/checkout/v1/private/checkout/sessions`, null, auth);
  const body = String(blocked.body || '');
  rowCheck('A21', blocked, {
    'the session is refused 409': (r) => r.status === 409,
    'with ITEM_NOT_ORDERABLE': () => body.indexOf('ITEM_NOT_ORDERABLE') !== -1,
    // Nothing to requote -- no session exists yet -- so there is no Retry-After.
    'and no Retry-After': (r) => !r.headers['Retry-After'] && !r.headers['retry-after'],
    // The SKU ids stay in the log and the span; the body stays opaque.
    'and an opaque body': () => body.indexOf('does not track') === -1,
  });

  const receipt = http.post(
    `${B}/inventory/v1/protected/receipts`,
    JSON.stringify({
      command_id: `a21-rcpt-${stamp()}`,
      sku_id: pid,
      warehouse_id: 1,
      quantity: 5,
      reason: 'a21 recovery',
    }),
    staffJson
  );
  rowCheck('A21', receipt, { 'the recovery receipt is 201': (r) => r.status === 201 });

  const recovered = freshSession(B, auth);
  rowCheck('A21', recovered.res, { 'the same basket now opens a session': () => !!recovered.id });

  if (recovered.id) deleteSession(B, auth, recovered.id);
  clearCart(B, auth);
}

// --- A22: the six reads behind the portal's attention cards ------------------
//
// B6 looks at the five cards and reads a numeral off each. What it cannot do is
// say WHICH query broke when a card shows a dash, and it cannot run at all
// without a browser. These are the exact six reads the dashboard issues
// (admin-service `src/routes/_authenticated/index.tsx`) -- same paths, same
// params -- so a renamed filter or a dropped `total_items` fails here with the
// endpoint named instead of surfacing as a blank card.
//
// The last assertion is the one that earns the row. A `status` order-service
// does not know is a 400, which proves the two order cards are really FILTERED.
// Were an unknown status ignored instead, `manual_review` and `cancelling`
// would both report the total order count -- two plausible numbers, both wrong,
// and not one non-200 anywhere to reveal it.

function a22(B, staff) {
  const cards = [
    ['low / out of stock', `${B}/inventory/v1/protected/balances?page=1&page_size=1&low_stock=true`],
    ['manual review', `${B}/order/v1/protected/orders?page=1&page_size=1&status=manual_review`],
    ['cancelling', `${B}/order/v1/protected/orders?page=1&page_size=1&status=cancelling`],
    ['unresolved attempts', `${B}/payment/v1/protected/attempts/open?page=1&page_size=1`],
    ['recon discrepancies', `${B}/payment/v1/protected/reconciliations/runs?page=1&page_size=1`],
  ];

  for (const [label, url] of cards) {
    rowCheck('A22', http.get(url, staff), {
      [`the ${label} card's query is 200`]: (r) => r.status === 200,
      [`the ${label} card gets a numeric total_items`]: (r) =>
        typeof (r.json() || {}).total_items === 'number',
    });
  }

  // The recent-orders panel is a list rather than a count, so page_size is the
  // thing to hold it to. A null `items` on an empty stack is a legal 200.
  rowCheck('A22', http.get(`${B}/order/v1/protected/orders?page=1&page_size=5`, staff), {
    'the recent-orders panel is 200': (r) => r.status === 200,
    'the recent-orders panel honours page_size=5': (r) => ((r.json() || {}).items || []).length <= 5,
  });

  rowCheck('A22', http.get(`${B}/order/v1/protected/orders?status=not_a_status`, staff), {
    'an unknown status is 400, so the order cards are genuinely filtered': (r) => r.status === 400,
  });
}

export function handleSummary(data) {
  const md = evidenceTable(data, ROWS, `Protected staff surface — gate \`${target.gate}\``);
  return { stdout: md, [`scripts/k6/out/staff-${target.gate}.md`]: md };
}
