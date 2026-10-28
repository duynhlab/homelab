#!/usr/bin/env node
// Validate one review.json against schema.json plus the invariants the schema
// cannot express, render it as the PR comment, and (unless DRY_RUN=true)
// upsert that comment and the impact/* labels on the pull request.
//
//   node post.mjs .review/review.json --check   validate only, exit 1 on error
//   node post.mjs .review/review.json           validate, render, post
//
// Environment: GITHUB_REPOSITORY, PR_NUMBER, RUN_URL, DRY_RUN ("true" prints the
// comment and the label plan without calling the API), GH_TOKEN.
//
// The job that runs the AI never reaches this file with write permission; only
// the post job does, from a file the AI could write but not post.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const MARKER = "<!-- dep-radar:v1 ";
const BOT_LOGIN = "github-actions[bot]";
const IMPACT_LABELS = ["impact/none", "impact/minor", "impact/breaking"];
const VERIFY_LABEL = "ai/needs-verification";

const here = dirname(fileURLToPath(import.meta.url));
const schema = JSON.parse(readFileSync(join(here, "schema.json"), "utf8"));

// --- a validator for the JSON Schema subset schema.json uses -------------------

function validate(value, node, path, errors) {
  if (node.const !== undefined && value !== node.const) {
    errors.push(`${path}: must equal ${JSON.stringify(node.const)}`);
    return;
  }
  if (node.enum && !node.enum.includes(value)) {
    errors.push(`${path}: must be one of ${node.enum.join(", ")}`);
    return;
  }
  if (node.type) {
    const ok =
      (node.type === "object" && value !== null && typeof value === "object" && !Array.isArray(value)) ||
      (node.type === "array" && Array.isArray(value)) ||
      (node.type === "string" && typeof value === "string") ||
      (node.type === "boolean" && typeof value === "boolean") ||
      (node.type === "integer" && Number.isInteger(value));
    if (!ok) {
      errors.push(`${path}: must be ${node.type}`);
      return;
    }
  }
  if (typeof value === "string") {
    if (node.minLength !== undefined && value.length < node.minLength) errors.push(`${path}: must not be empty`);
    if (node.maxLength !== undefined && value.length > node.maxLength) errors.push(`${path}: longer than ${node.maxLength}`);
    if (node.pattern && !new RegExp(node.pattern).test(value)) errors.push(`${path}: must match ${node.pattern}`);
    if (node.format === "uri" && !/^https?:\/\/\S+$/.test(value)) errors.push(`${path}: must be an absolute http(s) URL`);
    if (node.format === "date-time" && Number.isNaN(Date.parse(value))) errors.push(`${path}: must be an ISO-8601 date-time`);
  }
  if (typeof value === "number" && node.minimum !== undefined && value < node.minimum) {
    errors.push(`${path}: must be >= ${node.minimum}`);
  }
  if (node.type === "object") {
    for (const key of node.required || []) {
      if (!(key in value)) errors.push(`${path}: missing required key "${key}"`);
    }
    for (const [key, child] of Object.entries(value)) {
      const childNode = node.properties?.[key];
      if (!childNode) {
        if (node.additionalProperties === false) errors.push(`${path}: unexpected key "${key}"`);
        continue;
      }
      validate(child, childNode, `${path}.${key}`, errors);
    }
  }
  if (node.type === "array" && node.items) {
    value.forEach((item, i) => validate(item, node.items, `${path}[${i}]`, errors));
  }
}

function invariants(review, currentHeadSha, prNumber) {
  const errors = [];
  if (review.impact === "breaking") {
    const relevant = review.breaking.some((b) => b.relevant);
    if (!relevant && review.hold_reason !== "confirmed-repo-breaking-change") {
      errors.push("impact=breaking needs a relevant breaking[] item or hold_reason=confirmed-repo-breaking-change");
    }
  }
  if (review.verdict === "hold") {
    if (!review.hold_reason) errors.push("verdict=hold needs hold_reason");
    if (review.verification.length === 0) errors.push("verdict=hold needs at least one verification step");
  }
  if (prNumber && review.pr !== prNumber) errors.push(`pr=${review.pr} does not match PR_NUMBER=${prNumber}`);
  if (currentHeadSha && review.head_sha !== currentHeadSha) {
    errors.push(`head_sha ${review.head_sha.slice(0, 7)} is not the PR head ${currentHeadSha.slice(0, 7)}; the PR moved during the review`);
  }
  return errors;
}

