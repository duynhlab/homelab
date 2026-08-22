// Does a dashboard's datasource reference actually resolve?
//
// This is the check that a plain 200 cannot make. A dashboard whose panels name
// `${DS_PROMETHEUS}` without declaring that variable, or that hard-codes a
// `"uid"` no datasource carries, loads with a green 200 and then renders
// `Datasource ... was not found` on every panel -- an error banner, never "No
// data". Both gates have shipped a board in exactly that state.
//
// Kept here because two callers need it and they enumerate differently: the
// compose gate asserts an exact provisioned set, while the cluster's dashboards
// arrive as operator CRs whose count belongs to a kubectl row. Driving the uid
// list from Grafana rather than a literal is what lets one implementation serve
// both.

import http from 'k6/http';

// Grafana's built-in pseudo-datasources are always legal references.
const BUILTIN = ['grafana', '-- Grafana --', '-- Mixed --', '-- Dashboard --'];

// Both uids AND names count as live. Older boards reference a datasource by
// its display name -- `"uid": "VictoriaMetrics"` -- and Grafana resolves that,
// so a uid-only view of what exists reports working dashboards as broken. Found
// exactly that way: the first run of this check flagged two boards for naming
// `ClickHouse` and `VictoriaMetrics`, which are names of live datasources.
export function liveDatasources(graf) {
  const live = {};
  for (const name of BUILTIN) live[name] = true;
  const res = http.get(`${graf}/api/datasources`);
  if (res.status === 200) {
    for (const d of res.json() || []) {
      if (d.uid) live[d.uid] = true;
      if (d.name) live[d.name] = true;
    }
  }
  return live;
}

export function dashboardUids(graf) {
  const res = http.get(`${graf}/api/search?type=dash-db`);
  if (res.status !== 200) return null;
  return (res.json() || []).map((d) => d.uid);
}

// Returns { status, problems: [...] }. An empty problems list means every
// reference in the board resolves against `live`.
export function referenceProblems(graf, uid, live) {
  const res = http.get(`${graf}/api/dashboards/uid/${uid}`);
  if (res.status !== 200) return { status: res.status, problems: ['did not load'] };

  const raw = String(res.body || '');
  const dash = (res.json() || {}).dashboard || {};

  const declared = {};
  for (const v of (dash.templating && dash.templating.list) || []) {
    if (v.type === 'datasource' && v.name) declared[v.name] = true;
  }
  // Some boards carry an `__inputs` block instead of declaring the variable,
  // and rely on the import mapping to substitute it. Treat those inputs as
  // declared: their real risk is the mapping going missing, which is a
  // manifest-level concern rather than something this check can see.
  for (const i of dash.__inputs || []) {
    if (i && i.name) declared[i.name] = true;
  }

  const problems = [];
  const varRe = /\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g;
  const seen = {};
  let m;
  while ((m = varRe.exec(raw)) !== null) {
    const n = m[1];
    const looksLikeDatasource =
      n.toUpperCase().indexOf('DS_') === 0 || n === 'ds' || n === 'datasource';
    if (looksLikeDatasource && !declared[n] && !seen[`v:${n}`]) {
      seen[`v:${n}`] = true;
      problems.push(`undeclared var ${n}`);
    }
  }

  const uidRe = /"uid"\s*:\s*"([^"$]+)"/g;
  while ((m = uidRe.exec(raw)) !== null) {
    const u = m[1];
    if (!live[u] && u !== dash.uid && !seen[`u:${u}`]) {
      seen[`u:${u}`] = true;
      problems.push(`unknown uid ${u}`);
    }
  }

  return { status: res.status, problems: problems };
}
