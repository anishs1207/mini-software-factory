# Recovery

## Before a merge

The manager links issue prerequisites. The queue releases a dependent ticket only after its blockers close and their builder PRs merge. Builders push issue branches and run `product-check.sh`; GitHub CI, reviewer, and tester gate the current PR head. Reviewer or tester rejection sends the same issue and PR back to the builder for a new commit and fresh checks. A stale or conflicting PR must be updated against the default branch. The queue blocks a fourth builder dispatch by default for human inspection. The human runs `bash agents/merge-check.sh ISSUE_NUMBER` and inspects the PR before merging.

## After a bad service release

For a VM-hosted service using `product-service.sh`, run `bash agents/release-product.sh rollback` to restore the prior successful merged revision. A failed smoke check during deployment also triggers an automatic restore. The release script keeps persistent data outside release code. Open a linked bug issue and send a fix or revert PR through CI, review, test, and human merge. Record the bad revision, observed failure, rollback, and fix in `DELIVERY.md`. For other product types, the manager must define a matching recovery path from the selected spec.

The optional `product-service.sh` receives `prepare`, `restart`, `smoke`, or `stop`. The release script supplies `FACTORY_CURRENT_DIR`, `FACTORY_DATA_DIR`, and `FACTORY_RELEASE_ROOT` in a clean environment without agent keys. `prepare` installs runtime dependencies without destructive data changes. `restart` starts the current release. `smoke` checks real product behavior and returns nonzero on failure. `stop` terminates a failed initial release. The builder implements and tests this adapter only when the selected spec calls for a VM-hosted service.
