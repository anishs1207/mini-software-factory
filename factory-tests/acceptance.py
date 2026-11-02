"""Factory-owned black-box checks for the agent-built ingest core.

The builder supplies product-acceptance.sh as a thin adapter to real product code.
This file is read from the default branch during CI, so a builder PR cannot edit
the assertions it is evaluated against.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def invoke(adapter, action, *args):
    result = subprocess.run(
        ["bash", str(adapter), action, *(str(arg) for arg in args)],
        text=True,
        capture_output=True,
        timeout=90,
        check=False,
    )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise AssertionError(
            f"{action} did not return JSON; exit={result.returncode}; stderr={result.stderr}"
        ) from exc
    return result, payload


def item(item_id, title):
    return {"id": item_id, "title": title, "link": f"https://example.test/{item_id}"}


def check_run(adapter, feed, store, expected_count, expected_success):
    result, payload = invoke(adapter, "run", feed, store)
    require(isinstance(payload, dict), "run output must be a JSON object")
    require(payload.get("success") is expected_success, "run success flag is wrong")
    require(payload.get("new_count") == expected_count, "run new_count is wrong")
    if expected_success:
        require(result.returncode == 0, "a successful run must exit zero")


def main():
    require(len(sys.argv) == 2, "usage: acceptance.py PRODUCT_ADAPTER")
    adapter = Path(sys.argv[1]).resolve()
    require(adapter.is_file(), "product acceptance adapter is missing")
    with tempfile.TemporaryDirectory(prefix="briefing-acceptance-") as temporary:
        root = Path(temporary)
        feed = root / "feed.json"
        store = root / "store"
        store.mkdir()

        feed.write_text(json.dumps({"items": [item("alpha", "Shared title")]}))
        check_run(adapter, feed, store, 1, True)
        check_run(adapter, feed, store, 0, True)

        # Same ID with a changed title is old; different ID with the same title is new.
        feed.write_text(
            json.dumps(
                {"items": [item("alpha", "Updated title"), item("beta", "Shared title")]}
            )
        )
        check_run(adapter, feed, store, 1, True)

        feed.unlink()
        check_run(adapter, feed, store, 0, False)

        result, history = invoke(adapter, "history", store)
        require(result.returncode == 0, "history must exit zero")
        require(isinstance(history, list) and len(history) == 4, "all four runs must persist")
        require(
            [(run.get("success"), run.get("new_count")) for run in history]
            == [(True, 1), (True, 0), (True, 1), (False, 0)],
            "history status or new counts are wrong",
        )
        for run in history:
            require(isinstance(run.get("timestamp"), str) and run["timestamp"], "run timestamp missing")
            require(isinstance(run.get("items"), list), "observed items must be persisted per run")
        require(
            {entry.get("id") for entry in history[2]["items"]} == {"alpha", "beta"},
            "the third run must persist both observed stable IDs",
        )
        require(isinstance(history[3].get("error"), str) and history[3]["error"], "failure reason missing")
    print("Factory acceptance passed: first, unchanged, new ID, and persisted failure")


if __name__ == "__main__":
    main()
