// Authorization code + PKCE, in JS, because neither realm accepts a password
// grant. `curl -d grant_type=password` cannot mint a token here, so a token
// costs a full browser-shaped round trip: authorize, post the login form, read
// the code off the redirect, exchange it with the verifier.
//
// This replaces shelling out to local-stack/scripts/keycloak-token.sh for k6
// runs. The bash script stays for hand-driven rows. Porting it buys two things
// beyond one less dependency: the flow now runs per-VU inside the test (so a
// load scenario is not serialised behind a subprocess), and it sidesteps a trap
// the shell version cannot -- under zsh, `USERNAME` is a shell-set variable
// holding the OS user, so `USERNAME=alice ./keycloak-token.sh` silently logs in
// as whoever is at the keyboard.

import http from 'k6/http';
import crypto from 'k6/crypto';
import { target, tlsOptions, REALMS } from './config.js';

function realmBase(kind) {
  const r = REALMS[kind];
  if (!r) throw new Error(`unknown realm kind '${kind}'`);
  return `${target.kc}/realms/${r.realm}/protocol/openid-connect`;
}

// The verifier is 43-128 unreserved characters; the challenge is
// base64url(sha256(verifier)) with padding stripped -- 'base64rawurl' is
// exactly that encoding, so no manual +/ translation is needed.
function pkcePair() {
  const verifier = crypto.hexEncode(crypto.randomBytes(32));
  return { verifier, challenge: crypto.sha256(verifier, 'base64rawurl') };
}

// Returns { access_token, refresh_token, expires_in, ... } as the realm sent
// it, so a caller can assert on claims (row A1) or spend the refresh token
// (rows A4/A5) rather than only carry a bearer string.
export function tokenResponse(kind, identity) {
  const base = realmBase(kind);
  const { clientId } = REALMS[kind];
  const redirect = target.redirect[kind];
  const { verifier, challenge } = pkcePair();

  // 1. Authorization request. Answers 200 with the login page and sets the
  //    AUTH_SESSION_ID / KC_RESTART cookies the form post needs; k6's per-VU
  //    cookie jar carries them automatically.
  const authUrl =
    `${base}/auth?client_id=${encodeURIComponent(clientId)}` +
    `&redirect_uri=${encodeURIComponent(redirect)}` +
    `&response_type=code&scope=openid` +
    `&state=${crypto.hexEncode(crypto.randomBytes(8))}` +
    `&code_challenge=${challenge}&code_challenge_method=S256`;

  // Two success shapes, and missing the second one costs a confusing failure.
  // On a cold cookie jar Keycloak answers 200 with the login page. But the jar
  // is per-VU and survives iterations, so once this VU holds an SSO session for
  // the realm, the same request answers 302 straight to the redirect URI with a
  // code already attached and no form is ever rendered. Following that redirect
  // lands on the SPA -- a 200 with no login form -- which reads as "the realm or
  // client does not exist" while both are perfectly fine.
  const page = http.get(authUrl, { redirects: 0, tags: { step: 'authorize' } });
  if (page.status === 302 || page.status === 303) {
    const loc = page.headers['Location'] || page.headers['location'] || '';
    const ssoCode = (loc.match(/[?&]code=([^&]+)/) || [])[1];
    if (!ssoCode) throw new Error(`authorize redirected without a code: ${loc}`);
    return exchange(base, clientId, redirect, ssoCode, verifier);
  }
  if (page.status !== 200) {
    throw new Error(`authorize failed: ${page.status} (Keycloak up at ${target.kc}?)`);
  }

  // 2. The form action is per-attempt: it carries session_code, execution and
  //    tab_id. Selecting by the action substring rather than a theme's form id
  //    keeps this working if the login template is restyled. Reading it through
  //    the HTML parser also decodes &amp; for free.
  const action = page
    .html()
    .find('form[action*="login-actions/authenticate"]')
    .first()
    .attr('action');
  if (!action) {
    throw new Error(
      `no login form for realm '${REALMS[kind].realm}' / client '${clientId}' -- do both exist?`
    );
  }

  // 3. Success is a 302 to the redirect URI carrying the code. A rejected
  //    login re-renders the form with 200, so the redirect -- not the status --
  //    is what says the credentials were accepted.
  const posted = http.post(
    action,
    { username: identity.username, password: identity.password, credentialId: '' },
    { redirects: 0, tags: { step: 'login' } }
  );
  const location = posted.headers['Location'] || posted.headers['location'];
  if (!location) {
    throw new Error(
      `login rejected for '${identity.username}' (no redirect: wrong password, ` +
        `disabled user, or an extra authenticator in the browser flow)`
    );
  }
  const code = (location.match(/[?&]code=([^&]+)/) || [])[1];
  if (!code) throw new Error(`redirect carried no code: ${location}`);

  // 4. A public client authenticates with the verifier alone -- there is no
  //    client secret to hold.
  return exchange(base, clientId, redirect, code, verifier);
}

function exchange(base, clientId, redirect, code, verifier) {
  const res = http.post(
    `${base}/token`,
    {
      grant_type: 'authorization_code',
      client_id: clientId,
      redirect_uri: redirect,
      code: code,
      code_verifier: verifier,
    },
    { tags: { step: 'token' } }
  );
  const body = res.json();
  if (!body || !body.access_token) {
    throw new Error(`token endpoint returned no access_token: ${res.status} ${res.body}`);
  }
  return body;
}

// Per-VU token cache. Access tokens live 900s and every row in a gate run fits
// well inside that, so one mint per identity per VU is enough; re-mint
// explicitly when a row spends or invalidates the session.
const cache = {};

export function token(kind, identity) {
  const key = `${kind}:${identity.username}`;
  if (!cache[key]) cache[key] = tokenResponse(kind, identity).access_token;
  return cache[key];
}

export function forget(kind, identity) {
  delete cache[`${kind}:${identity.username}`];
}

export function bearer(kind, identity, extra) {
  return Object.assign({ headers: { Authorization: `Bearer ${token(kind, identity)}` } }, extra || {});
}

export { tlsOptions };
