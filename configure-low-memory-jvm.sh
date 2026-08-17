#!/usr/bin/env bash
set -euo pipefail

# configure-low-memory-jvm.sh
# Global low-memory JVM configuration for an 8 GB RAM Linux dev machine
# running Java + Scala + sbt + ZIO + Metals + Neovim + jdtls.
#
# Modes:
#   (no flag)       install / update the config
#   --verify        check effective values + runtime max heap, exit 3 on problems
#   --uninstall     remove the config and the .bashrc source block
#   --dry-run       show what install/uninstall would do without writing
#
# Exit codes: 0 ok, 1 error (e.g. java missing, config conflict),
#             2 usage error, 3 verification problems.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jvm-memory"
CONF_FILE="$CONF_DIR/jvm-memory.sh"
RC_FILE="$HOME/.bashrc"

MARKER_START="# >>> low-memory-jvm-config >>>"
MARKER_END="# <<< low-memory-jvm-config <<<"

MODE=install
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $0 [--verify|--uninstall|--dry-run] [-h]

  (default)   install or update the low-memory JVM config
  --verify    verify the installed config and report effective values
  --uninstall remove the config and the .bashrc source block
  --dry-run   print what would change without modifying anything
  -h, --help  show this help

Managed file : $CONF_FILE
Source block : $RC_FILE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify) MODE=verify ;;
    --uninstall) MODE=uninstall ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

require_java() {
  if ! command -v java >/dev/null 2>&1; then
    echo "ERROR: 'java' not found on PATH." >&2
    echo "  This configuration targets a machine with a JVM toolchain." >&2
    exit 1
  fi
}

backup_file() {
  local f="$1" b
  [ -f "$f" ] || return 0
  b="${f}.bak.$(date +%Y%m%d-%H%M%S)"
  cp -p "$f" "$b"
  echo "  backup: $b"
}

detect_tools() {
  echo "  Toolchain detected:"
  local t
  for t in java sbt scala scala-cli metals bloop cs jdtls; do
    if command -v "$t" >/dev/null 2>&1; then
      printf '    %-12s present\n' "$t"
    else
      printf '    %-12s absent\n' "$t"
    fi
  done
}

generate_managed_file() {
  cat > "$1" <<'EOF'
# >>> low-memory-jvm-config >>>
# Managed by configure-low-memory-jvm.sh -- manual edits are lost on re-run.
# Low-memory global JVM settings for an 8 GB dev machine.
#
# Layer model:
#  1. JDK_JAVA_OPTIONS -- every JDK launcher prepends this; an explicit -Xmx
#                         on the command line always overrides it.
#  2. SBT_OPTS          -- the sdkman sbt runner passes these as JVM args
#                         (beats JAVA_OPTS, JAVA_TOOL_OPTIONS and the default
#                         -mem 1024m).
#  3. scala-cli         -- no env var here (it warns and ignores heap flags in
#                         JAVA_OPTS/JDK_JAVA_OPTIONS); use `scala-cli --java-opt`
#                         or `scala-cli config java.properties` instead.
#  4. JAVA_OPTS         -- the coursier Metals launcher expands this. Kept unset
#                         by default; the Layer 1 cap already bounds the server.
#                         Uncomment below to pin it.
#  5. jdtls             -- no env var; bounded by the Layer 1 cap (~1G default
#                         max vs 2G without it). For a smaller server use
#                         nvim-jdtls -vmargs or vscode java.jdt.ls.vmargs.
#  6. BLOOP_JAVA_OPTS   -- read by `bloop start`; keeps bloop's default
#                         -XX:+UseZGC, which uncommits unused heap.

# Append tokens to a variable, deduplicating. If the variable already holds a
# conflicting flag (same option, e.g. -Xmx), the existing flag wins and ours is
# skipped with a notice.
_lmj_flag() {
  case "$1" in
    -Xmx*|-Xms*|-Xss*) printf '%s' "${1%%[0-9]*}" ;;
    -XX:*) printf '%s' "${1%%=*}" ;;
    *) printf '%s' "$1" ;;
  esac
}
_lmj_append_var() {
  local var="$1" val="$2"
  local cur t flag w
  local -a add=()
  cur="${!var:-}"
  for t in $val; do
    case " $cur " in
      *" $t "*) continue ;;
    esac
    flag="$(_lmj_flag "$t")"
    for w in $cur; do
      if [ -n "$w" ] && [ "$(_lmj_flag "$w")" = "$flag" ]; then
        printf '%s\n' "  jvm-memory: $var already has '$w'; keeping it, skipping '$t'" >&2
        t=""
        break
      fi
    done
    [ -n "$t" ] && add+=("$t")
  done
  if [ "${#add[@]}" -gt 0 ]; then
    if [ -n "$cur" ]; then
      export "$var=$cur ${add[*]}"
    else
      export "$var=${add[*]}"
    fi
  fi
}

# Layer 1 -- global default heap cap (~1G on this machine; explicit -Xmx wins).
_lmj_append_var JDK_JAVA_OPTIONS '-XX:MaxRAM=4g -XX:MaxRAMPercentage=25'

