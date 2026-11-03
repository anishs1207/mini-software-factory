#!/usr/bin/env python3
"""Initialize Terraform, bootstrap the VM, then open the manager over SSH."""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-chat", action="store_true", help="Finish after apply without opening SSH")
    options = parser.parse_args()
    if not shutil.which("terraform"):
        raise SystemExit("Install Terraform on this machine before running apply.py")
    python_command = "python3" if sys.platform != "win32" and shutil.which("python3") else "python"
    for args in (
        ["terraform", "-chdir=infra", "init"],
        ["terraform", "-chdir=infra", "apply", "-auto-approve", f"-var=bootstrap_python={python_command}"],
    ):
        print("Running " + " ".join(args), flush=True)
        subprocess.run(args, cwd=ROOT, check=True)
    if options.no_chat:
        return
    ip = subprocess.check_output(["terraform", "-chdir=infra", "output", "-raw", "public_ip"],
                                 cwd=ROOT, text=True).strip()
    key = subprocess.check_output(["terraform", "-chdir=infra", "output", "-raw", "ssh_private_key_path"],
                                  cwd=ROOT, text=True).strip()
    print(f"Opening manager on AWS VM {ip} over SSH. Exit chat to resume the issue queue.", flush=True)
    subprocess.run(["ssh", "-tt", "-i", key, f"ubuntu@{ip}",
                    "cd ~/briefing-repo && bash agents/manager-chat.sh"], check=True)


if __name__ == "__main__":
    main()
