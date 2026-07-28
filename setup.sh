#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$REPO_DIR/my-scripts:$PATH"

echo "=== Running setup scripts ==="
for script in "$REPO_DIR"/scripts/*.sh; do
  echo "--- Running $(basename "$script") ---"
  bash "$script"
  echo
done

echo "=== Registering my-scripts in PATH ==="
LINE="export PATH=\"\$HOME/dev-env-setup/my-scripts:\$PATH\""
RC_FILE="$HOME/.bashrc"
if ! grep -q "dev-env-setup/my-scripts" "$RC_FILE" 2>/dev/null; then
  echo "$LINE" >> "$RC_FILE"
  echo "Added to $RC_FILE — run 'source $RC_FILE' to activate"
else
  echo "Already registered in $RC_FILE"
fi

echo
echo "=== Setup complete ==="
