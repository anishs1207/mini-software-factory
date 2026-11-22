# Software factory on Google Cloud

Terraform creates one Ubuntu Compute Engine `n4-standard-2` VM (2 vCPUs, 8 GiB RAM) in project `confer-assignment`, zone `asia-south1-a`. It creates a VPC, subnet, SSH firewall limited to the operator's current public IPv4 address, and a public product port 3000. The VM runs the Hermes manager, reviewer, tester, and two OpenClaw builders. The agent queue and GitHub issue trail are described in [agents/README.md](agents/README.md).

## Prepare

1. Install Terraform, Google Cloud CLI, Python 3, Git, SSH, SCP, and `ssh-keygen` locally. Sign in with `gcloud auth login` and select the project with `gcloud config set project confer-assignment`. Enable the Compute Engine API and billing in that project.
2. Put `OLLAMA_API_KEY` and a GitHub token with access to `anishs1207/confer-assignment` in ignored `agents/.env` or `agents/secrets.env`, following `agents/.env.sample`.
3. Commit and push this factory revision to the repository default branch. Bootstrap checks that the VM clones exactly that revision.
4. The current Terraform bootstrap is configured for the historical briefing recovery (`FACTORY_RESUME_ISSUE=1`). That path expects a local `spec/spec.md`, which is not checked in here. For that recovery, copy [the briefing spec](examples/briefing-product/specs/spec.md) to `spec/spec.md` and ensure the referenced GitHub issue and PR are in the expected state. For a fresh campaign, remove the resume setting in `infra/bootstrap.tf`, apply, then select a spec on the VM with `agents/start-campaign.sh`.

## Plan and apply

The Google provider needs an OAuth token. In PowerShell, run:

```powershell
$env:Path = 'C:\ProgramData\chocolatey\lib\gcloudsdk\tools\google-cloud-sdk\bin;' + $env:Path
$env:GOOGLE_OAUTH_ACCESS_TOKEN = (gcloud.cmd auth print-access-token)
terraform -chdir=infra init
terraform -chdir=infra plan -out=tfplan
terraform -chdir=infra apply tfplan
```

The local SSH key is generated under ignored `.local-evidence/terraform-ssh` if absent. `terraform output -raw manager_chat_command` gives the interactive manager command. `terraform output -raw product_url` gives the product address after the builder PRs merge and the product is deployed. The VM must listen on all interfaces on port 3000 for that public address to work. The agent dashboards remain on localhost and use `dashboard_tunnel`.

In its historical recovery configuration, apply installs the runtimes, restores the existing campaign, reconstructs the builder worktree at the current PR head, and starts the queue. The issue and PR must still satisfy the resume checks. For a fresh campaign, the queue starts after you select a spec and the manager creates issues. Agents do not merge PRs.

The [root README](README.md) records the briefing campaign, its issue and PR links, observed failures, and token usage. [agents/RECOVERY.md](agents/RECOVERY.md) describes rejected work and release rollback.

## Persistent data

`FACTORY_DATA_DIR` must point at persistent VM data across releases so run
history and comparison state survive restart/release. Do not reset it per deploy.

## Automatic deployment

The user systemd `factory-autodeploy.timer` checks the default branch each minute.
It deploys a new main revision only when every first-parent commit since the live
release is a merged PR whose head passed the `verify` check and, for product changes, the `factory-gates` status. Factory-only PRs have a documented status exception.
Direct commits and unfinished gates are not deployed automatically. The deployer
builds a versioned release with `agents/release-product.sh`, checks the live page,
API, CSS, and JavaScript, and rolls back on failure. It retries failed releases
with a 15-minute cooldown, up to three attempts per revision. Run history remains
under the persistent `FACTORY_DATA_DIR`, outside release directories.

Use `systemctl --user status factory-autodeploy.timer` and
`journalctl --user -u factory-autodeploy.service -f` to inspect it.