# Layer 2 -- sbt. Keep below the ~1G cap ceiling so editor + server both fit.
_lmj_append_var SBT_OPTS '-Xms256m -Xmx1280m -Xss1m -XX:MaxMetaspaceSize=256m -XX:ReservedCodeCacheSize=128m'

# Layer 4 -- Metals server (coursier launcher expands $JAVA_OPTS; nvim-metals
# filters -Xms*/-Xmx*/-Xss* from the -J flags it passes, but the server still
# sees them through the launcher). Uncomment to pin the server below the cap.
#_lmj_append_var JAVA_OPTS '-Xms256m -Xmx768m -Xss4m -XX:MaxMetaspaceSize=256m'

# Layer 6 -- Bloop server. Keep bloop's default ZGC (uncommits unused heap).
_lmj_append_var BLOOP_JAVA_OPTS '-Xmx1g'

# <<< low-memory-jvm-config <<<
EOF
}

RC_BLOCK=$'# >>> low-memory-jvm-config >>>\n# Global low-memory JVM settings (configure-low-memory-jvm.sh)\n[ -f "$HOME/.config/jvm-memory/jvm-memory.sh" ] && . "$HOME/.config/jvm-memory/jvm-memory.sh"\n# <<< low-memory-jvm-config <<<'

# Append $block to $file, or replace an existing region bounded by the markers.
# Backs up only when the file actually changes.
append_or_replace_block() {
  local file="$1" start="$2" end="$3" block="$4" tmp
  if [ ! -f "$file" ]; then
    printf '%s\n' "$block" > "$file"
    echo "  created $file"
    return 0
  fi
  if grep -qF "$start" "$file" 2>/dev/null; then
    tmp="$(mktemp)"
    awk -v s="$start" -v e="$end" '
      $0 == s {skip=1; next}
      skip && $0 == e {skip=0; next}
      skip {next}
      {print}
    ' "$file" > "$tmp"
    printf '%s\n' "$block" >> "$tmp"
    if cmp -s "$file" "$tmp"; then
      rm -f "$tmp"
      echo "  $file unchanged (block already up to date)"
      return 0
    fi
    backup_file "$file"
    mv "$tmp" "$file"
    echo "  updated block in $file"
    return 0
  fi
  backup_file "$file"
  printf '\n%s\n' "$block" >> "$file"
  echo "  added block to $file"
}

