# Software factory on Google Cloud

Terraform creates one Ubuntu Compute Engine `n4-standard-2` VM (2 vCPUs, 8 GiB RAM) in project `confer-assignment`, zone `asia-south1-a`. It creates a VPC, subnet, SSH firewall limited to the operator's current public IPv4 address, and a public product port 3000. The VM runs the Hermes manager, reviewer, tester, and two OpenClaw builders. The agent queue and GitHub issue trail are described in [agents/README.md](agents/README.md).

## Prepare

1. Install Terraform, Google Cloud CLI, Python 3, Git, SSH, SCP, and `ssh-keygen` locally. Sign in with `gcloud auth login` and select the project with `gcloud config set project confer-assignment`. Enable the Compute Engine API and billing in that project.
2. Put `OLLAMA_API_KEY` and a GitHub token with access to `anishs1207/confer-assignment` in ignored `agents/.env` or `agents/secrets.env`, following `agents/.env.sample`.
3. Commit and push this factory revision to the repository default branch. Bootstrap checks that the VM clones exactly that revision.
4. The local `spec/spec.md` is the recovery copy of the existing briefing campaign. Issue #1 and PR #10 already exist. The bootstrap copies this spec to the VM and resumes that issue at the tester handoff after checking the reviewer approval and PR head.

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

Apply installs the runtimes, restores the existing campaign, reconstructs the builder worktree at the current PR head, moves issue #1 from its interrupted `factory:in-progress` state to `factory:test`, and starts the queue. The tester checks PR #10 before the human merges it. Subsequent issues resume through the existing dependency and gate flow. Agents do not merge PRs.

After real runs, create `DELIVERY.md` using [deliverables/DELIVERY.template.md](deliverables/DELIVERY.template.md) with actual issue and PR links, tests, traces, token usage, and product URL. [agents/RECOVERY.md](agents/RECOVERY.md) describes rejected work and release rollback.

## Persistent data

`FACTORY_DATA_DIR` must point at persistent VM storage across releases so run
history and comparison state survive restart/release. Do not reset it per deploy.
