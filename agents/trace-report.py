#!/usr/bin/env python3
"""Extract real GitHub issue handoff and rejection/retry comments for DELIVERY.md."""

import argparse
import json
import subprocess
from pathlib import Path


def gh_json(*args):
    result = subprocess.run(["gh", *args], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def fetch_issues():
    summaries = gh_json("issue", "list", "--state", "all", "--limit", "1000", "--json", "number,url,title")
    return [gh_json("issue", "view", str(item["number"]), "--json", "number,url,title,comments")
            for item in summaries]


def actor_login():
    result = subprocess.run(["gh", "api", "user", "-q", ".login"], check=True, capture_output=True, text=True)
    return result.stdout.strip()


def classify(body):
    if body.startswith("REVIEW: CHANGES REQUESTED") or body.startswith("TEST: FAILED"):
        return "rejection"
    if body.startswith("ACTIVITY:") and any(line.startswith("Phase: retries") for line in body.splitlines()):
        return "retry"
    if body.startswith("HANDOFF:"):
        return "handoff"
    return None


def gather(issues, actor):
    found = {"handoff": [], "rejection": [], "retry": []}
    for issue in issues:
        for comment in issue.get("comments") or []:
            if (comment.get("author") or {}).get("login") != actor:
                continue
            body = comment.get("body") or ""
            kind = classify(body)
            if kind:
                found[kind].append({
                    "issue": issue.get("number"),
                    "issue_url": issue.get("url"),
                    "comment_url": comment.get("url") or issue.get("url"),
                    "created_at": comment.get("createdAt") or "time unavailable",
                    "body": body,
                })
    for entries in found.values():
        entries.sort(key=lambda entry: (entry["created_at"], entry["issue"] or 0))
    return found


def excerpt(entry):
    lines = [line for line in entry["body"].splitlines() if line.strip()]
    quoted = ["> " + line for line in lines[:6]]
    if len(lines) > 6:
        quoted.append("> [Further lines omitted; open the linked comment.]" )
    return "\n".join([
        f"[Issue #{entry['issue']} comment]({entry['comment_url']}) — {entry['created_at']}",
        "",
        *quoted,
    ])


def render(issues, actor):
    found = gather(issues, actor)
    lines = [
        "# Delivery trace excerpts",
        "",
        f"Source: GitHub issue comments by `{actor}`. Text below is copied from the linked comments.",
        "",
        "## Handoffs",
        "",
    ]
    handoffs = found["handoff"][:3]
    if handoffs:
        lines.extend("\n\n".join(excerpt(entry) for entry in handoffs).splitlines())
    else:
        lines.append("No handoff comments found yet.")
    lines.extend(["", "## Review rejection or retry", ""])
    evidence = found["rejection"][:2] or found["retry"][:2]
    if evidence:
        lines.extend("\n\n".join(excerpt(entry) for entry in evidence).splitlines())
    else:
        lines.append("No real review rejection or retry found yet; do not invent one.")
    lines.extend(["", "Review the excerpt and linked issue comments before copying it into DELIVERY.md.", ""])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", help="Write the report to this path; otherwise print it")
    parser.add_argument("--input-json", help="Offline issue-view JSON fixture for testing")
    parser.add_argument("--actor", help="Trusted GitHub login; required with --input-json")
    args = parser.parse_args()
    if args.input_json:
        if not args.actor:
            parser.error("--actor is required with --input-json")
        issues = json.loads(Path(args.input_json).read_text(encoding="utf-8"))
        actor = args.actor
    else:
        issues = fetch_issues()
        actor = args.actor or actor_login()
    report = render(issues, actor)
    if args.output:
        path = Path(args.output)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(report, encoding="utf-8")
        print(path)
    else:
        print(report, end="")


if __name__ == "__main__":
    main()
