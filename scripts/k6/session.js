// Realm session lifecycle: refresh rotation, reuse detection, and logout.
//
// A separate file because these two rows are destructive in a way no other row
// is. A4 deliberately replays a spent refresh token, and the realm answers by
// killing the whole SESSION rather than merely refusing the call
// (`revokeRefreshToken=true` + `refreshTokenMaxReuse=0`). A5 then has to mint
// again before it can test logout. Run them inside another script and every
// later row holding that identity starts failing for a reason that has nothing
// to do with what it asserts.
//
// These talk to the realm directly, not through the edge: the token endpoint is
// Keycloak's own contract, and 400 `invalid_grant` is OAuth2's error shape, not
// an edge rejection.
//
//   GATE=compose k6 run scripts/k6/session.js
//
// NOT YET RUN against a live stack -- written from the audit rows, verified only
// for parse and imports. Rows A4 and A5 of local-stack/docs/e2e-audit.md.

import http from 'k6/http';
import { target, tlsOptions, identityFor, REALMS } from './lib/config.js';
import { tokenResponse, forget } from './lib/auth.js';
import { rowCheck, rowThresholds, evidenceTable } from './lib/rows.js';

const ROWS = ['A4', 'A5'];
const OIDC = `${target.kc}/realms/${REALMS.customer.realm}/protocol/openid-connect`;

export const options = Object.assign(
  { vus: 1, iterations: 1, thresholds: rowThresholds(ROWS) },
  tlsOptions
);

function refresh(rt) {
  return http.post(`${OIDC}/token`, {
    grant_type: 'refresh_token',
    client_id: REALMS.customer.clientId,
    refresh_token: rt,
  });
}

function logout(rt) {
  return http.post(`${OIDC}/logout`, {
    client_id: REALMS.customer.clientId,
    refresh_token: rt,
  });
}

export default function () {
  const alice = identityFor('customer', 0);

  // --- A4: rotation, then reuse detection ---------------------------------
  const first = tokenResponse('customer', alice);
  const rt = first.refresh_token;

  const rotated = refresh(rt);
  const rt2 = rotated.json('refresh_token');
  rowCheck('A4', rotated, {
    'refresh returns a new token': (r) => r.status === 200,
    'the refresh token rotated': () => !!rt2 && rt2 !== rt,
  });

  const replay = refresh(rt);
  rowCheck('A4', replay, {
    'replaying the spent token is 400': (r) => r.status === 400,
    'the reason names reuse': (r) =>
      String(r.body || '').indexOf('Maximum allowed refresh token reuse exceeded') !== -1,
  });

  // The replay did not just fail -- it killed the session, so the token that
  // legitimately rotated is dead too, and for a DIFFERENT reason. Both halves
  // are required: the second one is what proves the blast radius is the
  // session and not the single call.
  const family = refresh(rt2);
  rowCheck('A4', family, {
    'the rotated token died with the family': (r) => r.status === 400,
    'the error is invalid_grant': (r) => String(r.body || '').indexOf('invalid_grant') !== -1,
    'the reason differs from reuse detection': (r) =>
      String(r.body || '').indexOf("Session doesn't have required client") !== -1,
  });

  // A4 destroyed this identity's session; anything cached is a stale handle.
  forget('customer', alice);

  // --- A5: logout is idempotent, and it ends the session -------------------
  const fresh = tokenResponse('customer', alice);
  const rt3 = fresh.refresh_token;

  const out = logout(rt3);
  rowCheck('A5', out, { 'logout is 204': (r) => r.status === 204 });

  // Confirmed behaviour, and worth asserting rather than assuming: the
  // end-session endpoint answers 204 again rather than 400.
  const outAgain = logout(rt3);
  rowCheck('A5', outAgain, { 'a replayed logout is 204, not 400': (r) => r.status === 204 });

  const after = refresh(rt3);
  rowCheck('A5', after, {
    'refresh after logout is 400': (r) => r.status === 400,
    'the reason is that the session ended': (r) =>
      String(r.body || '').indexOf('Session not active') !== -1,
  });

  forget('customer', alice);
}

export function handleSummary(data) {
  return {
    stdout: evidenceTable(data, ROWS, `Realm session lifecycle — gate \`${target.gate}\``),
    [`scripts/k6/out/session-${target.gate}.md`]: evidenceTable(
      data,
      ROWS,
      `Realm session lifecycle — gate \`${target.gate}\``
    ),
  };
}
