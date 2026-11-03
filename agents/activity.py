#!/usr/bin/env python3
"""Keep one inspectable token/activity record for every agent dispatch."""

import argparse
import json
import os
from collections import defaultdict
from pathlib import Path


PHASES = {
    "manager": ("Hermes", "planning"),
    "builder1": ("OpenClaw", "coding"),
    "builder2": ("OpenClaw", "coding"),
    "reviewer": ("Hermes", "review/test"),
    "tester": ("Hermes", "review/test"),
}
MODEL_VARS = {
    "manager": "HERMES_MANAGER_MODEL",
    "builder1": "OPENCLAW_BUILDER_MODEL",
    "builder2": "OPENCLAW_BUILDER_MODEL",
    "reviewer": "HERMES_REVIEWER_MODEL",
    "tester": "HERMES_TESTER_MODEL",
}


def read_json(path):
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream)
    except (OSError, ValueError):
        return None


def token_number(value):
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else None


def model_name(provider, model):
    if not isinstance(model, str) or not model:
        return None
    if "/" in model:
        return model
    if isinstance(provider, str) and provider:
        return provider + "/" + model
    return model


def extract_usage(raw, runtime):
    if not isinstance(raw, dict):
        return None
    if runtime == "OpenClaw":
        # `agent exec --json` uses a flat envelope; gateway-backed `agent
        # --json` places run statistics under result.meta.agentMeta.
        result = raw.get("result") if isinstance(raw.get("result"), dict) else raw
        meta = result.get("meta") if isinstance(result.get("meta"), dict) else {}
        agent_meta = meta.get("agentMeta") if isinstance(meta.get("agentMeta"), dict) else {}
        stats = agent_meta if agent_meta else result
        usage = stats.get("usage") if isinstance(stats.get("usage"), dict) else {}
        total = token_number(usage.get("total"))
        if total is None:
            total = token_number(usage.get("total_tokens"))
        if total is None:
            total = token_number(usage.get("totalTokens"))
        return {
            "model": model_name(stats.get("provider"), stats.get("model")),
            "input": token_number(usage.get("input", usage.get("input_tokens", usage.get("inputTokens")))),
            "output": token_number(usage.get("output", usage.get("output_tokens", usage.get("outputTokens")))),
            "total": total,
            "method": "OpenClaw --json per-run usage; final model may differ from models used in retries",
            "model_attribution": "final model; check raw result if fallback attempts used",
        }
    grand = raw.get("total_including_auxiliary")
    grand = grand if isinstance(grand, dict) else {}
    main = token_number(raw.get("total_tokens"))
    auxiliary = raw.get("auxiliary")
    auxiliary = auxiliary if isinstance(auxiliary, dict) else {}
    auxiliary_tokens = token_number(auxiliary.get("total_tokens"))
    total = token_number(grand.get("total_tokens"))
    if total is None and main is not None:
        total = main + (auxiliary_tokens or 0)
    return {
        "model": model_name(raw.get("provider"), raw.get("model")),
        "input": token_number(raw.get("input_tokens")),
        "output": token_number(raw.get("output_tokens")),
        "total": total,
        "main_tokens": main,
        "auxiliary_tokens": auxiliary_tokens,
        "method": "Hermes --usage-file total including auxiliary calls",
        "model_attribution": (
            "main model known; auxiliary model attribution needs raw usage review"
            if auxiliary_tokens else "reported model"
        ),
    }


def write_json(path, data):
    temp = path.with_name(path.name + ".tmp")
    with temp.open("w", encoding="utf-8", newline="\n") as stream:
        os.chmod(temp, 0o600)
        json.dump(data, stream, indent=2, sort_keys=True)
        stream.write("\n")
    os.replace(temp, path)


def activities(usage_dir):
    for path in sorted(usage_dir.glob("*.activity.json")):
        data = read_json(path)
        if isinstance(data, dict):
            yield path, data


