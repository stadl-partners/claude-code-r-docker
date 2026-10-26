# Security notes

## Host boundary

The security boundary is Docker first, Claude permissions second. The launcher bind-mounts only the current project directory. A Docker-managed named volume at `/state` is used for Claude login/session state and R package caches; it is not a host-path mount.

Because `/workspace` is a direct read-write bind, `.env` and `.Renviron` files inside that project are physically present in the container namespace even though Claude file tools and sandboxed subprocesses are denied their contents. Secrets committed into Git history or duplicated under another filename are not recoverably distinguishable from ordinary project data; remove such secrets from the repository/history rather than relying on this sandbox.

Never add any of the following to `ccode`:

- `/var/run/docker.sock`
- `$HOME` or parent directories of the project
- `~/.ssh`, `~/.aws`, `~/.config/gcloud`, `~/.kube`
- `.env` or `.Renviron` as explicit mounts
- `--privileged`, `--cap-add`, `--network=host`, or `--user root`

## Claude policy

Managed settings enforce the following:

- bypass permissions disabled
- reads outside working directories blocked
- Bash sandbox required and fail-closed
- unsandboxed fallback disabled
- project/user permission rules cannot replace managed permission rules
- repository/user hooks, skills, agents, plugin marketplaces, and sideloaded plugins blocked
- non-managed MCP servers blocked, including built-in browser/computer/IDE bridges
- remote control and cross-session inbound access disabled
- managed network allowlist for sandboxed commands
- secret file patterns denied for file tools and Bash sandbox reads

`enableWeakerNestedSandbox` is enabled only because Claude's Linux bubblewrap sandbox is running inside an already-isolated, unprivileged Docker container. The outer Docker boundary remains the primary host-isolation control.

## Authentication

No host credentials are forwarded by default. OAuth/Claude login state is stored in a Docker volume. If API-key mode is explicitly enabled, the Claude process necessarily receives the key; subprocess credential scrubbing plus filesystem restrictions reduce exposure to commands Claude runs.

## R package installation

R packages install as the non-root user. Common native build dependencies are preinstalled. If a package requires an OS library that is not present, rebuild the image with that library. Do not solve this by granting runtime root or adding `sudo`.

## Explicit limitation of project bind mounts

Only `/workspace` is host-bound. However all files in that project are exposed to the container namespace, even when filename-deny rules intend to block them. Avoid secrets **inside** the directory: use a sanitized working copy for the strongest separation, especially before running untrusted package installation scripts. Managed permissions are not a substitute for OS-level file removal.

### Private GitHub Container Registry

Publishing via Actions uses only the per-job `GITHUB_TOKEN` (`packages: write`).
The registry package should stay **private**; confirm repository Actions access
if the package name already exists. Developer machines authenticate directly
to Docker/GHCR outside the container with `read:packages` and org SSO
authorization where required. Never pass GHCR PATs into container `-e`, image
build args, or files within `/workspace`.
