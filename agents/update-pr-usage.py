#!/usr/bin/env python3
"""Put measured OpenClaw usage into an open builder PR after each turn."""

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path


def usage_line(usage_dir: Path, agent: str, issue: str) -> str | None:
    records = []
    for path in usage_dir.glob(f"*-{agent}-{issue}-*.activity.json"):
        record = json.loads(path.read_text(encoding="utf-8"))
        if record.get("agent") == agent and str(record.get("issue")) == issue:
            records.append(record)
    measured = [record["tokens"]["total"] for record in records
                if record.get("tokens", {}).get("status") == "measured"
                and isinstance(record["tokens"].get("total"), int)]
    if not measured:
        return None
    unknown = len(records) - len(measured)
    suffix = f"; {unknown} turn(s) unavailable" if unknown else ""
    return f"Tokens: {sum(measured)} measured across {len(measured)} OpenClaw turn(s){suffix}"


def with_usage(body: str, line: str) -> str:
    # Builders sometimes pass literal "\\n" in a shell argument to gh pr create.
    # Normalize only required metadata separators, leaving other Markdown alone.
    body = re.sub(r"\\n(?=(?:Agent|Model|Tests|Tokens):)", "\n", body)
    if re.search(r"(?im)^Tokens:.*$", body):
        return re.sub(r"(?im)^Tokens:.*$", line, body)
    return body.rstrip() + "\n" + line + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("usage_dir", type=Path)
    parser.add_argument("agent", choices=("builder1", "builder2"))
    parser.add_argument("issue")
    args = parser.parse_args()
    if not re.fullmatch(r"[1-9][0-9]*", args.issue):
        parser.error("issue must be a positive number")
    line = usage_line(args.usage_dir, args.agent, args.issue)
    if line is None:
        return
    branch = f"agent/{args.agent}/issue-{args.issue}"
    view = subprocess.run(["gh", "pr", "view", branch, "--json", "state,body,url"],
                          capture_output=True, text=True)
    if view.returncode:
        return  # The builder has not opened its PR yet.
    pr = json.loads(view.stdout)
    if pr["state"] != "OPEN":
        return
    body = with_usage(pr.get("body") or "", line)
    if body == pr.get("body"):
        return
    match = re.fullmatch(r"https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([1-9][0-9]*)", pr["url"])
    if not match:
        raise ValueError("Unexpected GitHub PR URL")
    endpoint = f"repos/{match.group(1)}/pulls/{match.group(2)}"
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".md") as file:
        json.dump({"body": body}, file)
        file.flush()
        subprocess.run(["gh", "api", "--method", "PATCH", endpoint, "--input", file.name],
                       check=True, capture_output=True, text=True)
    print(f"Updated {branch}: {line}", flush=True)


if __name__ == "__main__":
    main()
