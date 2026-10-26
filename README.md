# Claude Code R Docker — `r-full-4.3.2`

A reusable, non-root Claude Code environment for R projects. The only host directory bind-mounted into the container is the directory from which you run `ccode`.

## Security model

- **Runtime is non-root.** Claude Code runs as `ruser`. The UID/GID are build arguments (default 1000/1000) so Linux users can match host project ownership without ever running Claude as root.
- **One host bind mount only.** `ccode` mounts the current project directory at `/workspace`. It does not mount `$HOME`, `~/.ssh`, `~/.aws`, Docker sockets, Git credentials, or other host paths.
- **Read-only container filesystem.** The launcher uses `--read-only`, drops all Linux capabilities, sets `no-new-privileges`, and limits PIDs.
- **Managed Claude policy.** `/etc/claude-code/managed-settings.json` forces sandboxing, disables bypass mode, blocks reads outside working directories, ignores repository permission rules, and locks down hooks, MCP servers, plugins, sideload flags, account-synced extensions, remote control, and cross-session inbound access.
- **Secret-file blocking.** `.env`, `.env.*`, `.Renviron`, `*.pem`, and `*.key` are denied through both Claude file permissions and the Bash OS sandbox. `R_ENVIRON_USER=/dev/null` also prevents R from automatically loading a project `.Renviron`.
- **No host credentials forwarded by default.** Authentication state is kept in a Docker-managed named volume, not in a host bind mount. Bash subprocesses run with Claude/cloud credentials scrubbed.
- **Restricted command network.** Sandboxed commands can reach common R, Bioconductor, Posit, GitHub/GitLab/Bitbucket, R-universe, and Python package hosts. Other command-line destinations are blocked by managed policy.

Important: the project directory itself is intentionally mounted read-write so Claude can edit code. Secret files inside the project are therefore physically present in the bind mount, but Claude's managed file permissions and OS-level Bash sandbox deny access to the configured secret patterns. This is an access-control boundary, not a filtered copy of the repository. If a secret was committed to Git history, hard-linked/copied under another name, or embedded in another project file, it is project data and filename-based secret blocking cannot reliably hide it. Do not weaken or remove the managed sandbox if that boundary matters to you.

## R dependency model

Use `renv` whenever possible.

- `r-deps` restores `renv.lock` when present.
- For R package source trees with `DESCRIPTION`, `r-deps` installs development dependencies with `pak`.
- `r-pkg pkg1 pkg2` installs ad-hoc R packages with `pak`.
- `renv`, `pak`, `devtools`, and `testthat` are preinstalled in the image.
- Claude login state and R package caches live under a single Docker-managed `claude-code-r-state` volume, not in a host bind mount.

For this full profile, the image also includes TBB, V8, and Clang for Stan-related compilation and interactive R tooling. `rstan`, `brms`, `shiny`, and the other R packages still come from the project lockfile; a missing `brms` entry is **not** silently added.

The image contains a broad set of common compilation and system libraries (curl/SSL/XML, GDAL/GEOS/PROJ, database clients, image/font libraries, HDF5/NetCDF, etc.). **An arbitrary R package can still require an unusual OS library.** Because runtime is deliberately non-root, such an OS dependency must be added to the Dockerfile and the image rebuilt; do not add `sudo` or runtime `apt-get`.

## Build via GitHub Actions (recommended)

This R 4.3.2 image is built in GitHub Actions, not on your laptop. Push the
repository to a private organization repository and push or merge to `main`.
GitHub Actions automatically builds and publishes the image on every push to `main`;
no manual trigger is needed.
The workflow publishes `ghcr.io/ORG/REPO:r-full-4.3.2`. See the full private
registry instructions below.

The hosted runner builds for `linux/amd64` with R 4.3.2 and Claude Code
2.1.310; OS dependencies are baked into the image, while individual projects
restore their own R packages with `renv`.

## Install the launcher

Set your image and put `ccode` somewhere on your `PATH`:

```bash
export CLAUDE_R_IMAGE='ghcr.io/YOUR_ORG/YOUR_REPOSITORY:r-full-4.3.2'
install -m 0755 ./ccode "$HOME/.local/bin/ccode"
```

Or keep the script in this repository and call it directly.

The launcher refuses `/`, your home directory, and directories that do not look like an R project. It also rejects Claude CLI flags such as `--add-dir`, `--settings`, `--plugin-dir`, and `--mcp-config` that could widen or replace the managed boundary. For an intentionally minimal R folder, opt in once:

```bash
CLAUDE_R_ALLOW_ANY_DIR=1 ccode
```

## Authentication

Preferred: start `ccode` and use Claude's normal `/login` flow. Claude state is stored under `/state/home` in the Docker named volume `claude-code-r-state`; no host Claude configuration is mounted.

