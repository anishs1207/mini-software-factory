#!/usr/bin/env python3
"""Run a product server briefly, verify HTTP, and always stop it."""

import argparse
import os
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("worktree", type=Path)
    parser.add_argument("--standalone", action="store_true", help="legacy Next.js standalone server")
    parser.add_argument("--path", default="/", help="HTTP path to probe")
    parser.add_argument("--command", nargs=argparse.REMAINDER, help="foreground product server command")
    args = parser.parse_args()
    worktree = args.worktree.resolve(strict=True)
    wrapper = Path(__file__).resolve().parent / "run-product-command.sh"
    if args.standalone and not (worktree / ".next/standalone/server.js").is_file():
        parser.error("standalone server is missing; run the product build first")
    if not args.path.startswith("/"):
        parser.error("--path must begin with /")
    with socket.socket() as port_probe:
        port_probe.bind(("127.0.0.1", 0))
        port = port_probe.getsockname()[1]
    with tempfile.TemporaryFile(mode="w+t", encoding="utf-8") as output, tempfile.TemporaryDirectory() as data_dir:
        if args.command:
            command = args.command
        elif args.standalone:
            command = ["node", ".next/standalone/server.js"]
        elif (worktree / "product-service.sh").is_file():
            command = ["bash", "product-service.sh", "serve"]
        else:
            parser.error("supply --command or a product-service.sh with serve")
        process = subprocess.Popen(
            ["bash", str(wrapper), "env", f"PORT={port}", "HOSTNAME=127.0.0.1", f"FACTORY_DATA_DIR={data_dir}", *command],
            cwd=worktree,
            stdout=output,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f"Product server exited with status {process.returncode}")
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}{args.path}", timeout=2) as response:
                        if response.status == 200:
                            print(f"HTTP 200 from http://127.0.0.1:{port}{args.path}", flush=True)
                            return
                except (OSError, urllib.error.URLError):
                    pass
                time.sleep(1)
            raise RuntimeError("Product server did not return HTTP 200 within 45 seconds")
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
