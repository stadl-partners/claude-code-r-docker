FROM node:22-bookworm-slim

# Install R runtime, C/C++ compilation tools, and system libraries for R packages
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git \
    r-base \
    r-base-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    gfortran \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Create workspace and set permissions for non-root node user
RUN mkdir /workspace && chown node:node /workspace
WORKDIR /workspace

USER node

ENTRYPOINT ["claude"]
