# Agent delivery instructions

Read the selected product spec from `~/.config/briefing-agents/spec-path` (default `spec/PRODUCT_SPEC.md`), `spec/ISSUES.md`, `agents/README.md`, and the issue assigned to your role. Keep code changes in agent-authored commits or PRs. Record handoffs, review decisions, test results, model usage, and retries in GitHub Issues/PRs so `DELIVERY.md` can cite real evidence. Never commit secrets or Terraform state.

The selected tracked spec supplies product requirements. `PRODUCT_BRIEF.md` remains the Daily Briefing reference. Its instructions about who writes feature code apply to the delivery team: the builders implement the product, while the human owner reviews and merges.
