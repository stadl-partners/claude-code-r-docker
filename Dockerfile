# syntax=docker/dockerfile:1.7

# R base image, pinned by digest (Renovate bumps tag + digest together).
# 4.3.2 is the R version this image targets; change the tag and digest together.
FROM rocker/r-ver:4.3.2@sha256:4e32addfc4da3e660f6e0d05ce5e43d3eceb9db58a60b9a142e0dde9a654ead1

# slim = core R build libraries; full = slim + geospatial, database, Stan/V8, image, Python.
ARG R_STACK=full
ARG DEBIAN_FRONTEND=noninteractive

# Claude Code native binary, pinned by version AND sha256 (checked against the release manifest
# at https://downloads.claude.ai/claude-code-releases/<version>/manifest.json, glibc builds).
# Bump all three together with scripts/update-claude-pin.
ARG CLAUDE_CODE_VERSION=2.1.316
ARG CLAUDE_SHA256_AMD64=fd13c70000fec3f2116dfbcbb6121210b4a29328bf0e46210a59dd594a67d824
ARG CLAUDE_SHA256_ARM64=55cdb8e162d190432696ea54010e0fca2e18d06fa7a7127fd563b9ffd4f22624

ARG HOST_UID=1000
ARG HOST_GID=1000

# Build-time root installs immutable OS dependencies only. Runtime is the non-root `claude` user.
# bubblewrap + socat are required by Claude Code's Linux sandbox.
RUN set -eux; \
    case "${R_STACK}" in slim|full) ;; *) echo "R_STACK must be slim or full" >&2; exit 1 ;; esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bubblewrap socat ca-certificates curl git ripgrep unzip ncurses-term \
        build-essential cmake gfortran pkg-config pandoc qpdf \
        libarchive-dev libbz2-dev libcairo2-dev libcurl4-openssl-dev libfontconfig1-dev \
        libfreetype6-dev libfribidi-dev libgit2-dev libglpk-dev libgmp3-dev libharfbuzz-dev \
        libicu-dev libjpeg-dev liblzma-dev libmpfr-dev libpng-dev libsodium-dev libsqlite3-dev \
        libssh2-1-dev libssl-dev libtiff-dev libxml2-dev libxt-dev zlib1g-dev; \
    if [ "${R_STACK}" = "full" ]; then \
        apt-get install -y --no-install-recommends \
            clang ninja-build python3 python3-venv protobuf-compiler \
            default-libmysqlclient-dev libfftw3-dev libgdal-dev libgeos-dev libgl1-mesa-dev \
            libglu1-mesa-dev libhdf5-dev libmagick++-dev libnetcdf-dev libpoppler-cpp-dev \
            libpq-dev libproj-dev libprotobuf-dev libtbb-dev libudunits2-dev libv8-dev \
            unixodbc-dev; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# CRAN repository for the build AND at runtime (r-deps, r-pkg, interactive R). rocker's own site
# profile points at Posit Package Manager, whose package downloads redirect to
# rspm-sync.rstudio.com; those transfers were cut off mid-stream (curl exit 18) in testing, while
# official CRAN completed every time. Override it in the site profile so a separate
# `Rscript -e options(repos=...)` (which only lasts for that one process) isn't needed.
# Packages compile from source: all needed system libraries are installed above.
# To use another official mirror: --build-arg CRAN_REPO=https://stat.ethz.ch/CRAN (and add
# ethz.ch to proxy/allowlist.txt).
ARG CRAN_REPO=https://cloud.r-project.org
RUN echo "options(repos = c(CRAN = '${CRAN_REPO}'))" >> "$(R RHOME)/etc/Rprofile.site" \
    && Rscript -e 'cat(getOption("repos"), "\n")' | grep -F "${CRAN_REPO}"

# Baseline R tooling. No --vanilla, so the site profile above applies. Project dependencies still
# belong in renv.lock / DESCRIPTION.
# pak comes from r-lib's own prebuilt-binary repository (the officially documented install).
# It then installs everything else with parallel downloads and builds. PKG_SYSREQS=false stops
# pak from running apt. install.packages() only warns on a failed download, so the R call checks
# that pak loads.
RUN Rscript -e 'install.packages("pak", repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s", .Platform$pkgType, R.Version()$os, R.Version()$arch)); stopifnot(requireNamespace("pak", quietly = TRUE))' \
    && PKG_SYSREQS=false Rscript -e 'pak::pkg_install(c("renv", "devtools", "testthat"))' \
    && Rscript -e 'stopifnot(all(c("renv", "pak", "devtools", "testthat") %in% rownames(installed.packages())))'

# Claude Code: download the release binary directly and verify the pinned checksum.
# (The official install script is not piped to a shell: it only checks a checksum fetched from the same host.)
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) platform=linux-x64;   sha="${CLAUDE_SHA256_AMD64}" ;; \
        arm64) platform=linux-arm64; sha="${CLAUDE_SHA256_ARM64}" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 -o /tmp/claude \
        "https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}/${platform}/claude"; \
    echo "${sha}  /tmp/claude" | sha256sum -c -; \
    install -D -m 0555 -o root -g root /tmp/claude /opt/claude/bin/claude; \
    rm -f /tmp/claude; \
    ln -s /opt/claude/bin/claude /usr/local/bin/claude; \
    /opt/claude/bin/claude --version

# Dedicated runtime user. HOST_UID/HOST_GID match the host user so the project bind mount is
# writable without ever running as root. Any pre-existing user/group on those IDs is removed.
RUN set -eux; \
    u="$(getent passwd "${HOST_UID}" | cut -d: -f1 || true)"; [ -z "$u" ] || userdel -r "$u"; \
    g="$(getent group "${HOST_GID}" | cut -d: -f1 || true)"; [ -z "$g" ] || groupdel "$g"; \
    groupadd --gid "${HOST_GID}" claude; \
    useradd --uid "${HOST_UID}" --gid "${HOST_GID}" --create-home --shell /bin/bash claude; \
    mkdir -p /workspace /etc/claude-code \
        /home/claude/.local/share/R/library /home/claude/.cache/R /home/claude/.cache/renv; \
    chown -R claude:claude /workspace /home/claude

# Root-owned, read-only policy and helpers. The user cannot alter them.
COPY --chown=root:root --chmod=0444 config/managed-settings.json /etc/claude-code/managed-settings.json
COPY --chown=root:root --chmod=0444 config/CLAUDE.md /etc/claude-code/CLAUDE.md
COPY --chown=root:root --chmod=0555 scripts/claude-r-entrypoint /usr/local/bin/claude-r-entrypoint
COPY --chown=root:root --chmod=0555 scripts/r-deps /usr/local/bin/r-deps
COPY --chown=root:root --chmod=0555 scripts/r-pkg /usr/local/bin/r-pkg

ENV HOME=/home/claude \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 \
    R_ENVIRON_USER=/dev/null \
    R_LIBS_USER=/home/claude/.local/share/R/library \
    R_USER_CACHE_DIR=/home/claude/.cache/R \
    RENV_PATHS_CACHE=/home/claude/.cache/renv \
    RENV_CONFIG_PAK_ENABLED=TRUE \
    RENV_CONFIG_AUTO_SNAPSHOT=FALSE \
    PKG_SYSREQS=false

USER claude
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/claude-r-entrypoint"]
