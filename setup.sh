#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

echo "=== Installing my-scripts to $BIN_DIR ==="
for f in "$REPO_DIR"/my-scripts/*; do
  [ -f "$f" ] && chmod +x "$f" && cp "$f" "$BIN_DIR/$(basename "$f")" && echo "  Installed $(basename "$f")"
done

export PATH="$BIN_DIR:$PATH"

echo "=== Running setup scripts ==="
for script in "$REPO_DIR"/scripts/*.sh; do
  echo "--- Running $(basename "$script") ---"
  bash "$script"
  echo
done

echo "=== Registering $BIN_DIR in PATH ==="
LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
RC_FILE="$HOME/.bashrc"
if ! grep -q "\.local/bin" "$RC_FILE" 2>/dev/null; then
  echo "$LINE" >> "$RC_FILE"
  echo "Added to $RC_FILE — run 'source $RC_FILE' to activate"
else
  echo "Already registered in $RC_FILE"
fi

echo
echo "=== Setup complete ==="