// --- rendering -----------------------------------------------------------------

const esc = (s) => String(s).replace(/</g, "&lt;");
const glyph = { none: "○", minor: "△", breaking: "✕" };
const holdLabel = (r) => (r ? r.replace(/-/g, " ") : "");

function render(review, ctx) {
  const d = review.dependency;
  const lines = [];
  lines.push(`${MARKER}${JSON.stringify(review)} -->`);
  lines.push(`### Dependency review · \`${esc(d.name)}\` ${esc(d.from)} → ${esc(d.to)}`);
  const verdict = review.verdict === "hold" ? `hold (${holdLabel(review.hold_reason)})` : review.verdict;
  lines.push("");
  lines.push(
    `**Verdict:** ${verdict} · **Impact:** ${glyph[review.impact]} ${review.impact} · ` +
      `${d.update_type} · reviewed \`${review.head_sha.slice(0, 7)}\` · prompt v${review.prompt_version} · ${esc(review.model)}`,
  );
  lines.push("");
  lines.push(esc(review.summary));
  if (d.notes_truncated) lines.push("", "> Renovate truncated the release notes in this PR body; the review covers what was visible.");

  const relevant = review.breaking.filter((b) => b.relevant);
  const irrelevant = review.breaking.filter((b) => !b.relevant);
  if (review.breaking.length) {
    lines.push("", `**Relevant changes** (${relevant.length} of ${review.breaking.length})`);
    for (const b of relevant) {
      const ver = b.version ? ` _(${esc(b.version)})_` : "";
      const link = b.evidence_url ? ` · [source](${b.evidence_url})` : "";
      lines.push(`- ${esc(b.title)}${ver} — ${esc(b.why)}${link}`);
    }
    if (relevant.length === 0) lines.push("- none");
    if (irrelevant.length) {
      lines.push("", "<details>", `<summary>${irrelevant.length} change${irrelevant.length === 1 ? "" : "s"} not relevant to this repository</summary>`, "");
      for (const b of irrelevant) lines.push(`- ${esc(b.title)} — ${esc(b.why)}`);
      lines.push("", "</details>");
    }
  }

  if (review.features?.length) {
    const useful = review.features.filter((f) => f.useful_for_homelab);
    if (useful.length) {
      lines.push("", "**Worth a look**");
      for (const f of useful) lines.push(`- ${esc(f.title)}${f.why ? ` — ${esc(f.why)}` : ""}${f.evidence_url ? ` · [source](${f.evidence_url})` : ""}`);
    }
  }

  if (review.affected_files.length) {
    lines.push("", "**Affected in this repository**");
    for (const f of review.affected_files) {
      const url = `https://github.com/${ctx.repo}/blob/main/${f.path}`;
      lines.push(`- [\`${esc(f.path)}\`](${url}) (${f.role})${f.note ? ` — ${esc(f.note)}` : ""}`);
    }
  }

  if (review.verification.length) {
    lines.push("", "**Verify before merge**");
    for (const v of review.verification) lines.push(`- [ ] ${v.kind} — ${esc(v.step)}`);
  }

  if (review.related_prs.length) {
    lines.push("", "**Lands with**");
    for (const r of review.related_prs) lines.push(`- #${r.number} (${r.relationship})${r.note ? ` — ${esc(r.note)}` : ""}`);
  }

  if (review.evidence.length) {
    lines.push("", "**Upstream evidence**");
    for (const e of review.evidence) lines.push(`- [${esc(e.label)}](${e.url})`);
  }

  if (review.notes?.length) {
    lines.push("", "**Notes**");
    for (const n of review.notes) lines.push(`- ${esc(n)}`);
  }

  lines.push(
    "",
    `<sub>AI commentary from [this workflow run](${ctx.runUrl}); it is not a substitute for reading the release notes. ` +
      "The comment is replaced on every push to the PR.</sub>",
  );
  return lines.join("\n") + "\n";
}

// --- GitHub ---------------------------------------------------------------------

const gh = (args, input) =>
  execFileSync("gh", args, { encoding: "utf8", input, maxBuffer: 64 * 1024 * 1024 });
const ghJson = (args) => JSON.parse(gh(args));

