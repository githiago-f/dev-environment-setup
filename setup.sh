#!/usr/bin/env bash
set -euo pipefail

INSTALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) INSTALL=true ;;
    *) echo "Usage: $0 [--full]"; exit 1 ;;
  esac
  shift
done

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

echo "=== Installing my-scripts to $BIN_DIR ==="
for f in "$REPO_DIR"/my-scripts/*; do
  [ -f "$f" ] && chmod +x "$f" && cp "$f" "$BIN_DIR/$(basename "$f")" && echo "  Installed $(basename "$f")"
done

export PATH="$BIN_DIR:$PATH"

if $INSTALL; then
  echo "=== Running setup scripts ==="
  for script in "$REPO_DIR"/scripts/*.sh; do
    echo "--- Running $(basename "$script") ---"
    bash "$script"
    echo
  done
else
  echo "=== Running safe setup scripts ==="
  for script in "$REPO_DIR"/scripts/github_setup.sh "$REPO_DIR"/scripts/sync_config.sh; do
    if [ -f "$script" ]; then
      echo "--- Running $(basename "$script") ---"
      bash "$script"
      echo
    fi
  done
fi

RC_FILE="$HOME/.bashrc"
MARKER_START="# >>> setup repo >>>"
MARKER_END="# <<< setup repo <<<"

register_block() {
  local marker="$1"
  local block="$2"
  if grep -qF "$marker" "$RC_FILE" 2>/dev/null; then
    echo "Already registered ($marker) in $RC_FILE"
  else
    printf '%s\n' "$block" >> "$RC_FILE"
    echo "Added block to $RC_FILE"
  fi
}

echo "=== Registering $BIN_DIR in PATH ==="
LINE='export PATH="$HOME/.local/bin:$PATH"'
if ! grep -q "\.local/bin" "$RC_FILE" 2>/dev/null; then
  echo "$LINE" >> "$RC_FILE"
  echo "Added $BIN_DIR to $RC_FILE"
else
  echo "$BIN_DIR already registered in $RC_FILE"
fi

echo "=== Registering my-scripts loader in $RC_FILE ==="
MY_SCRIPTS_DIR="$REPO_DIR/my-scripts"
read -r -d '' BLOCK <<- 'BLOCK_EOF' || true
	# >>> setup repo >>>
	# my-scripts: PATH and opener functions
	export PATH="__MY_SCRIPTS_DIR__:$PATH"
	for ___f in "__MY_SCRIPTS_DIR__"/*; do
	    [ -f "$___f" ] && [ -x "$___f" ] || continue
	    if head -3 "$___f" | grep -qs '# opener: cd'; then
	        ___n=$(basename "$___f")
	        eval "function $___n() { local d=\$(\"$___f\") && [ -n \"\$d\" ] && cd \"\$d\"; }"
	    fi
	done
	# <<< setup repo <<<
BLOCK_EOF
BLOCK="${BLOCK//__MY_SCRIPTS_DIR__/$MY_SCRIPTS_DIR}"
register_block "$MARKER_START" "$BLOCK"

echo
echo "=== Setup complete ==="
