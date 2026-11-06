---
name: r-package-dev
description: Develop, document, test and check an R package (DESCRIPTION, NAMESPACE, roxygen2, testthat, devtools). Use when editing files under R/, tests/, man/ or DESCRIPTION, or when asked to add a function, fix a bug or prepare a package for check.
---

# R package development

DRAFT. Review before use.

## Workflow

1. Read `DESCRIPTION`, `NAMESPACE` and the nearest existing function and test before writing anything; match their style (tidyverse style unless the package clearly differs).
2. Make sure dependencies are installed: `r-deps`. Don't call `install.packages()`.
3. Change code in `R/`. Document with roxygen2 comments; never hand-edit `man/*.Rd` or `NAMESPACE` when roxygen generates them.
4. Add or update a test in `tests/testthat/test-<file>.R` for every behavior change. Test the new behavior and one edge case (empty input, `NA`, wrong type).
5. Run, in this order, and fix before moving on:
   - `Rscript -e 'devtools::document()'`
   - `Rscript -e 'devtools::test()'`
   - `Rscript -e 'devtools::check(error_on = "warning")'` (slow; run once at the end)
6. Report what you ran and the result. If `check()` shows NOTEs you didn't cause, say so instead of fixing them.

## Rules

- New dependency: add it to `DESCRIPTION` (`Imports` or `Suggests`) and call it as `pkg::fun()`. Ask first if it's a heavy package.
- Never touch `.Renviron`, `.env` or credentials. Tests that need a service use mocks (`httptest2`, `mockery`) or `testthat::skip_if_offline()`.
- Don't bump `Version:` or edit `NEWS.md` unless asked.
- The container has no internet beyond the package hosts. A test that needs another host will fail here; mock it.
