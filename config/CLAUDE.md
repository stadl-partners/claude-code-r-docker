# Sandbox environment

You are running in a locked-down Docker container: non-root user `claude`, no sudo, no apt. Only `/workspace` (the project) and `/home/claude` (login state, R package cache) persist. The root filesystem is read-only.

Network access goes through an allowlist proxy (CRAN, Bioconductor, Posit Package Manager, GitHub/GitLab/Bitbucket, R-universe, PyPI, Anthropic). If a download is refused, tell the user which host you need; don't try to work around it.

# R

R and the common system libraries are preinstalled; `renv`, `pak`, `devtools` and `testthat` are available.

- Dependencies: if the project has `renv.lock` or `DESCRIPTION`, run `r-deps`. For an ad-hoc package, run `r-pkg <pkg> [...]`. Don't call `install.packages()` directly, and don't edit `renv.lock` unless the user asks.
- Run R non-interactively: `Rscript -e 'devtools::test()'`, `Rscript -e 'devtools::check()'`, `Rscript -e 'renv::status()'`.
- Tests that need external services should use mocks (`httptest2`, `mockery`) and dummy environment variables. Never look for or create `.Renviron`, `.env`, keys or tokens.
- A project `.Rprofile` runs whenever R starts in `/workspace`. Read it before running R in a project you don't trust.
- `.git/hooks` and `.git/config` are mounted read-only, so `git config` changes and hook edits will fail by design. Commits work normally.

## System libraries

They can't be installed here (e.g. `libpq-dev`). If a package fails to build because of a missing system library, tell the user the library name so they can add it to the Dockerfile and rebuild.
