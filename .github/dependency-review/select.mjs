#!/usr/bin/env node
// Pick the Renovate pull requests the dependency-review workflow should run on
// and print them as a JSON array of {number, head_sha} for the job matrix.
//
// Inputs (environment):
//   GITHUB_REPOSITORY  owner/repo
//   EVENT_PR           PR number when triggered by a pull_request event
//   INPUT_PR           "all" or a PR number when triggered by workflow_dispatch
//   INPUT_MAX          max PRs per run (default 10)
//   INPUT_FORCE        "true" to ignore an existing review for the same head SHA
//   GH_TOKEN           read-only token for gh
//
// Skips, in order: first-party images (they have their own changelog and CI),
// digest-only bumps with no release notes to read, and PRs whose current head
// SHA already carries a review comment (the comment is the state store).
import { execFileSync } from "node:child_process";
import { appendFileSync } from "node:fs";

const MARKER = "<!-- dep-radar:v1 ";
const BOT_LOGIN = "github-actions[bot]";
const FIRST_PARTY = "ghcr.io/duynhlab/";

const repo = process.env.GITHUB_REPOSITORY;
if (!repo) throw new Error("GITHUB_REPOSITORY is not set");

const gh = (args) => execFileSync("gh", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
const ghJson = (args) => JSON.parse(gh(args));

const fields = "number,title,body,headRefOid,author";

function candidates() {
  if (process.env.EVENT_PR) {
    return [ghJson(["pr", "view", process.env.EVENT_PR, "--repo", repo, "--json", fields])];
  }
  const input = (process.env.INPUT_PR || "all").trim();
  if (input !== "all") {
    return [ghJson(["pr", "view", input, "--repo", repo, "--json", fields])];
  }
  return ghJson([
    "pr", "list", "--repo", repo, "--state", "open", "--author", "app/renovate",
    "--limit", "100", "--json", fields,
  ]);
}

function reviewedHeadSha(number) {
  const comments = ghJson([
    "api", `repos/${repo}/issues/${number}/comments`, "--paginate", "--jq",
    `[.[] | select(.user.login == "${BOT_LOGIN}") | .body] `,
  ]).flat();
  for (const body of comments) {
    if (typeof body !== "string" || !body.startsWith(MARKER)) continue;
    const end = body.indexOf("-->");
    if (end < 0) continue;
    try {
      const review = JSON.parse(body.slice(MARKER.length, end));
      if (typeof review.head_sha === "string") return review.head_sha;
    } catch {
      // A malformed marker is not a review; re-review the PR.
    }
  }
  return null;
}

const max = Number.parseInt(process.env.INPUT_MAX || "10", 10) || 10;
const force = process.env.INPUT_FORCE === "true";
const selected = [];
const skipped = [];

for (const pr of candidates()) {
  const login = pr.author?.login || "";
  if (!process.env.EVENT_PR && login !== "app/renovate" && login !== "renovate[bot]") {
    skipped.push([pr.number, `author ${login} is not Renovate`]);
    continue;
  }
  if (pr.title.includes(FIRST_PARTY)) {
    skipped.push([pr.number, "first-party image"]);
    continue;
  }
  const digestOnly = /docker digest to/i.test(pr.title) && !pr.body.includes("### Release Notes");
  if (digestOnly) {
    skipped.push([pr.number, "digest-only bump, nothing to read"]);
    continue;
  }
  if (!force && reviewedHeadSha(pr.number) === pr.headRefOid) {
    skipped.push([pr.number, `head ${pr.headRefOid.slice(0, 7)} already reviewed`]);
    continue;
  }
  if (selected.length >= max) {
    skipped.push([pr.number, `over max=${max}, next run`]);
    continue;
  }
  selected.push({ number: pr.number, head_sha: pr.headRefOid });
}

for (const [n, why] of skipped) console.error(`skip #${n}: ${why}`);
console.error(`selected ${selected.length}: ${selected.map((p) => `#${p.number}`).join(" ") || "-"}`);

const json = JSON.stringify(selected);
console.log(json);
if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `prs=${json}\n`);
