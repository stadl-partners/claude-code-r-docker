#!/usr/bin/env bash
# Usage: ./install.sh [--uninstall]
# Linux/macOS/WSL: symlinks claude-r into $BIN_DIR (default: ~/.local/bin).
# Git Bash on Windows: runs install.ps1, which puts this repo on your user PATH so `claude-r`
# works from cmd, PowerShell and Git Bash (symlinks are unreliable there).
set -euo pipefail

repo="$(dirname "$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f "${BASH_SOURCE[0]}")")"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    ps_args=()
    [[ "${1:-}" == "--uninstall" ]] && ps_args=(-Uninstall)
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$repo/install.ps1")" "${ps_args[@]}" ;;
esac

bin_dir="${BIN_DIR:-$HOME/.local/bin}"
link="$bin_dir/claude-r"

if [[ "${1:-}" == "--uninstall" ]]; then
  if [[ -L "$link" && "$(readlink "$link")" == "$repo/claude-r" ]]; then
    rm "$link"
    echo "Removed $link"
  else
    echo "No claude-r link from this repo in $bin_dir" >&2
  fi
  exit 0
fi

mkdir -p "$bin_dir"
ln -sfn "$repo/claude-r" "$link"
echo "Linked $link -> $repo/claude-r"

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "Note: $bin_dir is not on your PATH. Add to ~/.bashrc or ~/.zshrc:"
     echo "  export PATH=\"$bin_dir:\$PATH\"" ;;
esac

command -v docker >/dev/null || echo "Warning: docker not found on PATH." >&2
