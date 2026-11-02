# Delivery team

| Agent | Runtime | Role | Model variable |
| --- | --- | --- | --- |
| manager | Hermes profile | Orchestrator and ticket owner | `HERMES_MANAGER_MODEL` |
| ingest | OpenClaw agent | Feed, persistence, deduplication builder | `OPENCLAW_BUILDER_MODEL` |
| page | OpenClaw agent | Public page builder | `OPENCLAW_BUILDER_MODEL` |
| reviewer | Hermes profile | Independent PR reviewer | `HERMES_REVIEWER_MODEL` |
| tester | Hermes profile | Independent acceptance tester | `HERMES_TESTER_MODEL` |

One person runs `agents/dispatch.sh manager` to start the delivery. The manager creates GitHub Issues and labels ready builder tickets. After `agents/enable-queue.sh` is run, a systemd timer polls GitHub every two minutes and dispatches one labeled ticket at a time. Each dispatcher invocation loads the issue and comments and runs the named runtime. Builders open PRs; the queue verifies the expected PR branch before handing the issue to reviewer. Reviewer can request changes; tester can open a bug and return the ticket to a builder. The human owner merges only after review and test sign-off. This creates an inspectable trail without a hidden chat-only queue.

Hermes `delegate_task` is available to the manager for bounded planning subtasks, but profile switching and cross-runtime execution happen through the queue and dispatcher. A delegated child is not a substitute for the reviewer or tester gate.

The `agents/` prompts are role instructions. They do not implement the product. Run only one agent at a time on the Ollama free tier's single concurrent request. A free OpenRouter fallback is configured for both runtimes; for HTTP 402/429, record whether it actually succeeded. Never claim a fallback was tested until a real call succeeds.

The dispatcher writes local Hermes per-run usage JSON and OpenClaw gateway before/after snapshots under `.local-evidence/usage/`. Run `bash agents/usage-report.sh` for a tabular index. Attribute each ticket's planning, coding, review/test, and retry tokens in the issue/PR and `DELIVERY.md`. If a provider does not expose exact per-agent counts, label estimates as estimates and explain the method.

## Before dispatch

Run `gh auth login` on the VM and verify `gh repo view`. Give the VM's GitHub identity permission to create issues and PRs. Agents use explicit git author names in their commits; the PR and issue comments show the actual GitHub account used. Do not invent separate GitHub identities.
The dispatcher accepts issue bodies and comments only from that authenticated GitHub identity; the manager must create the routed issues from the VM's account. This keeps public issue comments from becoming agent instructions.

Run `bash agents/enable-queue.sh` after GitHub authentication. The queue recognizes `briefing:ready` with `agent:ingest` or `agent:page`; it moves an open builder PR with the required fields to `briefing:review`, then requires a reviewer verdict and tester verdict before `briefing:merge-ready`. Failure routes to `briefing:needs-manager`; the manager must record a `MANAGER:` decision and choose one next-stage label. A manager failure ends at `briefing:blocked`. Check `journalctl --user -u briefing-issue-poller.service` and `systemctl --user list-timers briefing-issue-poller.timer` to observe it.

For an OpenClaw workspace, `AGENTS.md` is copied into its isolated workspace. For Hermes, `SOUL.md` is copied into its profile. The repository copies remain the reviewable source of those instructions.
