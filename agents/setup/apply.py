#!/usr/bin/env python3
"""One command to initialize Terraform and apply the VM plus agent bootstrap."""

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def main():
    if not shutil.which("terraform"):
        raise SystemExit("Install Terraform on this machine before running apply.py")
    python_command = "python3" if sys.platform != "win32" and shutil.which("python3") else "python"
    for args in (
        ["terraform", "-chdir=infra", "init"],
        ["terraform", "-chdir=infra", "apply", "-auto-approve", f"-var=bootstrap_python={python_command}"],
    ):
        print("Running " + " ".join(args), flush=True)
        subprocess.run(args, cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
