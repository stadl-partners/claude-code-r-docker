# Secure Claude Code R Environment

A sandboxed Docker environment for running [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) locally with R, `renv`, and `devtools` support.

## Security Guarantees
- **Non-root execution:** Runs as the `node` user.
- **Directory isolation:** Only mounts your active project workspace (`/workspace`).
- **Zero Credential Exposure:** Cannot access host directories (`~/.Renviron`, `~/.ssh`, `~/.aws`).
- **No Token Leaks:** Injects dummy environment variables for mock test execution.

## Shell Alias Setup

Add the following alias to your `~/.zshrc` or `~/.bashrc` (replace `YOUR_GITHUB_USERNAME` with your GitHub handle):

```bash
alias ccode='docker run -it --rm \
  --name claude-code-session \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  -e MOCK_API_KEY="dummy_key_for_tests" \
  -v "$(pwd):/workspace" \
  ghcr.io/YOUR_GITHUB_USERNAME/claude-code-r-docker:latest'
```

## Usage

1. Authenticate your Anthropic API key in your host terminal:

```bash
export ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

2. Navigate to your R project directory:

```bash
cd ~/projects/my-r-package
```
3. Run Claude Code:

```bash
cclaude
```

