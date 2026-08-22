// Query helpers for the stores the audits assert against.
//
// The audit labels these rows `promql` / `sql` / `LogsQL`, which describes the
// query language rather than the transport -- every one of them is an HTTP GET
// or POST returning JSON. That is why they belong in the suite: nothing about
// them needs a shell.
//
// Each helper returns a plain value or null and never throws on an empty
// result, because "no series" is a normal answer that a row must be able to
// assert on. A row that cannot tell "no series" from "query failed" is the
// failure mode the VERIFY-AT-KIND convention exists for: an expression naming a
// series that does not exist loads cleanly and stays silent forever.

import http from 'k6/http';

// --- VictoriaMetrics / PromQL ----------------------------------------------

export function promql(base, query) {
  const res = http.get(`${base}/api/v1/query?query=${encodeURIComponent(query)}`, {
    tags: { store: 'vm' },
  });
  if (res.status !== 200) return { ok: false, status: res.status, result: [] };
  const data = res.json('data');
  return { ok: true, status: 200, result: (data && data.result) || [] };
}

// First sample as a number, or null when the expression matched nothing. Null
// is the answer the audit prints as NO SERIES.
export function promqlScalar(base, query) {
  const r = promql(base, query);
  if (!r.ok || !r.result.length) return null;
  const v = Number(r.result[0].value[1]);
  return Number.isNaN(v) ? null : v;
}

// `count by (label) (expr)` shaped into { labelValue: count }.
export function promqlCountBy(base, query, label) {
  const r = promql(base, query);
  const out = {};
  for (const s of r.result) {
    const k = s.metric[label];
    if (k !== undefined) out[k] = Number(s.value[1]);
  }
  return out;
}

// --- VictoriaLogs / LogsQL -------------------------------------------------

// The query endpoint answers newline-delimited JSON, one object per row, so a
// `| count()` pipe comes back as a single object rather than an envelope.
export function logsqlCount(base, query) {
  const res = http.post(
    `${base}/select/logsql/query`,
    { query: query },
    { tags: { store: 'vl' } }
  );
  if (res.status !== 200) return null;
  const line = String(res.body || '').trim().split('\n')[0];
  if (!line) return 0;
  let obj;
  try {
    obj = JSON.parse(line);
  } catch (e) {
    return null;
  }
  // The column name follows the pipe -- `count()` unless the query aliased it.
  for (const k of Object.keys(obj)) {
    const n = Number(obj[k]);
    if (!Number.isNaN(n)) return n;
  }
  return null;
}

// --- Grafana ---------------------------------------------------------------
//
// Grafana runs with anonymous Admin on both gates, so none of these carry a
// token. `/api/ds/query` is the panel path: health only proves the plugin can
// reach the store, not that it can run a query and shape a frame.

export function grafanaFrame(graf, query) {
  const res = http.post(`${graf}/api/ds/query`, JSON.stringify(query), {
    headers: { 'Content-Type': 'application/json' },
    tags: { store: 'grafana' },
  });
  if (res.status !== 200) return { ok: false, status: res.status, values: null };
  const results = res.json('results');
  const a = results && results.A;
  const frames = a && a.frames;
  const values = frames && frames[0] && frames[0].data && frames[0].data.values;
  return { ok: true, status: 200, values: values || null };
}

export function promFrame(graf, expr) {
  return grafanaFrame(graf, {
    from: 'now-45m',
    to: 'now',
    queries: [
      {
        refId: 'A',
        datasource: { uid: 'victoriametrics', type: 'prometheus' },
        expr: expr,
        instant: true,
      },
    ],
  });
}

export function clickhouseFrame(graf, rawSql) {
  return grafanaFrame(graf, {
    from: 'now-45m',
    to: 'now',
    queries: [
      {
        refId: 'A',
        datasource: { uid: 'clickhouse', type: 'grafana-clickhouse-datasource' },
        rawSql: rawSql,
        format: 1,
        queryType: 'table',
      },
    ],
  });
}
