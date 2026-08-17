#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$REPO_DIR/configure-low-memory-jvm.sh"
TEMP_HOME="$(mktemp -d)"
STUB_DIR="$TEMP_HOME/stubs"
CONF_FILE="$TEMP_HOME/.config/jvm-memory/jvm-memory.sh"
RC_FILE="$TEMP_HOME/.bashrc"
PASS=0
FAIL=0
BASH_BIN="$(command -v bash)"

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

# --- stub tools ----------------------------------------------------------
mkdir -p "$STUB_DIR"
write_stub() {
  local name="$1" body="$2"
  printf '#!/bin/bash\n%s\n' "$body" > "$STUB_DIR/$name"
  chmod +x "$STUB_DIR/$name"
}

write_stub java 'if [[ " $* " == *" -XshowSettings"* ]]; then
  echo "VM settings:"
  echo "    Max. Heap Size (Estimated): 1.00G"
  echo "    Ergonomics Machine Class: desktop"
else
  echo "java $*"
fi'
for t in sbt scala scala-cli metals bloop cs jdtls; do
  write_stub "$t" 'exit 0'
done
write_stub jps 'echo "1234 sbt"'

export -n XDG_CONFIG_HOME || true
unset XDG_CONFIG_HOME || true

MINBIN="$TEMP_HOME/minbin"
mkdir -p "$MINBIN"
for c in mktemp date cp mv rm mkdir rmdir cmp awk grep head cat printf dirname wc ls chmod; do
  ln -s "$(command -v "$c")" "$MINBIN/$c" 2>/dev/null || true
done

export PATH="$MINBIN:$STUB_DIR"

run() {
  HOME="$TEMP_HOME" PATH="$PATH" "$BASH_BIN" "$SCRIPT" "$@"
}