function currentPr(repo, number) {
  return ghJson(["api", `repos/${repo}/pulls/${number}`, "--jq", "{head_sha: .head.sha, labels: [.labels[].name], state: .state}"]);
}

function findReviewComment(repo, number) {
  const comments = ghJson([
    "api", `repos/${repo}/issues/${number}/comments`, "--paginate", "--jq",
    `[.[] | select(.user.login == "${BOT_LOGIN}") | {id, body}]`,
  ]).flat();
  return comments.find((c) => typeof c.body === "string" && c.body.startsWith(MARKER)) || null;
}

function upsertComment(repo, number, body) {
  const existing = findReviewComment(repo, number);
  const dir = mkdtempSync(join(tmpdir(), "dep-review-"));
  const payload = join(dir, "comment.json");
  writeFileSync(payload, JSON.stringify({ body }));
  if (existing) {
    gh(["api", "-X", "PATCH", `repos/${repo}/issues/comments/${existing.id}`, "--input", payload]);
    return `updated comment ${existing.id}`;
  }
  const created = ghJson(["api", "-X", "POST", `repos/${repo}/issues/${number}/comments`, "--input", payload]);
  return `created comment ${created.id}`;
}

function labelPlan(review, current) {
  const want = new Set([`impact/${review.impact}`]);
  if (review.verdict === "hold") want.add(VERIFY_LABEL);
  const managed = new Set([...IMPACT_LABELS, VERIFY_LABEL]);
  const have = new Set(current.filter((l) => managed.has(l)));
  return {
    add: [...want].filter((l) => !have.has(l)),
    remove: [...have].filter((l) => !want.has(l)),
  };
}

function applyLabels(repo, number, plan) {
  for (const label of plan.remove) {
    gh(["api", "-X", "DELETE", `repos/${repo}/issues/${number}/labels/${encodeURIComponent(label)}`]);
  }
  if (plan.add.length) {
    gh(["api", "-X", "POST", `repos/${repo}/issues/${number}/labels`, "--input", "-"], JSON.stringify({ labels: plan.add }));
  }
}

// --- main -----------------------------------------------------------------------

function main() {
  const [, , file, flag] = process.argv;
  if (!file) {
    console.error("usage: post.mjs <review.json> [--check]");
    return 2;
  }
  const checkOnly = flag === "--check";
  const repo = process.env.GITHUB_REPOSITORY;
  const prNumber = Number.parseInt(process.env.PR_NUMBER || "0", 10) || null;
  const dryRun = process.env.DRY_RUN === "true";

  let review;
  try {
    review = JSON.parse(readFileSync(file, "utf8"));
  } catch (err) {
    console.error(`review.json is not valid JSON: ${err.message}`);
    return 1;
  }

  const errors = [];
  validate(review, schema, "$", errors);
  if (errors.length) {
    console.error("review.json does not match schema.json:");
    for (const e of errors) console.error(`  - ${e}`);
    return 1;
  }

  let pr = null;
  if (!checkOnly) {
    if (!repo || !prNumber) {
      console.error("GITHUB_REPOSITORY and PR_NUMBER are required to post");
      return 2;
    }
    pr = currentPr(repo, prNumber);
  }
  const invErrors = invariants(review, pr?.head_sha, prNumber);
  if (invErrors.length) {
    console.error("review.json violates an invariant:");
    for (const e of invErrors) console.error(`  - ${e}`);
    return 1;
  }
  if (checkOnly) {
    console.log("review.json is valid");
    return 0;
  }

  const body = render(review, { repo, runUrl: process.env.RUN_URL || "https://github.com/" + repo + "/actions" });
  const plan = labelPlan(review, pr.labels);

  if (dryRun) {
    console.log(body);
    console.log(`[dry-run] labels add=${JSON.stringify(plan.add)} remove=${JSON.stringify(plan.remove)}`);
    return 0;
  }
  if (pr.state !== "open") {
    console.log(`PR #${prNumber} is ${pr.state}; nothing posted`);
    return 0;
  }
  console.log(upsertComment(repo, prNumber, body));
  applyLabels(repo, prNumber, plan);
  console.log(`labels add=${JSON.stringify(plan.add)} remove=${JSON.stringify(plan.remove)}`);
  return 0;
}

process.exit(main());
