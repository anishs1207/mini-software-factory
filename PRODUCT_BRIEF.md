# Daily Briefing product brief

The agents build a small scheduled briefing in this repository. Keep the product small enough to build, review, test, and deploy with a clear GitHub ticket and PR trail.

## Required product

1. Read one free public RSS feed or API on a schedule. A synthetic feed with made-up items is acceptable for a reliable demo. Use no paid key or personal data.
2. Persist every run, including its time, success or failure, error on failure, and items observed. History must survive a process restart.
3. Identify new items with stable IDs from the source or a hash of each link. Compare IDs in ordinary code. Every item is new on the first run; an unchanged second run has zero new items; a new ID appears once even if its title matches an old item.
4. Serve a public page without login. Show the latest dated briefing, new-item count, a short line and link for each new item, and a history row for every run with time, success or failure, and new-item count. Label the first run as the baseline.
5. Provide a documented command or a Run now button so a reviewer can trigger a run. Rate-limit a public button and prevent overlapping runs.

The source comparison does not need a model. If you use a free model to summarize items, publish the plain list when that model returns HTTP 402 or 429. Keep several real runs in history, including a zero-new run and a failed run. The product's scheduler may be a simple systemd timer or cron job.

The public URL must show this product, not an agent dashboard. Keep OpenClaw and Hermes dashboards on localhost. Use `ISSUES.md` for ticket order and acceptance criteria; the builders write the product code, the reviewer and tester gate each PR, and the human owner reviews and merges.
