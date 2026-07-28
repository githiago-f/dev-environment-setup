#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Syncing .config/nvim from repo to ~/.config/nvim..."
cp -rf "$REPO_DIR/.config/nvim" "$HOME/.config/"
echo "Done."
