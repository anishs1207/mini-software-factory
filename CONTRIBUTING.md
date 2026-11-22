# Contributing

Contributions to the factory scripts, infrastructure, tests, documentation, and example briefing product are welcome. Read the [README](README.md) for the architecture and [agent operating guide](agents/README.md) for the issue and PR stages.

## Before changing code

1. For a product change, identify the active spec and GitHub issue. Note its acceptance criteria and dependencies. For a factory change, explain the queue, gate, bootstrap, or release behavior being changed.
2. Create a branch from the current default branch. Factory-assigned builders use `agent/builder1/issue-N` or `agent/builder2/issue-N` in isolated worktrees; other contributors can use a descriptive branch name.
3. Keep the change scoped. Add a test when behavior changes or a regression needs proof. Do not commit generated files such as `node_modules/`, `.next/`, Terraform state, local evidence, credentials, or persistent product data.

## Check your change

The `verify` GitHub Actions job runs factory checks, Terraform validation, and the example product check on PRs. On a system with Bash, Python 3, Terraform, and Node.js 22, run the relevant commands locally:

```sh
bash agents/ci-check.sh
terraform -chdir=infra fmt -check
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra validate -no-color
bash examples/briefing-product/product-check.sh
```

`agents/ci-check.sh` checks shell syntax, compiles Python, and runs the factory tests. The example product check installs locked npm dependencies, lints, type-checks, tests, builds, and checks standalone static assets. If you add another product, provide an executable `product-check.sh` with checks appropriate to its spec. You do not need cloud credentials for the checks above; deployment and live acceptance checks require the configured VM and accounts.

## Open a pull request

Link the issue when one exists. Describe the behavior, the acceptance criteria covered, the tests run and their results, and any operational or rollback effect. Agent-authored product PRs must also state the agent, model, token usage, and tests as described in [agents/README.md](agents/README.md). Keep secrets and private usage traces out of PR text and logs.

The factory verifies the assigned builder's commit identity and the PR head, runs CI, then obtains reviewer and tester verdicts for that head. A new commit requires those checks again. Failed review or test returns the same PR to the builder. The human owner reviews and merges after `factory:merge-ready` and passing checks. Do not push directly to `main` or merge an agent PR on behalf of the human owner.

For a change to a deployed product, document how to verify it after release. The release tool deploys merged revisions and retains a previous release for [rollback](agents/RECOVERY.md). Keep persistent data under `FACTORY_DATA_DIR` across releases.

Report suspected vulnerabilities through [SECURITY.md](SECURITY.md), not a public issue with exploit details.
