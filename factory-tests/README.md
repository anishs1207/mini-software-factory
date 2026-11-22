# Factory checks

These tests exercise bootstrap, queue policy, usage reporting, and release mechanics. They do not prescribe a product architecture or acceptance suite. Each product's builder supplies `product-check.sh` in its PR. The reviewer and tester compare that script and its results with the selected spec and issue acceptance criteria.

Each product supplies its own independent checks without changing the factory tests.

The `verify` GitHub Actions job runs on pull requests and pushes to `main`. It runs `agents/ci-check.sh` for the factory, validates the Terraform configuration, and runs `examples/breifing-product/product-check.sh` for the archived briefing example. The factory check parses all shell scripts and compiles all Python files before running its tests, including watchdog and usage accounting fixtures. The example check installs locked dependencies, lints, type checks, runs its unit tests including storage, builds the Next.js standalone server, and checks for generated static assets.
