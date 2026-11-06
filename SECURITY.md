# Security notes

## Boundaries, in order

1. **Docker.** Non-root user, read-only root filesystem, no capabilities, `no-new-privileges`, resource limits.
2. **Network.** The `claude` container sits on an `internal` network. The only route out is the allowlist proxy (`proxy/`). Direct connections fail; non-allowlisted hosts get a 403 from the proxy.
3. **Claude managed policy.** `/etc/claude-code/managed-settings.json` (root-owned, read-only): sandbox required and fail-closed, bypass mode disabled, reads outside the working directory blocked, repo/user hooks, MCP servers, plugins, remote control and cross-session access blocked.

Docker is the primary boundary; Claude's policy is defense in depth.

## What is mounted

- The project directory, read-write, at `/workspace`.
- `.git/hooks` and `.git/config` of that project, read-only (git executes them on the host). Disable with `CLAUDE_R_GIT_WRITABLE=1`.
- The named volume `claude-home` at `/home/claude`: login state and R package cache.

Never add to compose or the launcher: the Docker socket, `$HOME` or parents of the project, `~/.ssh`, `~/.aws`, `~/.config/gcloud`, `~/.kube`, `--privileged`, `cap_add`, host networking, or a root user. `scripts/validate-repo` rejects these.

## Known limits

- **Secrets in the project.** Files like `.env` and `.Renviron` are present in the bind mount. Filename deny rules don't cover secrets in git history, copies under other names, or other project files. Use a sanitized copy for strong separation.
- **Project `.Rprofile`** executes when R starts in `/workspace`. `r-deps` and `r-pkg` skip it; interactive `Rscript` calls don't. Other writable project files (`Makefile`, `.Rprofile`, package scripts) also run on your host if you run them there later.
- **`/tmp` allows execution.** Docker mounts tmpfs `noexec` by default; it is `exec` here because R compiles Stan and Rcpp models into `tempdir()` and loads them from there. Code Claude writes to `/tmp` can therefore run.
- **Nested sandbox.** Claude's bubblewrap sandbox runs inside Docker, which needs `enableWeakerNestedSandbox` in the managed settings. This is untested here; check that the sandbox actually starts.
- **Proxy allowlist.** The proxy filters by hostname only. GitHub and PyPI hosts can carry arbitrary data, so the allowlist limits where data goes but doesn't make exfiltration impossible. Keep the list short. The managed settings have their own domain allowlist; keep the two consistent.
- **API key mode** (`CLAUDE_R_USE_API_KEY=1`) puts the key in the Claude process environment. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` and the sandbox reduce exposure to child processes; they are not a hard boundary.
- **Prebuilt GHCR images** use UID 1000 and are pulled by tag; prefer `@sha256:` references.

## Supply chain

- Base images are pinned by digest. Claude Code is pinned by version and sha256 (`scripts/update-claude-pin`); the binary is verified at build time. GitHub Actions are pinned to commit SHAs.
- R packages come from official CRAN (source, compiled in the image). Project dependencies belong in `renv.lock`; nothing pins the baseline packages (`renv`, `devtools`, `testthat`) to a date.
- apt packages are not version-pinned. Rebuild picks up current Ubuntu security updates.
- Not yet done: vulnerability scanning (e.g. Trivy), image signing, a Renovate config.

## R packages

Packages install as the non-root user into `~/.local/share/R/library` (or the project's `renv` library). If one needs a missing system library, rebuild the image with it. Don't add sudo or runtime apt.
