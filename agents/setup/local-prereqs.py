#!/usr/bin/env python3
"""Supply Terraform plan inputs without putting an SSH private key in state."""

import ipaddress
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path


def resolve_key_paths(query):
    root = Path(query["workspace_root"]).resolve()
    supplied_private = query.get("ssh_private_key_path", "").strip()
    supplied_public = query.get("ssh_public_key_path", "").strip()
    if supplied_private:
        private = Path(supplied_private).expanduser().resolve()
        public = Path(supplied_public).expanduser().resolve() if supplied_public else Path(str(private) + ".pub")
    elif supplied_public:
        public = Path(supplied_public).expanduser().resolve()
        if not str(public).endswith(".pub"):
            raise ValueError("A public key path without a private key path must end in .pub")
        private = Path(str(public)[:-4])
    else:
        private = root / ".local-evidence" / "terraform-ssh" / "id_ed25519"
        public = Path(str(private) + ".pub")
        private.parent.mkdir(parents=True, exist_ok=True)
        if not private.exists() and not public.exists():
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(private)],
                           check=True, capture_output=True, text=True)
    if not private.is_file() or not public.is_file():
        raise ValueError("SSH key pair is incomplete; provide both paths or remove the partial generated pair")
    public_key = public.read_text(encoding="utf-8").strip()
    if not public_key.startswith("ssh-ed25519 "):
        raise ValueError("The SSH public key must be ed25519")
    if os.name != "nt":
        private.chmod(0o600)
    return str(private), str(public), public_key


def operator_cidr(override):
    if override:
        network = ipaddress.IPv4Network(override, strict=False)
        if network.prefixlen != 32:
            raise ValueError("SSH access must use an IPv4 /32")
        return str(network)
    try:
        with urllib.request.urlopen("https://api.ipify.org", timeout=10) as response:
            address = response.read(100).decode("ascii").strip()
        return str(ipaddress.IPv4Address(address)) + "/32"
    except (OSError, ValueError) as error:
        raise ValueError("Cannot detect your public IPv4; set ssh_allowed_cidr in infra/terraform.tfvars") from error


def main():
    query = json.load(sys.stdin)
    cidr = operator_cidr(query.get("ssh_allowed_cidr", "").strip())
    private, public, public_key = resolve_key_paths(query)
    json.dump({"ssh_private_key_path": private, "ssh_public_key_path": public,
               "ssh_allowed_cidr": cidr, "public_key": public_key}, sys.stdout)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError, KeyError) as error:
        print("Terraform local prerequisite error: " + str(error), file=sys.stderr)
        raise SystemExit(1) from None
