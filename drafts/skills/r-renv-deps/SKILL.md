---
name: r-renv-deps
description: Install, restore or add R package dependencies in this sandbox using renv and pak. Use when a library() call fails, renv.lock is out of sync, a package must be added, or an install fails to compile.
---

# R dependencies (renv + pak)

DRAFT. Review before use.

## Decide first

- `renv.lock` exists: the project is renv-managed. Restore with `r-deps`.
- Only `DESCRIPTION` exists: `r-deps` installs the development dependencies with pak.
- Neither exists: use `r-pkg <pkg> ...` for ad-hoc packages and tell the user nothing is recorded.

## Adding a package to an renv project

1. `r-pkg <pkg>` (or `Rscript -e 'renv::install("<pkg>")'`).
2. Use it in code, then **ask the user before** `renv::snapshot()`. Lockfile changes are theirs to approve. Show `renv::status()` first.

## When an install fails

1. Read the first compiler or configure error, not the last line.
2. A missing header or `.so` (for example `libpq-fe.h`, `gdal-config`, `udunits2.h`) means a missing system library. It can't be fixed here: no sudo, no apt. Tell the user the exact library or Ubuntu package name so they can add it to the Dockerfile.
3. `package ‘x’ requires R >= 4.x`: the image has R 4.3.2 and the current CRAN. Report it; don't try other repositories.
4. A download refused or timing out means the host isn't on the proxy allowlist. Tell the user the host.

## Rules

- Never run `install.packages()` or `remotes::install_github()` directly; use pak (`r-pkg user/repo` accepts GitHub references).
- Never change repositories or `options(repos = ...)`.
- Don't commit the renv library or cache.
