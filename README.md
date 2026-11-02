# Daily Briefing delivery setup

This repository provisions **one Oracle Cloud A1 VM** and contains scripts and prompts for a five-agent OpenClaw + Hermes delivery team. The product implementation is assigned through [ISSUES.md](ISSUES.md).

## One-command VM and agent setup

Prepare these inputs once on the machine that will run Terraform:

1. Commit this repository's default branch. If it is not published yet, run `bash agents/publish-repo.sh OWNER/REPO public` after local `gh auth login`; that script publishes and pushes it. Otherwise push the default branch yourself. The bootstrap checks that the local checkout is clean and matches the pushed default branch. A private repo can be cloned when its `GH_TOKEN` has access, but GitHub Free branch protection may require a public repo.
2. Install Terraform, Python 3, Git, SSH/SCP, and configure OCI API-key authentication (`~/.oci/config`).
3. Create an SSH key pair. Copy `infra/terraform.tfvars.example` to `infra/terraform.tfvars` and fill in the compartment, home region, availability domain, your public IP `/32` for SSH, and public/private key paths. By default Terraform creates one VCN, internet gateway, route table, security list, and public subnet with SSH limited to that `/32` and HTTP/HTTPS open for the future product. Set `subnet_id` only if you prefer an existing public subnet with suitable ingress rules.
4. Copy `agents/.env.sample` to the Git-ignored `agents/secrets.env`. Fill in fresh Ollama and OpenRouter free-tier credentials, current `:free` fallback model IDs, and a GitHub `GH_TOKEN` with access to this repo's contents, Issues, PRs, labels, and commit statuses. Keep this file private. The local bootstrap reads it and copies it to the VM over SSH; Terraform receives neither the secret values nor the file contents in state.
5. Run **`python agents/setup/apply.py`**. This one command runs `terraform init` and `terraform apply`, creates the VM, installs OpenClaw and Hermes, configures the five agents, enables the GitHub issue queue, and dispatches the Hermes manager to read the brief and create tickets. If setup fails, Terraform reports the failure; do not treat a created VM alone as a completed factory.

After setup, open the manager's private interactive CLI with `ssh -t ubuntu@PUBLIC_IP 'cd ~/briefing-repo && bash agents/manager-chat.sh'`. The manager has the briefing in `docs/03-daily-briefing.pdf` and `ISSUES.md`; you can give it further instructions in that chat. The script shares the one-request model lock with the queue. For private dashboards, tunnel `ssh -L 18789:127.0.0.1:18789 -L 9119:127.0.0.1:9119 ubuntu@PUBLIC_IP`. OpenClaw uses port 18789; Hermes uses port 9119 when its optional web extra installs. In the Hermes dashboard, choose the manager profile in the Chat tab.

If you set `bootstrap_agents = false`, Terraform creates only the VM. In that manual mode, clone the repo, copy `agents/secrets.env` to the VM, run `bash agents/setup/agent-setup.sh`, authenticate `gh`, run `bash agents/enable-queue.sh`, and dispatch the manager with `bash agents/dispatch.sh manager`. Builder PRs still need `Agent PR` CI, reviewer and tester verdicts, and human review and merge via `bash agents/merge-check.sh ISSUE_NUMBER`.

The script uses the official runtime installers. The model IDs in `agents/secrets.env` are tunable and should be checked against the provider's live catalog. A configured OpenRouter free fallback is required for both runtimes. The dispatcher serializes worker calls for the free Ollama tier. After real runs, use `bash agents/usage-report.sh` and fill `DELIVERY.template.md` as `DELIVERY.md` with actual evidence.

The poller caps builder attempts at three per issue by default (`BRIEFING_MAX_BUILD_ATTEMPTS` can change it). The factory-owned `factory-tests/acceptance.py` runs from the default branch once the builder adds the real-product adapter on the stable-ID ticket. `agents/release-product.sh` provides revision-pinned deploy and rollback mechanics; the deployment builder must add the product-specific `product-service.sh` adapter and demonstrate it on the VM.

After agent work, run `bash agents/usage-report.sh` for token activity and `python3 agents/trace-report.py --output .local-evidence/trace-excerpts.md` for linked handoff and rejection or retry excerpts to review for `DELIVERY.md`.

Terraform creates one VCN, public subnet, internet gateway, route table, and security list unless an existing `subnet_id` is supplied. It creates no load balancer, database, or product service. Its local SSH bootstrap installs the agent runtimes on the VM when `bootstrap_agents = true`. The defaults match the brief: `VM.Standard.A1.Flex`, 2 OCPU, 12 GB, Ubuntu 24.04 Arm image in the region you supply.

The old local notes contained a pasted model credential. Treat it as compromised and rotate it before using this setup.

## Public product link

The live link submitted for review must open the **Daily Briefing product page**: latest dated briefing, new items, and run history. The agent dashboards are private administration tools and must stay on localhost. The `product_url` Terraform output is the intended HTTP address of the VM; it becomes usable only after the agents build and deploy the product. The deployment ticket must verify the actual page at that address, or record a working HTTPS or Cloudflare Tunnel product URL in `DELIVERY.md` if that is the chosen hosting route. The product code, `infra/`, `agents/`, and ticket trail all belong in this same repository.
