---
name: r-debug-failing-tests
description: Diagnose and fix failing testthat tests or R CMD check errors by reproducing, isolating and fixing the root cause. Use when devtools::test() or devtools::check() fails.
---

# Debug failing R tests

DRAFT. Review before use.

1. **Reproduce narrowly.** Run only the failing file: `Rscript -e 'devtools::test(filter = "<file-stem>")'`. Copy the exact error and the `Failure`/`Error` location.
2. **Classify.**
   - Assertion mismatch: compare expected and actual with `waldo::compare()`; check types, attributes and factor levels before values.
   - Error in code under test: reproduce in a short `Rscript -e` call with the same inputs.
   - Environment: missing package (see r-renv-deps), network, locale, timezone or random seed. Set `set.seed()` and check `Sys.timezone()` before blaming the code.
3. **Fix the cause, not the test.** Only change an expectation if the old behavior was wrong, and say why. Never add `skip()` to make a failure go away.
4. **Re-run** the file, then the whole suite, then `check()` if the package is being prepared for release.
5. **Report**: root cause in one sentence, what changed, and what you ran.

Flaky tests: run the file three times. If results differ, find the nondeterminism (seed, time, ordering, shared state) and report it; don't retry until green.
