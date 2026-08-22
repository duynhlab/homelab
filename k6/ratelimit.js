// The edge rate limit, as a tested contract instead of a footnote.
//
// Neither runbook asserts anything about the limiter. The compose file tells you
// a 429 is a finding (its ceiling is 50/s, unreachable by hand); the Kind file
// never mentions rate limiting at all -- while its ceiling is roughly 4/s, low
// enough that a browser opening one page can cross it. So the two gates disagree
// about the edge by 25x and neither one measures it.
//
// This script measures it. Two scenarios, run in sequence:
//
//   under  -- pace below the configured ceiling, expect no 429 at all
//   over   -- pace above it, expect 429 AND the draft-03 headers that tell a
//             client its remaining budget
//
// Envoy Gateway's local limiter is an in-process token bucket, so the fleet
// ceiling is the configured number times the data-plane replica count and which
// pod a request lands on is the load balancer's business. `over` therefore
// asserts that 429 appears, never an exact count.
//
//   GATE=kind    k6 run k6/ratelimit.js
//   GATE=compose k6 run k6/ratelimit.js

import http from 'k6/http';
import { Counter } from 'k6/metrics';
import { target, tlsOptions } from './lib/config.js';
import { rowCheck, rowThresholds } from './lib/rows.js';

const PROBE = '/product/v1/public/products';

const accepted = new Counter('rl_accepted');
const limited = new Counter('rl_limited');

const ceiling = target.rateCeiling;
const ROWS = ['RL.1', 'RL.2'];

export const options = Object.assign(
  {
    scenarios: {
      // Half the ceiling, so even an uneven split across replicas stays inside
      // the smallest bucket.
      under: {
        executor: 'constant-arrival-rate',
        rate: Math.max(1, Math.floor(ceiling / 2)),
        timeUnit: '1s',
        duration: '6s',
        preAllocatedVUs: Math.max(2, ceiling),
        exec: 'under',
      },
      over: {
        executor: 'constant-arrival-rate',
        rate: ceiling * 4,
        timeUnit: '1s',
        duration: '6s',
        preAllocatedVUs: Math.max(4, ceiling * 4),
        maxVUs: ceiling * 8,
        exec: 'over',
        // Start after `under` finishes plus a second for the bucket to refill,
        // or the leftover tokens from one scenario decide the other's verdict.
        startTime: '8s',
      },
    },
    thresholds: rowThresholds(ROWS),
    discardResponseBodies: true,
  },
  tlsOptions
);

export function under() {
  const res = http.get(`${target.base}${PROBE}`);
  if (res.status === 429) limited.add(1);
  else accepted.add(1);
  rowCheck('RL.1', res, {
    [`under ${ceiling}/s is not limited`]: (r) => r.status !== 429,
  });
}

export function over() {
  const res = http.get(`${target.base}${PROBE}`);
  const isLimited = res.status === 429;
  if (isLimited) limited.add(1);
  else accepted.add(1);
  // Only the limited responses are asserted on: an accepted one carries the
  // headers too, but it is the rejection that has to be well-formed for a
  // client to back off correctly.
  if (isLimited) {
    rowCheck('RL.2', res, {
      'a limited response carries X-RateLimit-Limit': (r) =>
        !!(r.headers['X-Ratelimit-Limit'] || r.headers['X-RateLimit-Limit']),
      'a limited response carries X-RateLimit-Remaining': (r) =>
        !!(r.headers['X-Ratelimit-Remaining'] || r.headers['X-RateLimit-Remaining']),
      'a limited response carries X-RateLimit-Reset': (r) =>
        !!(r.headers['X-Ratelimit-Reset'] || r.headers['X-RateLimit-Reset']),
    });
  }
}

export function handleSummary(data) {
  const ok = (data.metrics.rl_accepted && data.metrics.rl_accepted.values.count) || 0;
  const no = (data.metrics.rl_limited && data.metrics.rl_limited.values.count) || 0;
  const rl2 = data.metrics['checks{row:RL.2}'];
  const sawLimit = rl2 && rl2.values.passes + rl2.values.fails > 0;

  const lines = [
    `### Edge rate limit — gate \`${target.gate}\``,
    '',
    `Configured ceiling: **${ceiling}/s** (per Envoy instance).`,
    '',
    '| | |',
    '|---|---|',
    `| Accepted | ${ok} |`,
    `| Limited (429) | ${no} |`,
    `| RL.1 under ${Math.max(1, Math.floor(ceiling / 2))}/s | ${
      data.metrics['checks{row:RL.1}'] && data.metrics['checks{row:RL.1}'].values.fails === 0
        ? 'PASS — nothing limited'
        : '**FAIL** — limited below the ceiling'
    } |`,
    `| RL.2 over ${ceiling * 4}/s | ${
      !sawLimit
        ? '**FAIL** — the limiter never engaged, so it is not enforcing'
        : rl2.values.fails === 0
        ? 'PASS — 429 with draft-03 headers'
        : '**FAIL** — 429 without the draft-03 headers'
    } |`,
    '',
  ];
  // A run that never saw a 429 while deliberately driving 4x the ceiling means
  // the limiter is absent, not that the platform is fast. Say so rather than
  // reporting an empty PASS.
  if (!sawLimit) {
    lines.push(
      `Drove ${ceiling * 4}/s for 6s and nothing was limited — either the policy ` +
        `is not attached to this route, or the ceiling is higher than \`${ceiling}\`.`,
      ''
    );
  }
  const md = lines.join('\n');
  return { stdout: md, [`k6/out/ratelimit-${target.gate}.md`]: md };
}
