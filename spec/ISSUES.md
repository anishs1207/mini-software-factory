# Daily Briefing: GitHub issue plan

Give this file and the selected `spec_path` to the Hermes `manager` agent. It should create the issues in GitHub, link each prerequisite through GitHub's native **blocked by** issue dependency, assign each to the role below, and keep issue comments as the canonical handoff trail. Start every issue with prerequisites at `briefing:waiting`; the poller releases it only after prerequisite issues close and builder PRs merge. The builders decide implementation details and write the feature code. Do not paste generated product code into these tickets.

## Shared rules for every issue

- One public source only: RSS or a free public API; a synthetic feed is acceptable for deterministic tests. No paid keys or personal data.
- Every PR links its issue, names the agent/model used, includes an approximate token count and tests actually run, and has an agent-authored commit. Builder PRs include `product-check.sh` so CI can run product tests on a fresh runner.
- Reviewer checks the diff against the issue and records **approved** or **changes requested** with a reason. Tester records observed commands/results. A requested change sends the issue back to the builder before merge.
- Human owner reviews and merges after both gates pass. No agent merges its own PR.
- Preserve a few real run records, including an unchanged run and a failed run, for the final demo.

## Issue 1 — Choose source and define run contract

**Owner:** manager (Hermes) with a bounded foreground planning pass. **Dependency:** none. Do not use `delegate_task` while all agents share a one-request Ollama key; its background child can overlap the manager.

Pick a stable, free source (or synthetic feed) and write a short contract in the issue: item ID source, fields stored per run, failure representation, schedule interval, and how a run is triggered for demo. Name the proposed lightweight persistence choice and public serving approach. Keep the plan small; do not write feature code.

**Acceptance:** reviewer and builders can implement from the contract without guessing what counts as “new.” The issue explicitly says first run is all new and repeat IDs are never new.

## Issue 2 — Persist runs and source items

**Owner:** ingest (OpenClaw). **Depends on:** Issue 1 above (use its actual GitHub issue number).

Create a durable store for every execution: timestamp, success/failure, error when present, source items and stable IDs, and count of new items. A small SQLite database or files on the VM are sufficient. Make schema/migration or initialization reproducible.

**Acceptance:** a successful run survives process restart; a failed run also appears in the history. Add focused tests for persistence and failure recording, invoked by `bash product-check.sh`. PR with agent-authored commit and handoff comment.

## Issue 3 — Fetch, compare IDs, and schedule

**Owner:** ingest (OpenClaw). **Depends on:** Issue 2 above. The manager applies `gate:ingest-acceptance` to this ticket so the independent black-box test is mandatory before review.

Fetch the chosen source on a schedule. Derive a stable ID from the feed ID or link hash; compare against stored IDs in plain code. Do not use an LLM for the comparison. Provide a documented manual run command so reviewers do not wait for the schedule. Make failed fetches persist as failed runs. A cron/systemd timer is sufficient; Hermes cron is optional.

**Acceptance:** first run reports every item new; unchanged second run reports zero; adding one item reports exactly one. Repeated items never reappear as new. Add the thin `product-acceptance.sh` adapter defined in `factory-tests/README.md`, which lets factory-owned tests exercise the real ingest code from CI. Include command output or test logs for all three cases.

## Issue 4 — Public briefing and history page

**Owner:** page (OpenClaw). **Depends on:** Issues 2 and 3 above.

Serve a public page with latest dated briefing at the top, number of new items, and one short line plus link per new item. Below it show one row per run with timestamp, success/failure mark, and new-item count. No login. If the first run is shown, label it as the baseline. Keep agent dashboards on localhost.

**Acceptance:** page loads in a browser using the stored data; latest run and history agree with the store; a zero-new run and a failed run are visible.

## Issue 5 — Run-now demo trigger

**Owner:** page (OpenClaw). **Depends on:** Issues 3 and 4 above.

Provide either a documented SSH command or a public Run now button. If public, add rate limiting and prevent overlapping runs. The product must remain usable when the source or model is unavailable.

**Acceptance:** a reviewer can trigger a run during the demo; an unchanged source adds a history row with zero new items. A public trigger cannot be spammed into unlimited model calls.

## Issue 6 — Review and acceptance gate

**Owner:** manager (Hermes) tracking the reviewer and tester gates on each builder PR. **Blocked by:** Issues 2–5 above, each of which must have a merged PR. This is a tracking ticket, not a separate review/test dispatch label.

Reviewer checks each PR against its issue and requests changes with exact reasons when needed. Tester executes the first/second/third run sequence, verifies failure persistence and the public page, and opens a linked bug issue for any failure. Both post actual model/token estimates and trace excerpts. Manager requeues rejected work.

**Acceptance:** ticket trail contains at least one real review decision and tester evidence. Do not manufacture a rejection; if no defect occurs, record that honestly.

## Issue 7 — Deployment and delivery evidence

**Owner:** manager (Hermes), with an `agent:page` builder ticket for product service deployment and recovery scripts (the page builder also fills the optional ops role). **Blocked by:** Issues 4–6 above. The queue labels this issue `briefing:needs-manager` when those prerequisites complete.

Bring the product up on the single AWS EC2 VM with a public URL that opens the Daily Briefing page, not an OpenClaw or Hermes dashboard. Keep agent dashboards bound to localhost. Have a builder add `product-service.sh` with `prepare`, `restart`, and `smoke` commands as specified in `agents/RECOVERY.md`. Use `agents/release-product.sh` to deploy a merged revision, automatically restore the prior release after a failed smoke check, and exercise an explicit rollback. Keep persistent run data outside the release checkout and avoid destructive migrations. The manager verifies the deployment and rollback ticket through the same PR/review/test gates. Write `DELIVERY.md` with the agent roster (name, runtime, role, actual model, and tools for each agent), a ticket flow diagram from product need to merged code, actual contribution per agent, something that broke and how it was caught or fixed (if one occurred), what to change next, reproduction steps, and a per-agent/per-model token table split into planning, coding, review/test, and retries. Include real trace excerpts for a handoff and any review rejection or retry. Report estimates explicitly as estimates.

**Acceptance:** live link loads the briefing product and its run history, a failed smoke check can restore the previous release without losing run history, this same repo contains product code, `infra/`, and `agents/`, issue/PR trail is inspectable, and the document lets someone reproduce the factory setup with `python agents/setup/apply.py` (or Terraform and `agents/setup/agent-setup.sh` in manual mode).

## Suggested ticket state labels

The queue uses `briefing:waiting`, `briefing:ready`, `briefing:in-progress`, `briefing:review`, `briefing:test`, `briefing:needs-manager`, `briefing:merge-ready`, `briefing:blocked`, and `briefing:done`. Builder issues also carry `agent:ingest` or `agent:page`. The manager links blocked-by dependencies at issue creation; the poller moves a waiting ticket to ready only after the blockers close and any builder PRs merge. It also returns stale or conflicting PRs to builders for an updated commit and fresh review/test. Use comments with “from → to”, timestamp, PR URL, and next action at every handoff. Labels are routing state; the issue and PR comments are the durable evidence.