API-key authentication is opt-in only:

```bash
export ANTHROPIC_API_KEY='...'
CLAUDE_R_USE_API_KEY=1 ccode
```

The key is made available to the Claude Code parent process because the CLI needs it. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, the sandbox, and `/proc` read denial are used to keep Bash subprocesses from reading it. OAuth/login avoids passing a host API-key variable at all.

## Typical R workflow

Inside Claude Code, prefer these non-interactive commands:

```bash
r-deps
Rscript -e "renv::status()"
Rscript -e "devtools::test()"
Rscript -e "devtools::check()"
```

For an ad-hoc dependency:

```bash
r-pkg ggplot2 dplyr
```

For tests that normally call external services, use mocks (`httptest2`, `httptest`, `mockery`) and dummy environment variables. Do not mount live `.Renviron`, `.env`, SSH, AWS, or cloud credentials into this container.

## GitHub publishing

The workflow builds pull requests without pushing, and publishes `linux/amd64` images to private GHCR from `main` and semantic-version tags (`v*`). Enable branch protection on `main` in GitHub and require PRs/status checks; use `development` as the normal integration branch.

## Compatibility and verification

The supplied example lockfile targets R 4.3.2. Copy it into **your actual project** as `renv.lock` and run `r-deps` there; do not install its 149 locked packages into the shared base image. The lockfile may include packages that require source compilation or remote repositories and restoration is not guaranteed until tested in the target image.

Run `./scripts/validate-repo` locally (optional), then push to `main` and inspect the automatically started GitHub Actions build and published digest. After pulling the image, run `r-deps` inside a real project. No Docker build is claimed to have been run here.

**Security limitation:** with a direct read-write bind of the working directory, files such as `.env` and `.Renviron` inside that directory exist in the container. Claude policy and sandbox restrictions are defense-in-depth, not a guarantee against malicious project scripts, plugins, package install hooks, symlink aliases, or Git history. For a strict guarantee that Claude cannot access those files, run it on a **sanitized separate working copy** containing no secrets. This tool never mounts your other host directories. Do not treat API-key subprocess scrubbing as a complete boundary against arbitrary user code.

## GitHub Actions build (private organization repository)

**No local build is needed.** Commit this toolkit to an organization repository
with Actions enabled. The workflow `.github/workflows/docker-build.yml`:

- Validates, builds, and publishes to `ghcr.io/ORG/REPO:r-full-4.3.2` on every push to `main`.
- Does not use manual workflow triggers, tag triggers, or PR builds.
- Uses the job's `GITHUB_TOKEN` with `packages: write`; no registry PAT or
  registry secret is needed for publishing to the repository's package.
- Builds `linux/amd64` to avoid slow QEMU cross-compilation on hosted runners.
  Apple Silicon users who need native `arm64` can extend the platform list
  and enable QEMU or dedicated ARM runners.
- Produces SHA-based tags and an image digest for pinning, with SBOM and
  minimal provenance.

**Private package setup:** The first published GHCR image normally defaults
private. Confirm visibility under your organization's Packages settings; do
not change it to public. If a package of the same name already exists, ensure
this repository has **Actions access: Write** to that package. An organization
administrator may need to enable GitHub Actions and allow third-party actions.

To pull from a laptop, authenticate with a GitHub **personal access token
(classic)** with `read:packages`, authorized for your organization if SSO is
required, and with permission to read the image. Do **not** put this token in
`.env`, `.Renviron`, an R project, or a Docker build argument:

```bash
# Create a PAT (classic) in GitHub settings, select read:packages.
# Enter it through stdin, without saving it in project files:
read -rsp 'GHCR token: ' GHCR_TOKEN; echo
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
unset GHCR_TOKEN

export CLAUDE_R_IMAGE=ghcr.io/YOUR_ORG/YOUR_REPOSITORY:r-full-4.3.2
cd /path/to/your/r-project
/path/to/ccode
```

The launcher runs `docker pull` on each invocation before launching. Docker's
registry credentials are handled by Docker on the host; they are **not**
mounted into the Claude container. Consider configuring a Docker credential
helper to protect the login token. The image and the repository are separate
access-control objects; only grant package read access to intended users.

For reproducibility, prefer an immutable `@sha256:<digest>` image reference
from the successful workflow rather than a moving tag.

**Host security caveat:** The chosen project is still mounted read-write at
`/workspace`; if it contains secrets, the container can potentially access
them despite assistant/tool-level denial rules. Use a sanitized project copy
when absolute secret separation is required. Runtime network access allows
packages and tools to download dependencies, so do not run untrusted code
or packages with real credentials in the workspace.
