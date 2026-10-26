# syntax=docker/dockerfile:1.7

ARG R_VERSION=4.3.2
FROM rocker/r-ver:${R_VERSION}

ARG CLAUDE_CODE_VERSION=2.1.310
ARG R_STACK=full
ARG DEBIAN_FRONTEND=noninteractive
ARG USER_ID=1000
ARG GROUP_ID=1000

# Build-time root is used only to install immutable OS dependencies.
# Runtime is strictly non-root (USER ruser below).
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    bubblewrap \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    default-libmysqlclient-dev \
    gfortran \
    git \
    libarchive-dev \
    libbz2-dev \
    libcairo2-dev \
    libcurl4-openssl-dev \
    libfftw3-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libfribidi-dev \
    libgdal-dev \
    libgeos-dev \
    libgit2-dev \
    libgl1-mesa-dev \
    libglpk-dev \
    libglu1-mesa-dev \
    libgmp3-dev \
    libharfbuzz-dev \
    libhdf5-dev \
    libicu-dev \
    libjpeg-dev \
    liblzma-dev \
    libmagick++-dev \
    libmpfr-dev \
    libnetcdf-dev \
    libpng-dev \
    libpoppler-cpp-dev \
    libpq-dev \
    libproj-dev \
    libprotobuf-dev \
    libsodium-dev \
    libsqlite3-dev \
    libssh2-1-dev \
    libssl-dev \
    libtiff-dev \
    libtbb-dev \
    libv8-dev \
    libudunits2-dev \
    libxml2-dev \
    libxt-dev \
    ninja-build \
    clang \
    pandoc \
    pkg-config \
    protobuf-compiler \
    python3 \
    python3-venv \
    qpdf \
    socat \
    unixodbc-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Baseline R development tooling. Project dependencies still belong in renv.lock/DESCRIPTION.
RUN Rscript --vanilla -e 'options(repos = c(CRAN = "https://cloud.r-project.org")); install.packages(c("renv", "pak", "devtools", "testthat"), Ncpus = max(1L, parallel::detectCores()))'

# Dedicated runtime user. Match USER_ID/GROUP_ID to the host user on Linux so
# the project bind mount remains writable without ever running Claude as root.
RUN if ! getent group "${GROUP_ID}" >/dev/null; then groupadd --gid "${GROUP_ID}" ruser; fi \
    && useradd --uid "${USER_ID}" --gid "${GROUP_ID}" --create-home --shell /bin/bash ruser \
    && mkdir -p \
        /opt/claude-install \
        /etc/claude-code \
        /workspace \
        /state/home \
        /state/r-cache/library \
        /state/r-cache/R \
        /state/r-cache/renv \
    && chown -R ruser:ruser \
        /opt/claude-install \
        /workspace \
        /state/home \
        /state/r-cache \
        /home/ruser

# Install a pinned native Claude Code build as the non-root user, then make it immutable to ruser.
USER ruser
ENV HOME=/opt/claude-install
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}" \
    && /opt/claude-install/.local/bin/claude --version

USER root
RUN chown -R root:root /opt/claude-install \
    && chmod -R a-w /opt/claude-install \
    && ln -s /opt/claude-install/.local/bin/claude /usr/local/bin/claude

COPY --chown=root:root config/managed-settings.json /etc/claude-code/managed-settings.json
COPY --chown=root:root scripts/claude-r-entrypoint /usr/local/bin/claude-r-entrypoint
COPY --chown=root:root scripts/r-deps /usr/local/bin/r-deps
COPY --chown=root:root scripts/r-pkg /usr/local/bin/r-pkg
RUN chmod 0555 /usr/local/bin/claude-r-entrypoint /usr/local/bin/r-deps /usr/local/bin/r-pkg \
    && chmod 0444 /etc/claude-code/managed-settings.json

ENV R_STACK=full \
    HOME=/state/home \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 \
    R_ENVIRON_USER=/dev/null \
    R_LIBS_USER=/state/r-cache/library \
    R_USER_CACHE_DIR=/state/r-cache/R \
    RENV_PATHS_CACHE=/state/r-cache/renv \
    RENV_CONFIG_PAK_ENABLED=TRUE \
    RENV_CONFIG_AUTO_SNAPSHOT=FALSE

WORKDIR /workspace
USER ruser

ENTRYPOINT ["/usr/local/bin/claude-r-entrypoint"]
