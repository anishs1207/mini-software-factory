# Security policy

## Reporting a vulnerability

Please report security issues privately. Use GitHub's **Report a vulnerability** option in this repository's Security tab if it is available. Otherwise, contact the repository owner through a private channel you already have. If you have no private contact route, open a GitHub issue asking for a private reporting channel without including exploit details, credentials, or sensitive logs. Do not post a proof of concept in a public issue or PR before a fix is ready.

Include the affected component and revision, the impact, steps to reproduce, and any safe mitigation you know. Redact tokens, private keys, VM addresses that are not already public, and personal data. The maintainer will assess the report and coordinate a fix and disclosure; this project does not promise a response or release timeline.

## Scope and trust boundaries

Security reports are useful for the factory scripts, Terraform configuration, GitHub workflow, agent handoffs, deployment path, and the example briefing product. The maintained code is the current `main` branch; the deployed VM may run an older merged revision.

This factory runs agent tools and product code on one VM user account. It uses an owner-scoped GitHub token and model API key during agent work. The product check and service adapter run with a clean environment so they do not inherit agent keys, but that is not a sandbox between code running as the same user. Treat code proposed by agents or contributors as untrusted until reviewed. Do not put product secrets in agent configuration.

The current private-repository setup does not enforce branch protection server-side. Local push guards, PR checks, reviewer and tester verdicts, and the human merge step reduce risk but can be bypassed by an actor with sufficient repository credentials. The automatic deployer checks merged PRs and their required checks before deploying; a failed product smoke check triggers rollback.

## Handling secrets

- Keep `OLLAMA_API_KEY` and `GH_TOKEN` in ignored `agents/secrets.env` or another approved private store. Use [`agents/.env.sample`](agents/.env.sample) only as a template.
- Do not commit `.env` files, Terraform state or plans, SSH keys, `.local-evidence/`, runtime logs with credentials, or persistent product data. Check staged files and commit history before pushing; deleting a secret in a later commit does not remove it from history.
- If a credential is exposed, revoke or rotate it promptly, remove it from reachable history where practical, and review the relevant GitHub and VM activity.
- Limit the GitHub token, cloud identity, SSH access, and network exposure to what the deployment needs. The product's port 3000 is public; agent dashboards are intended to stay on localhost behind SSH tunneling.

See [SETUP.md](SETUP.md) for deployment configuration and [agents/RECOVERY.md](agents/RECOVERY.md) for release rollback.
