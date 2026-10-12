# Contributing

This experimental snapshot is unmaintained. There is no guaranteed response, PR review, release or support. Contributions to a fork should use the MIT license for first-party changes and preserve third-party notices.

For independent forks: resolve locked dependencies and run analyzer/tests as described in `docs/BUILD_AND_TEST.md`. Keep changes small, use synthetic data and add focused regressions for behavior changes. Date/recurrence work belongs with rule tests; lifecycle UI work needs controller/widget regressions; native sharing or reminders need disposable-device tests. Never include real records, credentials, signing files or generated binaries.
