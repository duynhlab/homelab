// Target selection for the two E2E gates.
//
// One script set serves both gates because the gates differ only in where the
// platform is reached and how fast it may be driven -- not in what is asserted.
// GATE picks a preset; any single value can still be overridden by its own env
// var, which is how a row gets pointed at a port-forward.
//
// rateCeiling is the EDGE limit in requests/second, and it is a real
// constraint rather than a tuning knob: Envoy Gateway's local rate limiter is
// an in-process token bucket with no client dimension on the catch-all rule, so
// the ceiling is shared by every route and every identity. Exceeding it answers
// 429, which the compose runbook rightly calls a finding. Load scenarios pace
// themselves under this number; ratelimit.js is the one script that crosses it
// on purpose.

const GATE = (__ENV.GATE || 'compose').toLowerCase();

const PRESETS = {
  compose: {
    base: 'http://localhost:8080',
    kc: 'http://localhost:8081',
    vm: 'http://localhost:8428',
    graf: 'http://localhost:3002',
    pyroscope: 'http://localhost:4040',
    vtraces: 'http://localhost:10428',
    vmalert: 'http://localhost:8880',
    vmagent: 'http://localhost:8429',
    logs: 'http://localhost:9428',
    // Temporal's HTTP API, served by the UI container. saga.js used to default
    // to the Kind hostname regardless of gate, so SG.3 polled a URL that does
    // not resolve here and reported the saga as "never seen" while Temporal had
    // it Completed all along.
    temporalUI: 'http://localhost:8233',
    redirect: { customer: 'http://localhost:3001/', staff: 'http://localhost:3009/' },
    // gateway/eg/backendtrafficpolicy.yaml: one Envoy process, 50/Second.
    rateCeiling: 50,
    insecure: false,
  },
  kind: {
    base: 'https://gateway.duynh.me',
    kc: 'https://id.duynh.me',
    vm: 'https://vmui.duynh.me',
    graf: 'https://grafana.duynh.me',
    pyroscope: 'https://pyroscope.duynh.me',
    vtraces: 'https://victoriatraces.duynh.me',
    vmalert: 'https://vmalert.duynh.me',
    temporalUI: 'https://temporal.duynh.me',
    // No route by design; reach it with a port-forward and override VMAGENT.
    vmagent: 'http://localhost:8429',
    logs: 'https://logs.duynh.me',
    redirect: { customer: 'https://local.duynh.me/', staff: 'https://backoffice.duynh.me/' },
    // policies/btp-api.yaml requests-per-Second x data-plane replicas
    // (25 x 2). Keep this in step with that manifest; a stale number here
    // reads as a platform fault.
    rateCeiling: Number(__ENV.RATE_CEILING || 50),
    insecure: true,
  },
};

if (!PRESETS[GATE]) {
  throw new Error(`unknown GATE '${GATE}' -- expected 'compose' or 'kind'`);
}

const preset = PRESETS[GATE];

export const target = {
  gate: GATE,
  base: __ENV.BASE || preset.base,
  kc: __ENV.KC || preset.kc,
  vm: __ENV.VM || preset.vm,
  graf: __ENV.GRAF || preset.graf,
  pyroscope: __ENV.PYROSCOPE || preset.pyroscope,
  vtraces: __ENV.VTRACES || preset.vtraces,
  vmalert: __ENV.VMALERT || preset.vmalert,
  temporalUI: __ENV.TEMPORAL_UI || preset.temporalUI,
  vmagent: __ENV.VMAGENT || preset.vmagent,
  logs: __ENV.LOGS || preset.logs,
  redirect: preset.redirect,
  rateCeiling: preset.rateCeiling,
};

// The cluster serves every host from a self-signed homelab-ca that cert-manager
// re-mints on each bring-up, so no committed CA can validate it. Skipping
// verification is therefore the honest default on Kind; point K6_TLS_CACERT at
// a CA pulled from the live cluster to verify properly instead.
export const tlsOptions = preset.insecure ? { insecureSkipTLSVerify: true } : {};

// Realm shapes, from local-stack/keycloak and the runbooks' own mint commands.
// Direct grant is disabled on both realms, so every token here costs a full
// authorization-code + PKCE round trip.
export const REALMS = {
  customer: { realm: 'duynhlab', clientId: 'customer-spa' },
  staff: { realm: 'duynhlab-staff', clientId: 'admin-portal' },
};

// One identity per VU, never shared. The services hold a partial unique index
// admitting one active session per user, so two VUs driving `alice` at once
// evict each other and the failure surfaces as an unrelated 401.
export const IDENTITIES = {
  customer: [
    { username: 'alice', password: 'password123' },
    { username: 'bob', password: 'password123' },
    { username: 'carol', password: 'password123' },
    { username: 'david', password: 'password123' },
  ],
  staff: [{ username: 'duyne', password: 'p@ss1234' }],
};

export function identityFor(kind, index) {
  const pool = IDENTITIES[kind];
  return pool[index % pool.length];
}
