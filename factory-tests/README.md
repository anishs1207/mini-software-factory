# Factory checks

These tests exercise bootstrap, queue policy, usage reporting, and release mechanics. They do not prescribe a product architecture or acceptance suite. Each product's builder supplies `product-check.sh` in its PR. The reviewer and tester compare that script and its results with the selected spec and issue acceptance criteria.

Each product supplies its own independent checks without changing the factory tests.
