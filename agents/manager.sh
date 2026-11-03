#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ip="$(terraform "-chdir=$repo_dir/infra" output -raw public_ip)"
key="$(terraform "-chdir=$repo_dir/infra" output -raw ssh_private_key_path)"
exec ssh -t -i "$key" "ubuntu@$ip" 'cd ~/briefing-repo && bash agents/manager-chat.sh'
