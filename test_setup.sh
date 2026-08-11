#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_HOME="$(mktemp -d)"
RC_FILE="$TEMP_HOME/.bashrc"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TEMP_HOME"
}
trap cleanup EXIT

pass() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}

# --- test 1: setup.sh adds the block to .bashrc ---
echo "=== Test 1: setup.sh registers block in .bashrc ==="
echo "# existing content" > "$RC_FILE"
HOME="$TEMP_HOME" bash "$REPO_DIR/setup.sh" 2>&1 | tail -1

if ! grep -q '# >>> setup repo >>>' "$RC_FILE"; then
  fail "block marker not found in .bashrc"
else
  pass "block marker found in .bashrc"
fi

if grep -q '/home/thiag/projects/setup/my-scripts' "$RC_FILE"; then
  pass "block contains correct my-scripts path"
else
  fail "block missing my-scripts path"
fi

# --- test 2: opener functions work when sourced ---
echo "=== Test 2: sourced .bashrc creates opener functions ==="
source "$RC_FILE"

if declare -f gc &>/dev/null; then
  pass "opener function 'gc' defined"
else
  fail "opener function 'gc' not defined"
fi

if declare -f np &>/dev/null; then
  pass "opener function 'np' defined"
else
  fail "opener function 'np' not defined"
fi

# --- test 3: idempotent (running again doesn't duplicate) ---
echo "=== Test 3: setup.sh is idempotent ==="
BEFORE=$(wc -l < "$RC_FILE")
HOME="$TEMP_HOME" bash "$REPO_DIR/setup.sh" 2>&1 | tail -1
AFTER=$(wc -l < "$RC_FILE")

if [ "$BEFORE" -eq "$AFTER" ]; then
  pass "no duplicate lines added on second run"
else
  fail "duplicate lines added: $BEFORE -> $AFTER lines"
fi

# --- test 4: PATH entry for my-scripts is present ---
echo "=== Test 4: PATH includes my-scripts directory ==="
NEW_SESSION_PATH=$(bash -c "source '$RC_FILE' && echo \$PATH")
if [[ "$NEW_SESSION_PATH" == *"$REPO_DIR/my-scripts"* ]]; then
  pass "PATH includes my-scripts directory"
else
  fail "PATH missing my-scripts directory"
fi

# --- summary ---
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
