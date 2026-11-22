# Software factory on Google Cloud

Terraform creates one Ubuntu Compute Engine `n4-standard-2` VM (2 vCPUs, 8 GiB RAM) in the configured Google Cloud project and zone. It creates a VPC, subnet, SSH firewall limited to the operator's current public IPv4 address, and configurable public product ports. The VM runs the Hermes manager, reviewer, tester, and two OpenClaw builders. The agent queue and GitHub issue trail are described in [agents/README.md](agents/README.md).

## Prepare

For each new campaign, create and initialize a separate product repository before starting the manager. Give the factory GitHub token read and write access to it, and put `Repository: https://github.com/OWNER/PRODUCT` in the VM spec. The factory clones that repository under `~/factory-products/OWNER/PRODUCT`; builder branches, issues, PRs, CI, and product releases live there. The first builder PR adds the supplied `verify` workflow and `product-check.sh`.

1. Install Terraform, Google Cloud CLI, Python 3, Git, SSH, SCP, and `ssh-keygen` locally. Sign in with `gcloud auth login`, select the same project as `project_id`, and enable Compute Engine and billing there.
2. Put `OLLAMA_API_KEY` and a GitHub token with access to the factory repository and selected product repository in ignored `agents/.env` or `agents/secrets.env`, following `agents/.env.sample`.
3. Commit and push this factory revision to the repository default branch. Bootstrap checks that the VM clones exactly that revision.
4. For a fresh campaign, leave `resume_issue` and `resume_spec` unset. To resume a historical campaign, set both variables and ensure its GitHub issue and PR still satisfy the resume checks. The [briefing spec](examples/briefing-product/specs/spec.md) is an example, not a bootstrap default.

## Plan and apply

The Google provider needs an OAuth token. In PowerShell, run:

```powershell
$env:Path = 'C:\ProgramData\chocolatey\lib\gcloudsdk\tools\google-cloud-sdk\bin;' + $env:Path
$env:GOOGLE_OAUTH_ACCESS_TOKEN = (gcloud.cmd auth print-access-token)
terraform -chdir=infra init
terraform -chdir=infra plan -var 'project_id=YOUR_PROJECT' -out=tfplan
terraform -chdir=infra apply tfplan
```

The local SSH key is generated under ignored `.local-evidence/terraform-ssh` if absent. `terraform output -raw manager_chat_command` gives the interactive manager command. `terraform output -raw product_url` gives the origin for an HTTP product using `product_port`; the product must listen on that port for the address to work. Set `product_port` and `additional_product_ports` to match the spec. The agent dashboards remain on localhost and use `dashboard_tunnel`.

When recovery inputs are provided, apply installs the runtimes, restores the selected campaign, reconstructs the builder worktree at the current PR head, and starts the queue. The issue and PR must still satisfy the resume checks. For a fresh campaign, the queue starts after you select a spec and the manager creates issues. Agents do not merge PRs.

The [root README](README.md) records the briefing campaign, its issue and PR links, observed failures, and token usage. [agents/RECOVERY.md](agents/RECOVERY.md) describes rejected work and release rollback.

## Persistent data

`FACTORY_DATA_DIR` must point at persistent VM data across releases so run
history and comparison state survive restart/release. Do not reset it per deploy.

## Automatic deployment

The user systemd `factory-autodeploy.timer` checks the default branch each minute.
It deploys a new default-branch revision only when every first-parent commit since the live
release is a merged PR whose head passed the `verify` check and, for product changes, the `factory-gates` status. Factory-only PRs have a documented status exception.
Direct commits and unfinished gates are not deployed automatically. The deployer
builds a versioned release with `agents/release-product.sh`, runs the product's
`smoke` command, and rolls back on failure. The briefing example checks its page,
API, CSS, and JavaScript assets. It retries failed releases
with a 15-minute cooldown, up to three attempts per revision. Run history remains
under the persistent `FACTORY_DATA_DIR`, outside release directories.

Use `systemctl --user status factory-autodeploy.timer` and
`journalctl --user -u factory-autodeploy.service -f` to inspect it.
