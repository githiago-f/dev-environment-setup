#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REQ_FILE="$REPO_DIR/requirements.txt"

YAY_AVAILABLE=false
PACMAN_AVAILABLE=false
command -v yay &>/dev/null && YAY_AVAILABLE=true
command -v pacman &>/dev/null && PACMAN_AVAILABLE=true

install_pkg() {
  local pkg="$1"
  echo "--- Installing $pkg ---"
  if $YAY_AVAILABLE; then
    yay -S --noconfirm "$pkg" || echo "Warning: failed to install $pkg"
  elif $PACMAN_AVAILABLE; then
    sudo pacman -S --noconfirm "$pkg" || echo "Warning: failed to install $pkg"
  else
    echo "Warning: no package manager found, skipping $pkg"
  fi
}

while IFS= read -r line; do
  line="${line%%#*}"        # strip comments
  line="${line// /}"        # strip whitespace
  [ -z "$line" ] && continue
  install_pkg "$line"
done < "$REQ_FILE"

echo
echo "=== Requirements installed ==="
