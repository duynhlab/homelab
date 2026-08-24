// The order saga, end to end, asserted over HTTP only.
//
// The Kind gate proves this with `kubectl exec ... temporal workflow describe`
// (K4.10) and reads the worker's Current version the same way (K1.7). Both are
// reachable over plain HTTP: the Temporal UI serves a JSON API that carries the
// workflow's versioning block AND the deployment's routing config. Asserting
// against the routing config is in fact stronger than reading the Kubernetes
// CRD's status -- the routing config is what the server actually dispatches on,
// while the CRD reports what the controller believes it asked for.
//
// The chain this proves, in one run:
//
//   stock is armed  ->  an order confirms  ->  the saga reaches COMPLETED
//     ->  it ran Pinned  ->  on the deployment the controller composed
//     ->  at the build id that is Current, with no half-finished ramp
//
// Arming the stock matters and is not incidental. A single SKU carries finite
// seeded stock, so a repeated run eventually meets `insufficient stock to
// reserve` and the saga fails -- correctly, refusing to oversell. Left unarmed,
// this script would degrade run over run and read as a broken saga. The receipt
// endpoint is staff-only, so this doubles as a live check that /protected/ works.
//
//   GATE=kind k6 run scripts/k6/saga.js

import http from 'k6/http';
import { sleep } from 'k6';
import { target, tlsOptions, identityFor } from './lib/config.js';
import { bearer } from './lib/auth.js';
import { rowCheck, rowThresholds, evidenceTable } from './lib/rows.js';
import { clearCart, addItem, freshSession, priceSession, confirmSession } from './lib/funnel.js';

// Per-gate, from lib/config.js. It used to default to the Kind hostname no
// matter which gate was running, so on compose SG.3 polled a URL that does not
// resolve and reported "never seen" while Temporal had the workflow Completed.
const TEMPORAL = target.temporalUI;
const TQ_NAMESPACE = __ENV.TEMPORAL_NAMESPACE || 'mop';
const DEPLOYMENT = __ENV.WORKER_DEPLOYMENT || 'order/order-fulfillment';
const SKU = __ENV.SKU || '1';
const DEADLINE = Number(__ENV.SAGA_DEADLINE || 60);

const ROWS = ['SG.1', 'SG.2', 'SG.3', 'SG.4'];

export const options = Object.assign(
  { vus: 1, iterations: 1, thresholds: rowThresholds(ROWS) },
  tlsOptions
);

function jsonHeaders(extra) {
  return Object.assign({ 'Content-Type': 'application/json' }, extra);
}

export default function () {
  const B = target.base;
  const staff = bearer('staff', identityFor('staff', 0));
  const who = identityFor('customer', 0);
  const auth = bearer('customer', who);

  // SG.1 -- arm the stock through the staff surface. 201 on a new command,
  // 200 on a replay: the endpoint is idempotent on command_id.
  const receipt = http.post(
    `${B}/inventory/v1/protected/receipts`,
    JSON.stringify({
      command_id: `saga-arm-${Date.now()}`,
      sku_id: SKU,
      warehouse_id: 1,
      quantity: 5,
      reason: 'k6 saga arm',
    }),
    { headers: jsonHeaders(staff.headers) }
  );
  rowCheck('SG.1', receipt, {
    'stock is armed through /protected/': (r) => r.status === 201 || r.status === 200,
  });

  // SG.2 -- drive the funnel and confirm.
  clearCart(B, auth);
  addItem(B, auth, {
    product_id: SKU,
    product_name: 'Wireless Mouse',
    product_price: 29.99,
    quantity: 1,
  });
  const opened = freshSession(B, auth);
  const sid = opened.id;
  priceSession(B, auth, sid, { address: { full_name: 'Saga', line1: '1 Main St', city: 'HN', country: 'VN' } });
  const confirm = confirmSession(B, auth, sid, `saga-${Date.now()}`);
  const orderId = confirm.json('order_id') || confirm.json('id');
  rowCheck('SG.2', confirm, {
    'confirm creates an order': (r) => r.status === 201 || r.status === 200,
    'the response names the order': () => !!orderId,
  });
  if (!orderId) return;

  // SG.3 -- the saga reaches a terminal state on its own. Nothing is nudged
  // between confirm and here; that is the whole claim.
  const wid = `order-fulfillment-${orderId}`;
  const url = `${TEMPORAL}/api/v1/namespaces/${TQ_NAMESPACE}/workflows/${wid}`;
  let info = null;
  let status = 'never seen';
  for (let waited = 0; waited < DEADLINE; waited += 3) {
    const res = http.get(url);
    if (res.status === 200) {
      info = res.json('workflowExecutionInfo');
      status = (info && info.status) || 'unknown';
      if (status !== 'WORKFLOW_EXECUTION_STATUS_RUNNING') break;
    }
    sleep(3);
  }
  rowCheck('SG.3', info, {
    [`the saga completes within ${DEADLINE}s (saw ${status})`]: () =>
      status === 'WORKFLOW_EXECUTION_STATUS_COMPLETED',
  });

  // SG.4 -- and it ran on the version the server is actually routing to. The
  // build id is derived from the whole pod template and written down nowhere in
  // git, so this compares two server-side facts rather than a manifest guess.
  const routing = http.get(
    `${TEMPORAL}/api/v1/namespaces/${TQ_NAMESPACE}/worker-deployments`
  );
  let current = null;
  let ramping = null;
  const wds = routing.status === 200 ? routing.json('workerDeployments') || [] : [];
  for (const wd of wds) {
    if (wd.name !== DEPLOYMENT) continue;
    const rc = wd.routingConfig || {};
    current = (rc.currentDeploymentVersion || {}).buildId || null;
    ramping = rc.rampingVersion || null;
  }
  const vi = (info && info.versioningInfo) || {};
  const ranOn = (vi.deploymentVersion || {}).buildId || null;

  // SG.4 is KIND-ONLY. Worker versioning comes from the temporal-worker-
  // controller (RFC-0026 / ADR-054), which compose does not run: measured there,
  // /worker-deployments returns `{}` and a completed workflow carries no
  // versioningInfo at all. Asserting it on compose fails for a capability the
  // stack was never given, so the row is left unrun and counted as such.
  if (target.gate !== 'kind') return;

  rowCheck('SG.4', info, {
    'behavior is Pinned': () => vi.behavior === 'VERSIONING_BEHAVIOR_PINNED',
    [`deployment is ${DEPLOYMENT}`]: () =>
      (vi.deploymentVersion || {}).deploymentName === DEPLOYMENT,
    'a build id is recorded': () => !!ranOn,
    [`it ran on the Current build id (${ranOn} vs ${current})`]: () =>
      !!current && ranOn === current,
    'no half-finished ramp': () => !ramping,
  });
}

export function handleSummary(data) {
  const md = evidenceTable(data, ROWS, `Order saga — gate \`${target.gate}\``);
  return { stdout: md, [`scripts/k6/out/saga-${target.gate}.md`]: md };
}
