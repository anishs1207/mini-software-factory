# Daily Briefing delivery setup

This repository provisions **one Oracle Cloud A1 VM** and contains scripts and prompts for a five-agent OpenClaw + Hermes delivery team. The product implementation is assigned through [ISSUES.md](ISSUES.md).

## Before provisioning

0. Commit this scaffold, then publish it with `bash agents/publish-repo.sh OWNER/REPO private` after `gh auth login`. This creates the GitHub repository and pushes the current commit. Choose `public` explicitly if the source repository should be public. Clone that repository on the VM.
1. Install Terraform and the OCI CLI, then configure local OCI API-key authentication (`~/.oci/config`).
2. Have an existing public subnet with internet routing and SSH access from your IP. Create an SSH public key and copy `infra/terraform.tfvars.example` to `infra/terraform.tfvars`. Fill in your compartment, region, availability domain, subnet ID, and SSH key path.
3. Run `terraform -chdir=infra init`, `terraform -chdir=infra plan`, and `terraform -chdir=infra apply`. Keep Terraform state local and private.
4. SSH to the `public_ip` output as `ubuntu`.

## Prepare the agent team on the VM

1. Clone this repository on the VM and run `cd <repo>`.
2. Copy `agents/secrets.env.example` to `agents/secrets.env`; put fresh Ollama Cloud and OpenRouter keys in it, select a current OpenRouter `:free` fallback model for both runtimes, and run `chmod 600 agents/secrets.env`.
3. Run `bash agent-setup.sh` as `ubuntu`. The script installs OpenClaw and Hermes, configures two OpenClaw builder agents and three Hermes profiles, and starts the OpenClaw Gateway bound to localhost.
4. Run `gh auth login` and verify `gh repo view`. Run `bash agents/enable-queue.sh` to enable the GitHub Issue poller, then `bash agents/dispatch.sh manager` to create and label tickets. The poller dispatches ready issues automatically every two minutes. Manual dispatch remains available: `bash agents/dispatch.sh ingest 2`, `bash agents/dispatch.sh reviewer 2`, etc.
5. Tunnel both local dashboards: `ssh -L 18789:127.0.0.1:18789 -L 9119:127.0.0.1:9119 ubuntu@PUBLIC_IP`. OpenClaw is on port 18789; Hermes analytics is on port 9119. If Hermes' optional web extra could not be installed, its CLI profiles still work and the script reports that limitation.

The script uses the official runtime installers. The model IDs in `agents/secrets.env` are tunable and should be checked against the provider's live catalog. A configured OpenRouter free fallback is required for both runtimes. The dispatcher serializes worker calls for the free Ollama tier. After real runs, use `bash agents/usage-report.sh` and fill `DELIVERY.template.md` as `DELIVERY.md` with actual evidence.

Terraform creates no VCN, subnet, internet gateway, firewall rule, load balancer, database, agent runtime, or product service. The referenced subnet must already permit a public IP and the required network access. No cloud-init commands run. The defaults match the brief: `VM.Standard.A1.Flex`, 2 OCPU, 12 GB, Ubuntu 24.04 Arm image in the region you supply.

The old local notes contained a pasted model credential. Treat it as compromised and rotate it before using this setup.
