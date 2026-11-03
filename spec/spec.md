# Daily Briefing Product Spec:

Build a small scheduled briefing product

Tech Stack: Nextjs (Full Stack) + Local Files in vm for persistent storage

1. on schedule read a free public RSS feed, a public source (https://news.ycombinator.com/rss)

2. Persist every run, including its time, success or failure, error on failure, and items observed. History must survive a process restart. Use files in the vm to store instead of a db

3. it needs to Work out what is new since the last run. Give each item a stable ID (the feed's own ID, or a hash of its link) and compare it with what you stored, so the briefing never repeats an item. The first run has nothing to compare with, so everything is new; say so on the page.

4. Serve a public page on localhost without login. Show the latest dated briefing, new-item count, a short line and link for each new item, and a history row for every run with time, success or failure, and new-item count. Label the first run as the baseline. (so the public should be served at public_ip_of_vm:3000) running at port 300 (usee Nextjs for it)

5. Provide a documented command or a Run now button so a reviewer can trigger a run. Rate-limit a public button and prevent overlapping runs

6. Publish a dated briefing on a public page. The latest briefing sits at the top: the date, how many items are new, and a short line and link for each. Below it is a run history with one row per run: its time, a ✓ or ✗, and the number of new items. No login.

7. Keep several real runs in history, including a zero-new run and a failed run. The product's scheduler may be a simple systemd timer or cron job.

8. The comparison itself should be plain code, not a model's guess. If you also use a free model to write a one-line summary of each new item, handle quota errors (HTTP 402 or 429) by publishing the plain list instead (using the open router model used in the vm). The public URL must show this product

# SAMPLE RUN:
You open the public link. At the top: "Briefing · Oct 14 · 4 new since the last run", with four short items and their links. Below it, a run history of the last handful of runs, each marked ✓ or ✗ with its count of new items, including a run that found nothing new. Press "Run now" and a new row appears, showing 0 new because nothing changed.
