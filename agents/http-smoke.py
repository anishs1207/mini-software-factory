#!/usr/bin/env python3
"""Run a product dev server briefly, verify HTTP, and always stop it."""

import argparse
import os
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("worktree", type=Path)
    args = parser.parse_args()
    worktree = args.worktree.resolve(strict=True)
    wrapper = Path(__file__).resolve().parent / "run-product-command.sh"
    with tempfile.TemporaryFile(mode="w+t", encoding="utf-8") as output:
        process = subprocess.Popen(
            ["bash", str(wrapper), "npm", "run", "dev"],
            cwd=worktree,
            stdout=output,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f"Dev server exited with status {process.returncode}")
                try:
                    with urllib.request.urlopen("http://127.0.0.1:3000/", timeout=2) as response:
                        if response.status == 200 and "text/html" in response.headers.get("Content-Type", ""):
                            print("HTTP 200 text/html from http://127.0.0.1:3000/", flush=True)
                            return
                except (OSError, urllib.error.URLError):
                    pass
                time.sleep(1)
            raise RuntimeError("Dev server did not return HTTP 200 within 45 seconds")
        except RuntimeError:
            output.seek(0)
            print(output.read()[-2000:])
            raise
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()


if __name__ == "__main__":
    main()
