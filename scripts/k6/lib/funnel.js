// The checkout funnel, once.
//
// Four scripts drive the same six requests to turn a cart into an order, and
// they were four copies until one of them exposed a bug all four shared.
//
// The bug is worth stating, because it is invisible until it bites. Creating a
// checkout session answers **201 with a new session** on a clean identity, and
// **200 with the EXISTING session** when that identity already has an open one
// -- the services hold one active session per user as a partial unique index.
// So a run that leaves a session behind hands the next run a session built from
// a different cart, and every price assertion after that is measuring the wrong
// basket. It fails as "the total is not what I engineered", which reads like a
// pricing bug in the platform.
//
// The audit's shell rows try to handle this by probing for a stale session
// before populating the cart -- but an empty cart answers `409 Cart is empty`,
// so the probe can never see the session it is looking for. `freshSession`
// inverts the order: populate first, then treat a 200 as "this is somebody
// else's session" and replace it.

import http from 'k6/http';

const json = (extra) => Object.assign({ 'Content-Type': 'application/json' }, extra);

export function clearCart(base, auth) {
  return http.del(`${base}/cart/v1/private/cart`, null, auth);
}

export function addItem(base, auth, item) {
  return http.post(`${base}/cart/v1/private/cart`, JSON.stringify(item), {
    headers: json(auth.headers),
  });
}

// Returns { id, res, adopted } where `adopted` records that a session already
// existed. Call it only after the cart holds what this run intends to buy.
export function freshSession(base, auth) {
  const sessions = `${base}/checkout/v1/private/checkout/sessions`;
  let res = http.post(sessions, null, auth);

  // 200 means an open session was returned rather than created. It belongs to
  // whatever the identity was doing last, so discard it and ask again.
  if (res.status === 200) {
    const stale = (res.json() || {}).id;
    if (stale) http.del(`${sessions}/${stale}`, null, auth);
    res = http.post(sessions, null, auth);
    return { id: (res.json() || {}).id, res: res, adopted: true };
  }
  return { id: (res.json() || {}).id, res: res, adopted: false };
}

// Address, then shipping, then payment -- and the order matters: shipping_fee
// and tax stay 0 until the shipping method is set, so a total read before that
// step is the subtotal wearing the name of a total.
export function priceSession(base, auth, sid, opts) {
  const s = `${base}/checkout/v1/private/checkout/sessions/${sid}`;
  const o = opts || {};
  http.put(
    `${s}/address`,
    JSON.stringify(
      o.address || { full_name: 'Audit', line1: '1 Main St', city: 'HN', country: 'VN' }
    ),
    { headers: json(auth.headers) }
  );
  http.put(`${s}/shipping`, JSON.stringify({ shipping_method: o.shipping || 'standard' }), {
    headers: json(auth.headers),
  });
  http.put(
    `${s}/payment`,
    JSON.stringify({ payment_method_token: o.token || 'tok_visa_ok' }),
    { headers: json(auth.headers) }
  );
  return s;
}

export function readSession(base, auth, sid) {
  return http.get(`${base}/checkout/v1/private/checkout/sessions/${sid}`, auth);
}

export function confirmSession(base, auth, sid, key) {
  const s = `${base}/checkout/v1/private/checkout/sessions/${sid}`;
  return http.post(`${s}/confirm`, null, {
    headers: json(Object.assign({ 'Idempotency-Key': key }, auth.headers)),
  });
}

export function deleteSession(base, auth, sid) {
  return http.del(`${base}/checkout/v1/private/checkout/sessions/${sid}`, null, auth);
}
