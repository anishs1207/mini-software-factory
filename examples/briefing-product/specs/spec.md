# Daily Briefing Product Spec (Technical Plan):

A small scheduled briefing. On a schedule it checks one public source, works out what is new since the last run, and publishes a dated briefing on a public page, with a history of every run. 

Tech Stack: Nextjs (Full Stack) + Local Files in VM for persistent storage

# Features:

1. On schedule read a free public RSS feed, a public source, use https://news.ycombinator.com/rss for it, underdtand how it returns data (it does not require an api key to carry it out)

2. Persist every run, including its time, success or failure, error on failure, and items observed. History must survive a process restart. Use local files in this VM to store instead of a Database

3. It needs to Work out what is new since the last run: Give each item a stable ID (the feed's own ID, or a hash of its link) and compare it with what you stored, so the briefing never repeats an item. The first run has nothing to compare with, so everything is new; say so on the page.

4. Serve a public page on localhost:3000 without login. Show the latest dated briefing, new-item count, a short line and link for each new item, and a history row for every run with time, success or failure, and new-item count. Label the first run as the baseline. (so the public should be served at public_ip_of_vm:3000) running at port 3000 (usee Nextjs for it). Publish a dated briefing on a public page. The latest briefing sits at the top: the date, how many items are new, and a short line and link for each. Below it is a run history with one row per run: its time, a ✓ or ✗, and the number of new items.

5. Provide a Run now button so a human reviewer testing the product can trigger a run. Rate-limit the button and prevent overlapping runs

7. Keep several real runs in history, including a zero-new run and a failed run. The product's scheduler may be a simple systemd timer or cron job. The comparison itself should be plain code, not a model's guess. 

# GOOD SAMPLE RUN:
You open the public link. At the top: "Briefing · Oct 14 · 4 new since the last run", with four short items and their links. Below it, a run history of the last handful of runs, each marked ✓ or ✗ with its count of new items, including a run that found nothing new. Press "Run now" and a new row appears, showing 0 new because nothing changed.
