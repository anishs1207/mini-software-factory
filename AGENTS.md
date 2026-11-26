# Coding agent guide

This repository contains the reusable software factory, not the active product's source. The factory turns a Markdown product spec into GitHub issues, assigns two builders, runs review and test gates, and prepares merged product revisions for deployment. Each campaign's product code, issues, branches, and pull requests belong in the separate repository named by the spec. `examples/briefing-product/` is an archived example, not a template that every product must follow.

## Find the right code

- `agents/`: queue, dispatch, role configuration, campaign setup, release, recovery, and usage scripts. Start with [agents/README.md](agents/README.md) for the stage and handoff rules.
- `infra/`: Terraform for the Google Cloud VM and network. [SETUP.md](SETUP.md) covers provisioning and operation.
- `tests/`: factory regression tests. [tests/README.md](tests/README.md) explains their scope.
- `code-review/`: a separate TypeScript advisory GitHub reviewer; it does not implement the factory's reviewer gate.
- `examples/briefing-product/`: the archived Next.js product and its own check script.
- `.github/workflows/agent-pr.yml`: this repository's `verify` CI job.

Read [README.md](README.md) for the architecture and [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution and PR workflow. The builder-specific instructions in `agents/openclaw/builder1/AGENTS.md` and `agents/openclaw/builder2/AGENTS.md` apply to those dispatched roles in their product worktrees.

## Work on changes

1. Identify whether the request changes factory behavior or a campaign product. For product work, read the selected spec, issue, acceptance criteria, and dependencies, then work in that product repository's assigned worktree. Do not place new product code in this factory checkout merely because the example is here.
2. Keep changes focused. For changed behavior, add a meaningful regression test in the relevant suite. Preserve the existing queue stages, head-bound review/test verdicts, and release rollback behavior unless the task explicitly changes them.
3. Run the relevant checks and report exactly what ran. The CI job runs these from the repository root on Ubuntu:

   ```sh
   bash agents/ci-check.sh
   terraform -chdir=infra fmt -check
   terraform -chdir=infra init -backend=false -input=false
   terraform -chdir=infra validate -no-color
   npm ci --prefix code-review && npm test --prefix code-review
   bash examples/briefing-product/product-check.sh
   ```

   Factory checks need Bash and Python 3; Terraform checks need Terraform; Node checks use Node.js 22 in CI. Run checks relevant to the files changed when the full toolchain is unavailable, and state any checks you could not run. A new product needs its own executable `product-check.sh` that works non-interactively on a fresh Ubuntu runner.
4. Inspect the diff and staged files before a commit. Do not commit secrets, `.env` files, Terraform state or plans, `.local-evidence/`, generated dependencies or builds, or persistent product data. See [SECURITY.md](SECURITY.md) for private vulnerability reporting.

## Delivery boundary

Use a branch and PR for changes. Link the issue when one exists, describe the acceptance criteria, checks and results, and operational effects. Factory-assigned builders follow their role-specific identity, branch, and PR-body requirements. A new commit on a product PR requires CI, reviewer, and tester gates again for that head. Leave PR merging to the human owner; do not push directly to `main` or merge an agent PR. Deployment and rollback procedures are in [agents/RECOVERY.md](agents/RECOVERY.md).