def record(args):
    usage_dir = Path(args.usage_dir)
    usage_dir.mkdir(parents=True, exist_ok=True)
    path = usage_dir / (args.run_id + ".activity.json")
    if path.exists():
        raise SystemExit("Activity already exists: " + str(path))
    prior = sum(
        1 for _, item in activities(usage_dir)
        if args.issue and args.source_stage != "interactive-chat"
        and item.get("source_stage") != "interactive-chat"
        and item.get("agent") == args.agent and item.get("issue") == args.issue
    )
    runtime, base_phase = PHASES[args.agent]
    raw_name = args.run_id + (".openclaw.json" if runtime == "OpenClaw" else ".hermes.json")
    raw = read_json(usage_dir / raw_name)
    extracted = extract_usage(raw, runtime)
    configured = None
    if args.agent in ("manager", "reviewer") and os.environ.get("OPENROUTER_API_KEY"):
        configured = "openrouter/" + os.environ.get(
            "OPENROUTER_REASONING_MODEL", "nvidia/nemotron-3-ultra-550b-a55b:free")
    elif os.environ.get("OLLAMA_MODEL"):
        configured = ("ollama-cloud/" if runtime == "OpenClaw" else "") + os.environ["OLLAMA_MODEL"]
    else:
        configured = os.environ.get(MODEL_VARS[args.agent]) or None
    token_total = extracted.get("total") if extracted else None
    item = {
        "schema_version": 1,
        "activity_type": "agent_run",
        "run_id": args.run_id,
        "agent": args.agent,
        "runtime": runtime,
        "issue": args.issue,
        "task": args.task or ("issue #" + args.issue if args.issue else "campaign startup"),
        "purpose": args.purpose or base_phase,
        "source_stage": args.source_stage,
        "started_at": args.started_at,
        "finished_at": args.finished_at,
        "exit_code": args.exit_code,
        "attempt": prior + 1,
        "is_repeat_dispatch": prior > 0,
        "base_phase": base_phase,
        "report_phase": "retries" if prior else base_phase,
        "configured_model": configured,
        "model": extracted.get("model") if extracted else None,
        "model_source": "runtime usage" if extracted and extracted.get("model") else "unavailable",
        "model_attribution": extracted.get("model_attribution") if extracted else "unavailable",
        "tokens": {
            "input": extracted.get("input") if extracted else None,
            "output": extracted.get("output") if extracted else None,
            "total": token_total,
            "main": extracted.get("main_tokens") if extracted else None,
            "auxiliary": extracted.get("auxiliary_tokens") if extracted else None,
            "status": "measured" if token_total is not None else "unavailable",
            "method": extracted.get("method") if token_total is not None else "Runtime did not provide a readable per-run total",
        },
        "raw_usage_file": raw_name if raw is not None else None,
    }
    write_json(path, item)


def estimate(args):
    path = Path(args.usage_dir) / (args.run_id + ".activity.json")
    item = read_json(path)
    if not isinstance(item, dict):
        raise SystemExit("Unknown run ID: " + args.run_id)
    if item["tokens"]["status"] == "measured":
        raise SystemExit("Measured usage cannot be replaced with an estimate")
    item["model"] = args.model
    item["model_source"] = "manual estimate"
    item["model_attribution"] = "estimated from: " + args.method
    item["tokens"].update({"total": args.tokens, "status": "estimated", "method": args.method})
    write_json(path, item)


def comment(args):
    path = Path(args.usage_dir) / (args.run_id + ".activity.json")
    item = read_json(path)
    if not isinstance(item, dict):
        raise SystemExit("Unknown run ID: " + args.run_id)
    tokens = item["tokens"]
    total = tokens["total"]
    print("ACTIVITY: agent run finished")
    print("Run: " + item["run_id"])
    print("Agent: " + item["agent"] + " (" + item["runtime"] + ")")
    print("Issue: " + ("#" + item["issue"] if item["issue"] else "unassigned"))
    print("Task: " + item.get("task", "unknown"))
    print("Purpose: " + item.get("purpose", "unknown"))
    print("Phase: " + item["report_phase"] + " (attempt " + str(item["attempt"]) + ")")
    print("Exit code: " + str(item["exit_code"]))
    print("Model: " + (item["model"] or "unknown; configured " + (item["configured_model"] or "unknown")))
    print("Tokens: " + (str(total) if total is not None else "unknown") + " (" + tokens["status"] + ")")
    print("Method: " + tokens["method"])
    print("Evidence: .local-evidence/usage/" + path.name + " (private VM file)")


def cell(value):
    return "unknown" if value is None or value == "" else str(value).replace("\t", " ").replace("\n", " ")


