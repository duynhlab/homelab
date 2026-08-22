// Row bookkeeping: turn audit rows into checks that carry their row id, and
// turn the run into the evidence table both runbooks ask a human to type.
//
// Every assertion is tagged with its row, and every row gets a
// `checks{row:<id>}: rate==1.0` threshold. That pairing is what makes the gate
// a gate: a failed assertion breaches its threshold and k6 exits 99, so a
// broken row can no longer pass by going unread in scrollback.

import { check } from 'k6';

// Assert against a row. `assertions` is the k6 check map; the row id is both
// the tag and the check-name prefix so a failure line names its row.
export function rowCheck(id, subject, assertions) {
  const named = {};
  for (const label of Object.keys(assertions)) {
    named[`${id} ${label}`] = assertions[label];
  }
  return check(subject, named, { row: id });
}

export function rowThresholds(rows) {
  const t = {};
  for (const id of rows) t[`checks{row:${id}}`] = ['rate==1.0'];
  return t;
}

// A row present in the plan but absent from the results did not run. Saying so
// matters more than it sounds: a row that quietly never executed is the one
// failure mode a green summary cannot distinguish from success, and both
// runbooks have been bitten by exactly that.
export function evidenceTable(data, rows, title) {
  const lines = [
    `### ${title}`,
    '',
    '| Row | Checks | Verdict |',
    '|-----|--------|---------|',
  ];
  let failed = 0;
  let missing = 0;

  for (const id of rows) {
    const m = data.metrics[`checks{row:${id}}`];
    if (!m) {
      missing++;
      lines.push(`| ${id} | – | **DID NOT RUN** |`);
      continue;
    }
    const { passes = 0, fails = 0 } = m.values;
    // A declared threshold mints the submetric even when nothing asserted
    // against it, so zero-of-zero means the row never executed -- report that
    // as its own verdict rather than as a failure, because the fix differs.
    if (passes === 0 && fails === 0) {
      missing++;
      lines.push(`| ${id} | 0/0 | **DID NOT RUN** |`);
      continue;
    }
    const ok = fails === 0;
    if (!ok) failed++;
    lines.push(`| ${id} | ${passes}/${passes + fails} | ${ok ? 'PASS' : '**FAIL**'} |`);
  }

  const total = data.metrics.checks ? data.metrics.checks.values : { passes: 0, fails: 0 };
  lines.push(
    '',
    `${rows.length} rows: ${rows.length - failed - missing} pass, ${failed} fail, ` +
      `${missing} did not run — ${total.passes} of ${total.passes + total.fails} assertions passed.`,
    ''
  );
  return lines.join('\n');
}
