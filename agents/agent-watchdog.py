#!/usr/bin/env python3
"""Run one gate agent and stop repeated slow or failing terminal calls."""

import argparse
import os
import re
import signal
import subprocess
import sys


SLOW_CALL = re.compile(r"\b(\d{3,})\.\d+s(?:\s|$)")
FAILED_COMMAND = re.compile(r"^✗ \$ (.+)")


def stop_child(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-slow-calls", type=int, default=2)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.max_slow_calls < 1 or not args.command:
        parser.error("a command and positive --max-slow-calls are required")

    process = subprocess.Popen(
        args.command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )

    def interrupted(_signum, _frame):
        stop_child(process)
        raise SystemExit(124)

    signal.signal(signal.SIGTERM, interrupted)
    slow_calls = 0
    failures = {}
    try:
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            match = SLOW_CALL.search(line)
            if match and int(match.group(1)) >= 150:
                slow_calls += 1
                if slow_calls >= args.max_slow_calls:
                    print(f"WATCHDOG: {slow_calls} terminal calls took at least 150s; stopping this gate run.", flush=True)
                    stop_child(process)
                    return 124
            match = FAILED_COMMAND.match(line)
            if match:
                command = match.group(1).strip()[:160]
                failures[command] = failures.get(command, 0) + 1
                if failures[command] >= 3:
                    print("WATCHDOG: same terminal command failed 3 times; stopping this gate run.", flush=True)
                    stop_child(process)
                    return 124
        return process.wait()
    finally:
        if process.poll() is None:
            stop_child(process)


if __name__ == "__main__":
    raise SystemExit(main())