def report(args):
    usage_dir = Path(args.usage_dir)
    rows = list(activities(usage_dir)) if usage_dir.is_dir() else []
    if not rows:
        raise SystemExit("No activity records yet. Run an agent first.")
    print("RUNS")
    print("run_id\tagent\tissue\ttask\tpurpose\tphase\tattempt\tmodel\ttokens\tstatus\tmodel_attribution\texit\tevidence")
    totals = defaultdict(lambda: {"measured": 0, "estimated": 0, "unavailable": 0, "components": 0})
    issue_totals = defaultdict(lambda: {"measured": 0, "estimated": 0, "unknown_runs": 0, "runs": 0})
    for path, item in rows:
        tokens = item.get("tokens") or {}
        status = tokens.get("status", "unavailable")
        model = item.get("model")
        total = token_number(tokens.get("total"))
        issue_key = (item.get("issue") or "unassigned", item.get("agent", "unknown"),
                     item.get("purpose") or item.get("report_phase", "unknown"))
        issue_totals[issue_key]["runs"] += 1
        if status in ("measured", "estimated") and total is not None:
            issue_totals[issue_key][status] += total
        else:
            issue_totals[issue_key]["unknown_runs"] += 1
        pieces = [(model or "unknown", total)]
        if item.get("runtime") == "Hermes" and status == "measured" and total is not None:
            main = token_number(tokens.get("main"))
            if main is None:
                pieces = [("unknown (Hermes mixed)", total)]
            else:
                main = min(main, total)
                pieces = [(model or "unknown", main)]
                if total > main:
                    pieces.append(("unknown (Hermes auxiliary)", total - main))
        for piece_model, piece_tokens in pieces:
            key = (item.get("agent", "unknown"), piece_model, item.get("report_phase", "unknown"))
            totals[key]["components"] += 1
            if status in ("measured", "estimated") and piece_tokens is not None:
                totals[key][status] += piece_tokens
            else:
                totals[key]["unavailable"] += 1
        print("\t".join(map(cell, (
            item.get("run_id"), item.get("agent"), item.get("issue") or "unassigned",
            item.get("task"), item.get("purpose"),
            item.get("report_phase"), item.get("attempt"), model,
            tokens.get("total"), status, item.get("model_attribution"), item.get("exit_code"), path.name,
        ))))
    print("\nBY_ISSUE_AND_PURPOSE")
    print("issue\tagent\tpurpose\tmeasured_tokens\testimated_tokens\tunknown_runs\truns")
    for key, values in sorted(issue_totals.items()):
        print("\t".join(map(cell, (*key, values["measured"], values["estimated"],
                                   values["unknown_runs"], values["runs"]))))
    print("\nTOTALS")
    print("agent\tmodel\tphase\tmeasured_tokens\testimated_tokens\tunknown_runs\tcomponents")
    for key, values in sorted(totals.items()):
        print("\t".join(map(cell, (*key, values["measured"], values["estimated"], values["unavailable"], values["components"]))))
    print("\nRepeat dispatches for the same agent and issue are classified as retries; review raw activity records for context.")
    print("Unknown usage is never counted as zero. Hermes auxiliary tokens with no model identity appear under unknown (Hermes auxiliary).")
    print("OpenClaw totals are grouped by the reported final model; fallback attempts may need manual per-model attribution.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    rec = commands.add_parser("record")
    rec.add_argument("--usage-dir", required=True)
    rec.add_argument("--run-id", required=True)
    rec.add_argument("--agent", choices=PHASES, required=True)
    rec.add_argument("--issue", default="")
    rec.add_argument("--task", default="")
    rec.add_argument("--purpose", default="")
    rec.add_argument("--started-at", required=True)
    rec.add_argument("--finished-at", required=True)
    rec.add_argument("--exit-code", type=int, required=True)
    rec.add_argument("--source-stage", default="manual")
    rec.set_defaults(func=record)
    est = commands.add_parser("estimate")
    est.add_argument("--usage-dir", required=True)
    est.add_argument("--run-id", required=True)
    est.add_argument("--model", required=True)
    est.add_argument("--tokens", type=int, required=True)
    est.add_argument("--method", required=True)
    est.set_defaults(func=estimate)
    com = commands.add_parser("comment")
    com.add_argument("--usage-dir", required=True)
    com.add_argument("--run-id", required=True)
    com.set_defaults(func=comment)
    rep = commands.add_parser("report")
    rep.add_argument("--usage-dir", required=True)
    rep.set_defaults(func=report)
    args = parser.parse_args()
    if args.command == "estimate" and args.tokens < 0:
        parser.error("--tokens must be nonnegative")
    args.func(args)


if __name__ == "__main__":
    main()
