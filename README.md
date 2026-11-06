# Claude Code R sandbox

Claude Code in a locked-down Docker container for R projects. It runs as the non-root user `claude`, sees only the project directory you launch it from, and can reach the internet only through an allowlist proxy.

**Status:** `scripts/validate-repo` and `scripts/smoke-test` pass (images build; identity, read-only filesystem, pinned Claude, C++ compile, proxy allow/deny). Not yet verified: a full interactive Claude session, whether Claude's own sandbox starts inside the container, and the Windows installer.

## Quick start

Needs Docker (Docker Desktop on Windows/macOS) and git.

**Linux, macOS, WSL**

```bash
./install.sh                 # symlinks claude-r into ~/.local/bin (add it to PATH if prompted)
cd /path/to/your/r-project
claude-r                     # first run builds the images (a few minutes), then /login
```

**Windows** (cmd, PowerShell, or the Git Bash terminal in VS Code / RStudio)

```powershell
.\install.cmd                # or .\install.ps1, or ./install.sh from Git Bash
# restart open terminals (VS Code, RStudio) so the new PATH is picked up
cd C:\path\to\your\r-project
claude-r
```

On Windows the installer adds this repo's folder to your user PATH. `claude-r` then resolves to `claude-r.cmd` (PowerShell launcher) in cmd and PowerShell, and to the `claude-r` bash script in Git Bash. `install.sh --uninstall` / `install.ps1 -Uninstall` undo it. If an interactive session fails in Git Bash with "the input device is not a TTY", run it from PowerShell or the VS Code terminal instead, or prefix with `winpty`.

`claude-r [--update | --no-update-check | --stop] [directory] [claude args...]`

| Variable | Meaning |
|---|---|
| `CLAUDE_R_STACK=slim\|full` | `full` (default) adds geospatial, database, Stan/V8, image and Python libraries |
| `CLAUDE_R_MEMORY`, `CLAUDE_R_CPUS` | container limits (default `8g`, `4`) |
| `CLAUDE_R_USE_API_KEY=1` | forward `ANTHROPIC_API_KEY` (OAuth `/login` is the default and preferred) |
| `CLAUDE_R_ALLOW_ANY_DIR=1` | allow a directory without an R project marker |
| `CLAUDE_R_GIT_WRITABLE=1` | don't mount `.git/hooks` and `.git/config` read-only |

The launcher builds the image for your host UID/GID, so files Claude writes are owned by you. It refuses `/`, `/home`, your home directory, non-R directories, and Claude flags that could widen the boundary (`--add-dir`, `--settings`, `--mcp-config`, `--permission-mode`, `--dangerously-skip-permissions`, ...). `claude-r --stop` removes the proxy, which otherwise stays up between sessions.

## What is in the image

- `rocker/r-ver` (R 4.3.2, pinned by digest) with system libraries for compiling R packages, `renv`, `pak`, `devtools`, `testthat`. CRAN is the official `https://cloud.r-project.org` (set in the site profile via `--build-arg CRAN_REPO=...`). Packages compile from source, so the first install of a big package is slower; use `renv.lock` for reproducible versions. Posit Package Manager is not used: its downloads were truncated in testing.
- Claude Code, a native binary downloaded and checked against a pinned sha256 (`scripts/update-claude-pin` bumps version and hashes together). Auto-update is off.
- `bubblewrap` and `socat` for Claude's Linux sandbox, a root-owned `/etc/claude-code/managed-settings.json` policy, and a root-owned `/etc/claude-code/CLAUDE.md` with R conventions.
- `r-deps` (restore `renv.lock`, or install `DESCRIPTION` dependencies) and `r-pkg <pkg>...` (ad-hoc installs with `pak`). Both skip the project's `.Rprofile`.

## Security model

1. **No root.** The image runs as `claude`; the entrypoint refuses uid 0; there is no sudo.
2. **Container hardening.** Read-only root filesystem, all capabilities dropped, `no-new-privileges`, PID, memory and CPU limits, `/tmp` as a `nosuid,nodev` tmpfs that allows exec (Stan and Rcpp models are compiled and loaded from there).
3. **One host mount.** Only the project directory is bind-mounted, plus a named volume `claude-home` (login state, R package cache). No `$HOME`, SSH keys, cloud credentials or Docker socket. `.git/hooks` and `.git/config` are mounted read-only, because git runs them on your host.
4. **Network egress.** The container is on an `internal` Docker network with no route out. The only exit is the `proxy` container (tinyproxy, deny by default) which allows Anthropic, CRAN, Bioconductor, Posit, R-universe, GitHub/GitLab/Bitbucket and PyPI hosts (`proxy/allowlist.txt`).
5. **Claude policy.** Managed settings force the sandbox, disable bypass mode, block reads outside the working directory and block repo-level hooks, MCP servers and plugins.

Limits: the project directory is read-write, so secrets inside it are physically present. Claude's deny rules are defense in depth, not a guarantee. Use a sanitized copy when that matters. A project `.Rprofile` runs whenever R starts in `/workspace`; read it before running R in a project you don't trust. See [SECURITY.md](SECURITY.md).

## R workflow

```bash
r-deps                                  # renv::restore() or install DESCRIPTION deps
r-pkg ggplot2 dplyr                     # ad-hoc packages
Rscript -e 'devtools::test()'
Rscript -e 'devtools::check()'
```

If a package needs a system library that isn't in the image, add it to the Dockerfile and rebuild. There is no sudo or runtime `apt`.

## Verify

```bash
bash scripts/validate-repo                                      # static checks (needs jq)
docker build -t claude-r-ci:full .
docker build -t claude-r-proxy-ci ./proxy
bash scripts/smoke-test claude-r-ci:full claude-r-proxy-ci      # identity, read-only FS, pinned Claude, proxy allow/deny
```

CI (`.github/workflows/docker-build.yml`) runs the same checks for `slim` and `full` on every PR and push, and publishes to GHCR from `main`. Published images carry UID/GID 1000; on any other host UID build locally with `claude-r`.

## Updating pins

```bash
scripts/update-claude-pin            # Claude Code stable; or pass a version
```

The base image digest and GitHub Action SHAs are updated by hand or with Renovate (not configured yet).
