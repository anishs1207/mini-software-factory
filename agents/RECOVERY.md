# Bad-code recovery

## Before merge

The builder pushes to an issue branch, never to the default branch. `Agent PR` CI runs `product-check.sh`; a failed or missing check prevents reviewer dispatch. The reviewer examines the diff and can request changes. The tester runs issue-specific acceptance checks and can file a bug. Either rejection returns the issue to the builder. The builder fixes the same PR with a new commit, preserving the failed attempt in history. Review and test verdicts must name the current head SHA. Before merging, the human runs `bash agents/merge-check.sh ISSUE_NUMBER` and inspects the PR.

## After merge or deployment

Stop the product service or disable its public Run now trigger if the bad release could corrupt data or burn model quota. Use the product deployment ticket's rollback command to restore the previous known-good git revision, then run its public smoke check. Keep the persistent run store separate from release code. Do not reset or delete run history to hide a failure. Open a linked bug issue, ask a builder for a fix or revert PR, and put that PR through CI, review, and test before the human merges it. Record the bad revision, rollback revision, observed failure, and fix in the ticket and `DELIVERY.md`.

The concrete deploy/rollback commands cannot be filled in until the agents choose and implement the product service. The deployment ticket must supply and test them before a live submission.
