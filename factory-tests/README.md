# Ingest acceptance adapter contract

The builder adds `product-acceptance.sh` with two commands. It is a thin adapter to the actual product implementation, not a second fake implementation.

- `bash product-acceptance.sh run FEED_JSON STORE_DIR` reads a synthetic JSON feed of `{ "items": [{ "id", "title", "link" }] }`, executes one real product run using `STORE_DIR` for persistent data, and writes one JSON object to stdout: `{ "success": true|false, "new_count": number }`. A failed fetch must still be persisted and reported as `success: false`.
- `bash product-acceptance.sh history STORE_DIR` reads the durable store in a fresh process and writes a JSON array, oldest first. Each row has `timestamp`, `success`, `new_count`, and `items` with stable `id` fields. A failed row also has a nonempty `error`.

The factory-owned [`acceptance.py`](acceptance.py) checks first run, unchanged second run, same ID with a changed title, a new ID with the same title, and a persisted failed run. CI reads this test from the default branch. The manager labels the stable-ID ticket `gate:ingest-acceptance`; the queue then requires this adapter and runs the independent test before review. Later PRs with the adapter also run the check. The manager and tester inspect the adapter to ensure it invokes the same code path as the scheduled product run. Before the stable-ID ticket, CI runs the builder's unit tests and the tester checks the ticket's narrower acceptance criteria.
