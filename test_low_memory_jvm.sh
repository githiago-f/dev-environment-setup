#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$REPO_DIR/configure-low-memory-jvm.sh"
TEMP_HOME="$(mktemp -d)"
STUB_DIR="$TEMP_HOME/stubs"
CONF_DIR="$TEMP_HOME/.config/jvm-memory"
CONF_FILE="$CONF_DIR/config"
LOADER_FILE="$CONF_DIR/low-memory-jvm.sh"
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
else
  exit 0
fi'
for t in sbt scala scala-cli metals bloop cs jdtls jcmd jps; do
  write_stub "$t" 'exit 0'
done

export -n XDG_CONFIG_HOME || true
unset XDG_CONFIG_HOME || true

MINBIN="$TEMP_HOME/minbin"
mkdir -p "$MINBIN"
for c in mktemp date cp mv rm mkdir rmdir cmp awk grep head cat printf dirname wc ls chmod \
         timeout sed ps tr seq kill sleep; do
  ln -s "$(command -v "$c")" "$MINBIN/$c" 2>/dev/null || true
done

export PATH="$MINBIN:$STUB_DIR"

run() {
  HOME="$TEMP_HOME" PATH="$PATH" "$BASH_BIN" "$SCRIPT" "$@"
}

count_backups() {
  local n=0 f
  for f in "$TEMP_HOME"/.bashrc.bak.* "$CONF_DIR"/*.bak.* "$CONF_DIR"/profiles/*.bak.*; do
    [ -e "$f" ] && n=$((n + 1))
  done
  echo "$n"
}

echo "=== Test 1: fresh install (low profile) writes config + loader + profiles + block ==="
printf '# my existing rc\n' > "$RC_FILE"
run 2>&1 >/dev/null
if [ -f "$CONF_FILE" ] && grep -q 'PROFILE=low' "$CONF_FILE"; then
  pass "config written with PROFILE=low"
else
  fail "config missing or not low"
fi
if [ -f "$LOADER_FILE" ] && [ -f "$CONF_DIR/profiles/low" ] && [ -f "$CONF_DIR/profiles/normal" ]; then
  pass "loader + both profiles written"
else
  fail "loader or profiles missing"
fi
if grep -q 'low-memory-jvm' "$RC_FILE"; then
  pass ".bashrc has source block"
else
  fail ".bashrc missing source block"
fi
if grep -q '# my existing rc' "$RC_FILE"; then
  pass "pre-existing .bashrc content preserved"
else
  fail "pre-existing .bashrc content lost"
fi

echo "=== Test 2: sourced loader sets the low-profile values ==="
RESULT=$(HOME="$TEMP_HOME" "$BASH_BIN" -c 'source "$1"; printf "%s|%s" "$SBT_OPTS" "$LOW_MEMORY_JVM_ACTIVE"' _ "$LOADER_FILE")
if [[ "$RESULT" == *"-Xmx768m"* ]] && [[ "$RESULT" == *"|low" ]]; then
  pass "SBT_OPTS=-Xmx768m and ACTIVE=low"
else
  fail "loader values wrong: $RESULT"
fi
if grep -q -- '-Xmx' <(HOME="$TEMP_HOME" "$BASH_BIN" -c 'source "$1"; echo "$JDK_JAVA_OPTIONS"' _ "$LOADER_FILE"); then
  fail "JDK_JAVA_OPTIONS must not contain a global -Xmx"
else
  pass "no global -Xmx in JDK_JAVA_OPTIONS"
fi

echo "=== Test 3: install fails without java ==="
if PATH="$MINBIN" HOME="$TEMP_HOME" "$BASH_BIN" "$SCRIPT" >/dev/null 2>&1; then
  fail "install should fail when java is missing"
else
  pass "install fails when java is missing"
fi

echo "=== Test 4: dry-run writes nothing ==="
rm -rf "$CONF_DIR" "$RC_FILE"
run --dry-run 2>&1 >/dev/null
if [ ! -f "$CONF_FILE" ] && [ ! -f "$RC_FILE" ]; then
  pass "dry-run created no files"
else
  fail "dry-run wrote files"
fi

echo "=== Test 5: re-run is idempotent ==="
printf '# my existing rc\n' > "$RC_FILE"
run 2>&1 >/dev/null
RC_BEFORE=$(wc -l < "$RC_FILE")
BAK_BEFORE=$(count_backups)
run 2>&1 >/dev/null
RC_AFTER=$(wc -l < "$RC_FILE")
BAK_AFTER=$(count_backups)
if [ "$RC_BEFORE" -eq "$RC_AFTER" ]; then
  pass "second run did not change .bashrc"
else
  fail ".bashrc changed on re-run"
fi
if [ "$BAK_AFTER" -eq "$BAK_BEFORE" ]; then
  pass "second run created no new backups"
else
  fail "new backups created on re-run"
fi

echo "=== Test 6: verify passes (exit 0) ==="
if run --verify >/dev/null 2>&1; then
  pass "verify exited 0"
else
  fail "verify exited non-zero"
fi

echo "=== Test 7: --profile normal switches config + values ==="
run --profile normal 2>&1 >/dev/null
if grep -q 'PROFILE=normal' "$CONF_FILE"; then
  pass "config switched to normal"
else
  fail "config not switched"
fi
RESULT=$(HOME="$TEMP_HOME" "$BASH_BIN" -c 'source "$1"; printf "%s" "$SBT_OPTS"' _ "$LOADER_FILE")
if [[ "$RESULT" == *"-Xmx1g"* ]]; then
  pass "normal profile sets SBT_OPTS=-Xmx1g"
else
  fail "normal profile values wrong: $RESULT"
fi

echo "=== Test 8: verify fails (exit 3) when config missing ==="
run --uninstall >/dev/null 2>&1
if run --verify >/dev/null 2>&1; then
  fail "verify should fail after uninstall"
else
  pass "verify fails after uninstall"
fi

echo "=== Test 9: uninstall removes managed files and restores .bashrc ==="
run 2>&1 >/dev/null
run --uninstall 2>&1 >/dev/null
if [ ! -f "$CONF_FILE" ] && [ ! -f "$LOADER_FILE" ] && [ ! -f "$CONF_DIR/profiles/low" ]; then
  pass "managed files removed"
else
  fail "managed files still present"
fi
if ! grep -q 'low-memory-jvm' "$RC_FILE"; then
  pass "source block removed from .bashrc"
else
  fail "source block still in .bashrc"
fi
if grep -q '# my existing rc' "$RC_FILE"; then
  pass "original .bashrc content restored"
else
  fail "original .bashrc content lost"
fi

echo "=== Test 10: existing SBT_OPTS wins over ours (conflict skip) ==="
rm -rf "$CONF_DIR"
run 2>&1 >/dev/null
RESULT=$(HOME="$TEMP_HOME" "$BASH_BIN" -c 'export SBT_OPTS="-Xmx2048m"; source "$1" 2>/dev/null; printf "%s" "$SBT_OPTS"' _ "$LOADER_FILE")
if [[ "$RESULT" == *"-Xmx2048m"* ]] && [[ "$RESULT" != *"-Xmx768m"* ]] && [[ "$RESULT" == *"-Xss512k"* ]]; then
  pass "existing -Xmx2048m preserved, ours skipped, other flags appended"
else
  fail "SBT_OPTS merge wrong: $RESULT"
fi

echo "=== Test 11: existing JDK_JAVA_OPTIONS preserved alongside cap ==="
RESULT=$(HOME="$TEMP_HOME" "$BASH_BIN" -c 'export JDK_JAVA_OPTIONS="-Xmx2048m"; source "$1" 2>/dev/null; printf "%s" "$JDK_JAVA_OPTIONS"' _ "$LOADER_FILE")
if [[ "$RESULT" == *"-Xmx2048m"* ]] && [[ "$RESULT" == *"-XX:MaxRAM=4g"* ]]; then
  pass "existing -Xmx2048m kept alongside cap tokens"
else
  fail "JDK_JAVA_OPTIONS merge wrong: $RESULT"
fi

echo "=== Test 12: unmarked config conflict is preserved (exit 1) ==="
rm -rf "$CONF_DIR"
mkdir -p "$CONF_DIR/profiles"
printf 'export MY_THING=1\n' > "$CONF_FILE"
if run >/dev/null 2>&1; then
  fail "install should exit 1 on unmarked config conflict"
else
  pass "install rejected unmarked config conflict"
fi
if grep -q 'MY_THING' "$CONF_FILE"; then
  pass "conflicting config preserved"
else
  fail "conflicting config overwritten"
fi

echo "=== Test 13: old layout is migrated ==="
rm -rf "$CONF_DIR"
mkdir -p "$CONF_DIR"
printf '# >>> low-memory-jvm-config >>>\nexport OLD=1\n# <<< low-memory-jvm-config <<<\n' > "$CONF_DIR/jvm-memory.sh"
printf '# my existing rc\n# >>> low-memory-jvm-config >>>\nsource stuff\n# <<< low-memory-jvm-config <<<\n' > "$RC_FILE"
run 2>&1 >/dev/null
if [ ! -f "$CONF_DIR/jvm-memory.sh" ]; then
  pass "old managed file removed"
else
  fail "old managed file still present"
fi
if grep -q 'low-memory-jvm-config' "$RC_FILE"; then
  fail "old .bashrc block still present"
else
  pass "old .bashrc block migrated to new one"
fi

echo "=== Test 14: bad usage exits 2 ==="
if run --bogus >/dev/null 2>&1; then
  fail "bad flag should exit 2"
else
  pass "bad flag exits 2"
fi

echo "=== Test 15: diagnose is read-only and exits 0 ==="
rm -rf "$CONF_DIR"
run 2>&1 >/dev/null
D_OUT=$(run --diagnose 2>&1) || D_OUT=""
if printf '%s' "$D_OUT" | grep -q 'MemTotal'; then
  pass "diagnose reports physical memory"
else
  fail "diagnose missing MemTotal"
fi
if printf '%s' "$D_OUT" | grep -qi 'JVM RSS'; then
  pass "diagnose reports JVM RSS"
else
  fail "diagnose missing JVM RSS section"
fi
if [ -f "$CONF_FILE" ] && [ -f "$LOADER_FILE" ]; then
  pass "diagnose left managed config untouched"
else
  fail "diagnose modified managed config"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]