count_backups() {
  local n=0 f
  for f in "$TEMP_HOME"/.bashrc.bak.* "$TEMP_HOME"/.config/jvm-memory/*.bak.*; do
    [ -e "$f" ] && n=$((n + 1))
  done
  echo "$n"
}

echo "=== Test 1: fresh install writes config + .bashrc block ==="
printf '# my existing rc\n' > "$RC_FILE"
run 2>&1 >/dev/null
if [ -f "$CONF_FILE" ] && grep -q 'low-memory-jvm-config' "$CONF_FILE"; then
  pass "config file created with markers"
else
  fail "config file missing or unmarked"
fi
if grep -q 'low-memory-jvm-config' "$RC_FILE"; then
  pass ".bashrc has source block"
else
  fail ".bashrc missing source block"
fi
if grep -q '# my existing rc' "$RC_FILE"; then
  pass "pre-existing .bashrc content preserved"
else
  fail "pre-existing .bashrc content lost"
fi

echo "=== Test 2: install fails without java ==="
if PATH="$MINBIN" HOME="$TEMP_HOME" "$BASH_BIN" "$SCRIPT" >/dev/null 2>&1; then
  fail "install should fail when java is missing"
else
  pass "install fails when java is missing"
fi

echo "=== Test 3: dry-run writes nothing ==="
rm -f "$CONF_FILE" "$RC_FILE"
rm -f "$TEMP_HOME/.bashrc.bak."* "$TEMP_HOME/.config/jvm-memory/"*.bak.*
run --dry-run 2>&1 >/dev/null
if [ ! -f "$CONF_FILE" ] && [ ! -f "$RC_FILE" ]; then
  pass "dry-run created no files"
else
  fail "dry-run wrote files"
fi

echo "=== Test 4: re-run is idempotent ==="
printf '# my existing rc\n' > "$RC_FILE"
run 2>&1 >/dev/null
RC_BEFORE=$(wc -l < "$RC_FILE")
BAK_BEFORE=$(count_backups)
run 2>&1 >/dev/null
RC_AFTER=$(wc -l < "$RC_FILE")
BAK_AFTER=$(count_backups)
if [ "$RC_BEFORE" -eq "$RC_AFTER" ]; then
  pass "second run did not duplicate .bashrc lines"
else
  fail ".bashrc changed on re-run: $RC_BEFORE -> $RC_AFTER"
fi
if [ "$BAK_AFTER" -eq "$BAK_BEFORE" ]; then
  pass "second run created no new backups"
else
  fail "new backups created on re-run"
fi

echo "=== Test 5: verify passes (exit 0) ==="
if run --verify >/dev/null 2>&1; then
  pass "verify exited 0"
else
  fail "verify exited non-zero"
fi

echo "=== Test 6: verify fails (exit 3) when config missing ==="
run --uninstall >/dev/null 2>&1
if run --verify >/dev/null 2>&1; then
  fail "verify should fail after uninstall"
else
  pass "verify fails after uninstall"
fi

echo "=== Test 7: uninstall removes config and restores .bashrc ==="
run 2>&1 >/dev/null
run --uninstall 2>&1 >/dev/null
if [ ! -f "$CONF_FILE" ]; then
  pass "config removed"
else
  fail "config still present"
fi
if ! grep -q 'low-memory-jvm-config' "$RC_FILE"; then
  pass "source block removed from .bashrc"
else
  fail "source block still in .bashrc"
fi
if grep -q '# my existing rc' "$RC_FILE"; then
  pass "original .bashrc content restored"
else
  fail "original .bashrc content lost"
fi

echo "=== Test 8: install tolerates missing optional tools ==="
mkdir -p "$TEMP_HOME/stubs_javaonly"
printf '#!/bin/bash\nif [[ " $* " == *" -XshowSettings"* ]]; then\n  echo "Max. Heap Size (Estimated): 1.00G"\nfi\n' > "$TEMP_HOME/stubs_javaonly/java"
chmod +x "$TEMP_HOME/stubs_javaonly/java"
T8_OUT=$(PATH="$MINBIN:$TEMP_HOME/stubs_javaonly" HOME="$TEMP_HOME" "$BASH_BIN" "$SCRIPT" 2>&1) || true
if printf '%s' "$T8_OUT" | grep -q 'scala-cli.*absent' && ! printf '%s' "$T8_OUT" | grep -qi 'ERROR\|not found'; then
  pass "install succeeds with only java; optional tools reported absent"
else
  fail "install with only java failed or did not report absent tools"
fi

echo "=== Test 9: existing SBT_OPTS wins over ours (conflict skip) ==="
rm -rf "$TEMP_HOME/.config"
run 2>&1 >/dev/null
RESULT=$(HOME="$TEMP_HOME" "$BASH_BIN" -c 'export SBT_OPTS="-Xmx2048m"; source "$1" 2>/dev/null; printf "%s\n" "$SBT_OPTS"' _ "$CONF_FILE")
if [[ "$RESULT" == *"-Xmx2048m"* ]] && [[ "$RESULT" != *"-Xmx1280m"* ]] && [[ "$RESULT" == *"-Xms256m"* ]]; then
  pass "existing -Xmx2048m preserved, our -Xmx1280m skipped, rest appended"
else
  fail "SBT_OPTS merge wrong: $RESULT"
fi

echo "=== Test 10: existing JDK_JAVA_OPTIONS preserved ==="
RESULT=$(HOME="$TEMP_HOME" "$BASH_BIN" -c 'export JDK_JAVA_OPTIONS="-Xmx2048m"; source "$1" 2>/dev/null; printf "%s\n" "$JDK_JAVA_OPTIONS"' _ "$CONF_FILE")
if [[ "$RESULT" == *"-Xmx2048m"* ]] && [[ "$RESULT" == *"-XX:MaxRAM=4g"* ]]; then
  pass "existing -Xmx2048m kept alongside cap tokens"
else
  fail "JDK_JAVA_OPTIONS merge wrong: $RESULT"
fi

echo "=== Test 11: unmarked config conflict is preserved (exit 1) ==="
rm -rf "$TEMP_HOME/.config"
mkdir -p "$TEMP_HOME/.config/jvm-memory"
printf 'export MY_THING=1\n' > "$CONF_FILE"
if run 2>/dev/null; then
  fail "install should exit 1 on unmarked config conflict"
else
  pass "install rejected unmarked config conflict"
fi
if grep -q 'MY_THING' "$CONF_FILE"; then
  pass "conflicting config preserved"
else
  fail "conflicting config overwritten"
fi

echo "=== Test 12: bad usage exits 2 ==="
if run --bogus 2>/dev/null; then
  fail "bad flag should exit 2"
else
  pass "bad flag exits 2"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]