print_summary() {
  cat <<EOF

=== Summary ===
  JDK_JAVA_OPTIONS : -XX:MaxRAM=4g -XX:MaxRAMPercentage=25
                     (default ~1G max heap for every JVM; explicit -Xmx overrides)
  SBT_OPTS          : -Xms256m -Xmx1280m -Xss1m -XX:MaxMetaspaceSize=256m
                      -XX:ReservedCodeCacheSize=128m
  JAVA_OPTS         : unset by default (Metals bounded by the Layer 1 cap);
                      uncomment the pinned line in $CONF_FILE to enable
  BLOOP_JAVA_OPTS   : -Xmx1g (keeps bloop's default ZGC)
  scala-cli         : no env var (ignores heap flags with a warning); use
                      --java-opt or 'scala-cli config java.properties'
  jdtls             : no env var; ~1G via the cap; use nvim-jdtls -vmargs for 512m
  GC                : Java 26 default G1 kept; bloop ZGC kept (evidence-based)
EOF
}

install() {
  echo "=== Installing low-memory JVM config ==="
  require_java
  detect_tools

  local generated
  generated="$(mktemp)"
  generate_managed_file "$generated"

  if [ -f "$CONF_FILE" ] && ! grep -qF "$MARKER_START" "$CONF_FILE" 2>/dev/null; then
    echo "CONFLICT: $CONF_FILE exists and is not managed by this script." >&2
    echo "  Preserving it. Remove it manually, then re-run." >&2
    rm -f "$generated"
    exit 1
  fi

  if $DRY_RUN; then
    echo
    echo "[dry-run] would write $CONF_FILE"
    if [ -f "$CONF_FILE" ] && ! cmp -s "$generated" "$CONF_FILE"; then
      echo "[dry-run]   ($CONF_FILE currently differs; would back it up first)"
    fi
    echo "[dry-run] would register source block in $RC_FILE"
    echo
    echo "---- generated $CONF_FILE ----"
    cat "$generated"
    echo "---- would add to $RC_FILE ----"
    printf '%s\n' "$RC_BLOCK"
    echo "--------------------------------"
  else
    if [ -f "$CONF_FILE" ] && cmp -s "$generated" "$CONF_FILE"; then
      echo "  $CONF_FILE unchanged"
    else
      backup_file "$CONF_FILE"
      mkdir -p "$CONF_DIR"
      cp "$generated" "$CONF_FILE"
      echo "  wrote $CONF_FILE"
    fi
    append_or_replace_block "$RC_FILE" "$MARKER_START" "$MARKER_END" "$RC_BLOCK"
  fi
  rm -f "$generated"

  print_summary
  echo
  echo "Restart your shell or run: source $CONF_FILE"
}

uninstall() {
  echo "=== Uninstalling low-memory JVM config ==="
  if $DRY_RUN; then
    echo "[dry-run] would remove the source block from $RC_FILE"
    echo "[dry-run] would remove $CONF_FILE"
    return 0
  fi

  if [ -f "$RC_FILE" ] && grep -qF "$MARKER_START" "$RC_FILE" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    awk -v s="$MARKER_START" -v e="$MARKER_END" '
      $0 == s {skip=1; next}
      skip && $0 == e {skip=0; next}
      skip {next}
      {print}
    ' "$RC_FILE" > "$tmp"
    if cmp -s "$RC_FILE" "$tmp"; then
      rm -f "$tmp"
      echo "  no managed block in $RC_FILE"
    else
      backup_file "$RC_FILE"
      mv "$tmp" "$RC_FILE"
      echo "  removed source block from $RC_FILE"
    fi
  else
    echo "  no managed block in $RC_FILE"
  fi

  if [ -f "$CONF_FILE" ]; then
    if grep -qF "$MARKER_START" "$CONF_FILE" 2>/dev/null; then
      backup_file "$CONF_FILE"
      rm -f "$CONF_FILE"
      echo "  removed $CONF_FILE"
      rmdir "$CONF_DIR" 2>/dev/null || true
    else
      echo "  $CONF_FILE exists but is not managed (no marker); leaving it"
    fi
  else
    echo "  no $CONF_FILE"
  fi
}

verify() {
  echo "=== Verifying low-memory JVM config ==="
  local problems=0

  if [ -f "$CONF_FILE" ]; then
    if ! . "$CONF_FILE" 2>/dev/null; then
      echo "  FAIL: could not source $CONF_FILE" >&2
      problems=$((problems + 1))
    else
      echo "  OK: $CONF_FILE present and sources cleanly"
    fi
  else
    echo "  FAIL: $CONF_FILE missing" >&2
    problems=$((problems + 1))
  fi

  if [ -f "$RC_FILE" ] && grep -qF "$MARKER_START" "$RC_FILE" 2>/dev/null; then
    echo "  OK: source block registered in $RC_FILE"
  else
    echo "  FAIL: source block missing from $RC_FILE" >&2
    problems=$((problems + 1))
  fi

  echo
  echo "  Effective values (after sourcing $CONF_FILE):"
  echo "    JDK_JAVA_OPTIONS: ${JDK_JAVA_OPTIONS:-<unset>}"
  echo "    SBT_OPTS         : ${SBT_OPTS:-<unset>}"
  echo "    JAVA_OPTS        : ${JAVA_OPTS:-<unset>}"
  echo "    BLOOP_JAVA_OPTS  : ${BLOOP_JAVA_OPTS:-<unset>}"

  local var tok count
  for var in JDK_JAVA_OPTIONS SBT_OPTS; do
    for tok in -Xmx -Xms -Xss; do
      count=$({ printf '%s\n' "${!var:-}" | grep -o -F "$tok" 2>/dev/null || true; } | wc -l)
      if [ "$count" -gt 1 ]; then
        echo "  FAIL: $var contains $count '$tok' flags" >&2
        problems=$((problems + 1))
      fi
    done
  done

  echo
  if command -v java >/dev/null 2>&1; then
    local hsize ok
    hsize="$(java -XshowSettings:vm -version 2>&1 | grep -iE 'Max[^:]*Heap' | head -1)"
    ok="$(printf '%s' "$hsize" | awk '{
      for (i=1; i<=NF; i++) {
        if ($i ~ /^[0-9.]+[GMK]m?$/) {
          v=substr($i,1,length($i)-1); u=substr($i,length($i),1);
          if (u=="G") v=v*1024; else if (u=="K") v=v/1024;
          if (v<=1536) ok=1;
          break;
        }
      }
    } END { print (ok?1:0) }')"
    case "$ok" in
      1) echo "  OK: runtime max heap (default java, config applied): $hsize" ;;
      0) echo "  FAIL: runtime max heap exceeds 1536 MB: $hsize" >&2
         problems=$((problems + 1)) ;;
      *) echo "  runtime max heap: $hsize (could not parse; not failing)" ;;
    esac
  else
    echo "  FAIL: 'java' not found on PATH" >&2
    problems=$((problems + 1))
  fi

  echo
  if command -v sbt >/dev/null 2>&1 && command -v jps >/dev/null 2>&1; then
    echo "  note: run 'sbt -v' and inspect the java pid via 'jps -lv' to confirm"
    echo "        the -Xmx1280m reaches the sbt server; automated check skipped"
    echo "        (would need to launch sbt, which is slow)."
  else
    echo "  note: sbt runtime check skipped (sbt and/or jps not found)."
  fi

  echo
  if [ "$problems" -gt 0 ]; then
    echo "Verification FAILED: $problems problem(s)." >&2
    exit 3
  fi
  echo "Verification PASSED."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
  verify) verify ;;
esac