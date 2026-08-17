#!/usr/bin/env bash
set -euo pipefail

# configure-low-memory-jvm.sh
# Global low-memory JVM configuration for an 8 GB Linux dev machine with only
# ~5.2 GB realistically available (OS + Brave + Neovim take the rest).
#
# Architecture (everything under ~/.config/jvm-memory, sourced from .bashrc):
#   config               active profile (PROFILE=low|normal)
#   low-memory-jvm.sh    loader sourced from .bashrc
#   profiles/low         env vars for the 'low' profile
#   profiles/normal      env vars for the 'normal' profile
#
# Modes:
#   --profile low|normal   select the active profile (default: low)
#   --verify               verify effective configuration (exit 3 on problems)
#   --diagnose             snapshot of the real memory situation
#   --dry-run              show what install/uninstall would change
#   --uninstall            remove the managed config and .bashrc block
#   -h, --help             this help
#
# Exit codes: 0 ok, 1 error (missing java / config conflict), 2 usage,
#             3 verification problems.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jvm-memory"
CONF_FILE="$CONF_DIR/config"
LOADER_FILE="$CONF_DIR/low-memory-jvm.sh"
PROFILE_DIR="$CONF_DIR/profiles"
PROFILE_LOW="$PROFILE_DIR/low"
PROFILE_NORMAL="$PROFILE_DIR/normal"
RC_FILE="$HOME/.bashrc"

MARKER_START="# >>> low-memory-jvm >>>"
MARKER_END="# <<< low-memory-jvm <<<"
OLD_MARKER_START="# >>> low-memory-jvm-config >>>"
OLD_MARKER_END="# <<< low-memory-jvm-config <<<"
OLD_CONF_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/jvm-memory/jvm-memory.sh"

PROFILE=""
MODE=install
DRY_RUN=false
SBT_LAUNCH_TIMEOUT="${LMJ_VERIFY_TIMEOUT:-90}"

usage() {
  cat <<EOF
Usage: $0 [--profile low|normal] [--verify|--diagnose|--dry-run|--uninstall] [-h]

  (default)           install/update the managed config with --profile low
  --profile low       ultra-low profile: sbt 768m, Metals 512m, jdtls 384m, ZIO 384m
  --profile normal    relaxed profile:    sbt 1g,   Metals 768m, jdtls 512m, ZIO 512m
  --verify            verify the effective configuration (PASS/WARN/FAIL, exit 3 on FAIL)
  --diagnose          snapshot of RAM/Swap/JVM RSS and per-JVM flags
  --dry-run           print what would change without writing anything
  --uninstall         remove the managed config and the .bashrc source block
  -h, --help          show this help

Managed files:
  $CONF_DIR/
  $RC_FILE  (one source line inside marker comments)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      if [[ $# -lt 2 ]]; then usage >&2; exit 2; fi
      case "$2" in
        low|normal) PROFILE="$2"; shift 2 ;;
        *) echo "ERROR: unknown profile '$2' (use low or normal)" >&2; exit 2 ;;
      esac ;;
    --verify) MODE=verify; shift ;;
    --diagnose) MODE=diagnose; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --uninstall) MODE=uninstall; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
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

# Parse a heap size like 768m / 1g / 512m to MB.
parse_mb() {
  printf '%s' "$1" | awk '{
    v=$0; u=substr(v,length(v),1);
    if (u=="g"||u=="G") printf "%d", v*1024;
    else if (u=="k"||u=="K") printf "%d", v/1024;
    else printf "%d", v;
  }'
}

detect_tools() {
  echo "  Toolchain detected:"
  local t
  for t in java sbt scala scala-cli metals bloop cs jdtls jps jcmd; do
    if command -v "$t" >/dev/null 2>&1; then
      printf '    %-12s present\n' "$t"
    else
      printf '    %-12s absent\n' "$t"
    fi
  done
  [ -f /etc/sbt/sbtopts ] && echo "    /etc/sbt/sbtopts  present (root-level global sbt opts)" \
                          || echo "    /etc/sbt/sbtopts  absent"
}

# ---------------------------------------------------------------- generators

generate_config() {
  local profile="$1" out="$2"
  {
    printf '%s\n' "# >>> low-memory-jvm >>>"
    printf '%s\n' "# Active profile. Managed by configure-low-memory-jvm.sh --profile."
    printf '%s\n' "# You may edit PROFILE here; a bare re-run of the script keeps it."
    printf 'PROFILE=%s\n' "$profile"
    printf '%s\n' "# <<< low-memory-jvm <<<"
  } > "$out"
}

generate_loader() {
  local out="$1"
  {
    printf '%s\n' "# >>> low-memory-jvm >>>"
    printf '%s\n' "# Loader for the global low-memory JVM configuration."
    printf '%s\n' "# Managed by configure-low-memory-jvm.sh -- edits are lost on re-run."
    printf '%s\n' '_lmj_root="${XDG_CONFIG_HOME:-$HOME/.config}/jvm-memory"'
    printf '%s\n' '[ -r "$_lmj_root/config" ] && . "$_lmj_root/config"'
    printf '%s\n' 'case "${PROFILE:-low}" in'
    printf '%s\n' '  normal) [ -r "$_lmj_root/profiles/normal" ] && . "$_lmj_root/profiles/normal" ;;'
    printf '%s\n' '  *)      [ -r "$_lmj_root/profiles/low" ]    && . "$_lmj_root/profiles/low" ;;'
    printf '%s\n' 'esac'
    printf '%s\n' 'export LOW_MEMORY_JVM_ACTIVE="${PROFILE:-low}"'
    printf '%s\n' 'unset _lmj_root'
    printf '%s\n' "# <<< low-memory-jvm <<<"
  } > "$out"
}

# Profile content. $1 = profile name (low|normal), $2 = output file.
generate_profile() {
  local profile="$1" out="$2"
  local sbt_xms sbt_xmx metals_xms metals_xmx jdtls_xms jdtls_xmx zio_xmx bloop_xmx metaspace
  case "$profile" in
    normal)
      sbt_xms=256m;    sbt_xmx=1g
      metals_xms=128m; metals_xmx=768m
      jdtls_xms=128m;  jdtls_xmx=512m
      zio_xmx=512m
      bloop_xmx=1g
      metaspace=256m
      ;;
    *)
      sbt_xms=128m;    sbt_xmx=768m
      metals_xms=128m; metals_xmx=512m
      jdtls_xms=96m;   jdtls_xmx=384m
      zio_xmx=384m
      bloop_xmx=768m
      metaspace=192m
      ;;
  esac
  {
    printf '%s\n' "# >>> low-memory-jvm >>>"
    printf '%s\n' "# Profile: $profile  (managed by configure-low-memory-jvm.sh --profile $profile)"
    printf '%s\n' "# Ultra-low-memory JVM settings for an 8 GB box (~5.2 GB available)."
    printf '%s\n' "# Heap targets, NOT RSS limits: each process also uses metaspace,"
    printf '%s\n' "# thread stacks, code cache, direct buffers and GC structures."
    printf '%s\n' ""
    printf '%s\n' '_lmj_flag() {'
    printf '%s\n' '  case "$1" in'
    printf '%s\n' '    -Xmx*|-Xms*|-Xss*) printf "%s" "${1%%[0-9]*}" ;;'
    printf '%s\n' '    -XX:*) printf "%s" "${1%%=*}" ;;'
    printf '%s\n' '    *) printf "%s" "$1" ;;'
    printf '%s\n' '  esac'
    printf '%s\n' '}'
    printf '%s\n' '_lmj_append_var() {'
    printf '%s\n' '  local var="$1" val="$2"'
    printf '%s\n' '  local cur t flag w'
    printf '%s\n' '  local -a add=()'
    printf '%s\n' '  cur="${!var:-}"'
    printf '%s\n' '  for t in $val; do'
    printf '%s\n' '    case " $cur " in'
    printf '%s\n' '      *" $t "*) continue ;;'
    printf '%s\n' '    esac'
    printf '%s\n' '    flag="$(_lmj_flag "$t")"'
    printf '%s\n' '    for w in $cur; do'
    printf '%s\n' '      if [ -n "$w" ] && [ "$(_lmj_flag "$w")" = "$flag" ]; then'
    printf '%s\n' '        printf "%s\n" "  jvm-memory: $var already has '"'"'$w'"'"'; keeping it, skipping '"'"'$t'"'"'" >&2'
    printf '%s\n' '        t=""; break'
    printf '%s\n' '      fi'
    printf '%s\n' '    done'
    printf '%s\n' '    [ -n "$t" ] && add+=("$t")'
    printf '%s\n' '  done'
    printf '%s\n' '  if [ "${#add[@]}" -gt 0 ]; then'
    printf '%s\n' '    if [ -n "$cur" ]; then export "$var=$cur ${add[*]}"; else export "$var=${add[*]}"; fi'
    printf '%s\n' '  fi'
    printf '%s\n' '}'
    printf '%s\n' ""
    printf '%s\n' '# Universal (every JDK launcher prepends JDK_JAVA_OPTIONS): a default'
    printf '%s\n' '# heap CEILING of ~1G. This is NOT a forced -Xmx: any explicit -Xmx on a'
    printf '%s\n' '# command line overrides it, so large apps remain configurable.'
    printf '%s\n' "_lmj_append_var JDK_JAVA_OPTIONS '-Xmx=4g -XX:MaxRAMPercentage=25'"
    printf '%s\n' ""
    printf '%s\n' '# sbt: global user-level mechanism (SBT_OPTS). Beats JAVA_OPTS,'
    printf '%s\n' '# JAVA_TOOL_OPTIONS and the default -mem 1024m in the sbt runner.'
    printf '%s\n' "# If sbt/scalac throws StackOverflowError, raise -Xss to 1m."
    printf '%s\n' "_lmj_append_var SBT_OPTS '-Xms$sbt_xms -Xmx$sbt_xmx -Xss512k -XX:MaxMetaspaceSize=$metaspace'"
    printf '%s\n' ""
    printf '%s\n' '# Metals: the coursier launcher expands JAVA_OPTS and nvim-metals reads'
    printf '%s\n' '# it too, so JAVA_OPTS is the user-global server mechanism here. Note:'
    printf '%s\n' '# scala-cli warns (and ignores) heap flags in JAVA_OPTS - if you install'
    printf '%s\n' '# scala-cli, use `scala-cli --java-opt` / `scala-cli config` instead.'
    printf '%s\n' "# nvim-metals alternative: settings.serverProperties = { '-Xmx$metals_xmx' }"
    printf '%s\n' "_lmj_append_var JAVA_OPTS '-Xms$metals_xms -Xmx$metals_xmx -Xss512k -XX:MaxMetaspaceSize=$metaspace'"
    printf '%s\n' ""
    printf '%s\n' '# Bloop (standalone `bloop start`): BLOOP_JAVA_OPTS. The launcher keeps'
    printf '%s\n' '# its ZGC defaults; we only cap the heap. Metals-spawned Bloop is a'
    printf '%s\n' '# SEPARATE JVM controlled by the Metals `bloopJvmProperties` setting'
    printf '%s\n' "# (default -Xmx1G) - set it to ['-Xmx$bloop_xmx'] to match."
    printf '%s\n' "_lmj_append_var BLOOP_JAVA_OPTS '-Xmx$bloop_xmx'"
    printf '%s\n' ""
    printf '%s\n' '# jdtls: the eclipse.jdt.ls launcher does NOT read these from the'
    printf '%s\n' '# environment. JDTLS_JVM_ARGS is honored by launchers/wrappers (e.g.'
    printf '%s\n' '# nixvim) and is the override value for the nvim-jdtls cmd snippet'
    printf '%s\n' '# (see README). It is not auto-applied.'
    printf '%s\n' "# (jdtls target: -Xms$jdtls_xms -Xmx$jdtls_xmx -Xss512k -XX:MaxMetaspaceSize=128m)"
    printf '%s\n' "_lmj_append_var JDTLS_JVM_ARGS '-Xms$jdtls_xms -Xmx$jdtls_xmx -Xss512k -XX:MaxMetaspaceSize=128m'"
    printf '%s\n' ""
    printf '%s\n' '# ZIO development application: NOT set globally. It belongs to the'
    printf '%s\n' '# project, e.g. build.sbt:  run / javaOptions ++= Seq("-Xms64m",'
    printf '%s\n' "# \"-Xmx$zio_xmx\", \"-Xss512k\")   or scala-cli:  --java-opt \"-Xmx$zio_xmx\""
    printf '%s\n' ""
    printf '%s\n' 'export LOW_MEMORY_JVM_ACTIVE="'"$profile"'"'
    printf '%s\n' 'unset -f _lmj_append_var _lmj_flag'
    printf '%s\n' "# <<< low-memory-jvm <<<"
  } > "$out"
}

RC_BLOCK=$'# >>> low-memory-jvm >>>\n# Global low-memory JVM settings (configure-low-memory-jvm.sh)\n[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/jvm-memory/low-memory-jvm.sh" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/jvm-memory/low-memory-jvm.sh"\n# <<< low-memory-jvm <<<'

# ------------------------------------------------------------- write helpers

# Write generated file $1 to managed path $2. Returns non-zero on conflict.
install_managed_file() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && ! grep -qF "$MARKER_START" "$dst" 2>/dev/null; then
    echo "CONFLICT: $dst exists without managed markers; preserving it." >&2
    echo "  Remove it (or let --uninstall handle it) to let this script manage it." >&2
    return 1
  fi
  if $DRY_RUN; then
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
      echo "[dry-run] $dst unchanged"
    else
      echo "[dry-run] would write $dst"
    fi
    return 0
  fi
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    echo "  $dst unchanged"
    return 0
  fi
  backup_file "$dst"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "  wrote $dst"
}

# Update .bashrc: remove any old/new managed region, then ensure the new block.
update_bashrc() {
  local rc="$RC_FILE" block="$1" tmp
  if [ ! -f "$rc" ]; then
    if $DRY_RUN; then
      echo "[dry-run] would create $rc"
      return 0
    fi
    printf '%s\n' "$block" > "$rc"
    echo "  created $rc"
    return 0
  fi
  tmp="$(mktemp)"
  awk -v os="$OLD_MARKER_START" -v oe="$OLD_MARKER_END" -v s="$MARKER_START" -v e="$MARKER_END" '
    $0 == os {skip=1; next} skip && $0 == oe {skip=0; next}
    $0 == s {skip=1; next} skip && $0 == e {skip=0; next}
    skip {next}
    {print}
  ' "$rc" > "$tmp"
  printf '%s\n' "$block" >> "$tmp"
  if cmp -s "$rc" "$tmp"; then
    rm -f "$tmp"
    echo "  $rc unchanged (block already up to date)"
    return 0
  fi
  if $DRY_RUN; then
    rm -f "$tmp"
    echo "[dry-run] would update $rc"
    return 0
  fi
  backup_file "$rc"
  mv "$tmp" "$rc"
  echo "  updated $rc"
}

# Remove old managed files from the previous script version.
migrate_old_layout() {
  local old_rc="$RC_FILE"
  if [ -f "$OLD_CONF_FILE" ]; then
    if grep -qF "$OLD_MARKER_START" "$OLD_CONF_FILE" 2>/dev/null; then
      if $DRY_RUN; then
        echo "[dry-run] would remove old managed file $OLD_CONF_FILE"
      else
        backup_file "$OLD_CONF_FILE"
        rm -f "$OLD_CONF_FILE"
        echo "  removed old managed file $OLD_CONF_FILE"
      fi
    else
      echo "CONFLICT: $OLD_CONF_FILE exists without managed markers; preserving it." >&2
    fi
  fi
}

# ------------------------------------------------------------------ install

print_summary() {
  local profile="$1"
  echo
  echo "=== Active profile: $profile ==="
  echo "  Heap targets (not RSS limits - each JVM also uses metaspace, thread"
  echo "  stacks, code cache, direct buffers and GC structures on top):"
  echo "    sbt      : -Xms${SBT_XMS:-} -Xmx${SBT_XMX:-} -Xss512k -XX:MaxMetaspaceSize=${SBT_META:-}"
  echo "    Metals   : -Xms${METALS_XMS:-} -Xmx${METALS_XMX:-} -Xss512k -XX:MaxMetaspaceSize=${METALS_META:-}"
  echo "    jdtls    : -Xms${JDTLS_XMS:-} -Xmx${JDTLS_XMX:-} -Xss512k -XX:MaxMetaspaceSize=128m (via launcher args)"
  echo "    ZIO dev  : -Xmx${ZIO_XMX:-} (project-owned, not global)"
  echo "    Bloop    : -Xmx${BLOOP_XMX:-} (BLOOP_JAVA_OPTS; Metals-spawned bloop via bloopJvmProperties)"
  echo "    Other JVM: no forced Xmx (JDK_JAVA_OPTIONS only lowers the default ceiling to ~1G)"
  echo
  echo "  Warnings:"
  echo "    * -Xss512k is aggressive. If sbt/scalac/Metals throws StackOverflowError,"
  echo "      raise the stack to -Xss1m (edit the profile's -Xss values or use --profile normal)."
  echo "    * JAVA_OPTS heap flags are ignored (with a warning) by scala-cli."
  echo "    * jdtls is not applied from the environment; wire JDTLS_JVM_ARGS into the"
  echo "      launcher or nvim-jdtls cmd (see README)."
  echo "    * This config is intentionally conservative because Brave runs alongside"
  echo "      the JVM toolchain (see README)."
}

install() {
  echo "=== Installing low-memory JVM config ==="
  require_java
  detect_tools
  migrate_old_layout

  # Resolve the active profile: explicit --profile wins, else keep config's,
  # else default to low.
  if [ -z "$PROFILE" ]; then
    if [ -f "$CONF_FILE" ] && grep -qF "$MARKER_START" "$CONF_FILE" 2>/dev/null; then
      PROFILE="$(sed -n 's/^PROFILE=//p' "$CONF_FILE" | head -1)"
      case "${PROFILE:-}" in low|normal) ;; *) PROFILE=low ;; esac
    else
      PROFILE=low
    fi
  fi

  local tmp; tmp="$(mktemp)"
  local conflicts=0
  generate_config "$PROFILE" "$tmp"
  install_managed_file "$tmp" "$CONF_FILE" || conflicts=1
  generate_loader "$tmp"
  install_managed_file "$tmp" "$LOADER_FILE" || conflicts=1
  generate_profile low "$tmp"
  install_managed_file "$tmp" "$PROFILE_LOW" || conflicts=1
  generate_profile normal "$tmp"
  install_managed_file "$tmp" "$PROFILE_NORMAL" || conflicts=1
  rm -f "$tmp"

  if [ "$conflicts" -ne 0 ]; then
    echo
    echo "ERROR: one or more managed files are not owned by this script." >&2
    echo "  Preserved them as-is; resolve the conflicts above, then re-run." >&2
    exit 1
  fi

  update_bashrc "$RC_BLOCK"

  # Values used by the summary table.
  case "$PROFILE" in
    normal)
      SBT_XMS=256m; SBT_XMX=1g; SBT_META=256m
      METALS_XMS=128m; METALS_XMX=768m; METALS_META=256m
      JDTLS_XMS=128m; JDTLS_XMX=512m
      ZIO_XMX=512m; BLOOP_XMX=1g ;;
    *)
      SBT_XMS=128m; SBT_XMX=768m; SBT_META=192m
      METALS_XMS=128m; METALS_XMX=512m; METALS_META=192m
      JDTLS_XMS=96m; JDTLS_XMX=384m
      ZIO_XMX=384m; BLOOP_XMX=768m ;;
  esac
  print_summary "$PROFILE"
  echo
  echo "Restart your shell or run: source $LOADER_FILE"
  echo "Switch profiles with:       $0 --profile normal"
}

# ------------------------------------------------------------------ uninstall

uninstall() {
  echo "=== Uninstalling low-memory JVM config ==="
  if $DRY_RUN; then
    echo "[dry-run] would remove the managed block from $RC_FILE"
    echo "[dry-run] would remove $CONF_DIR (config, loader, profiles)"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  awk -v os="$OLD_MARKER_START" -v oe="$OLD_MARKER_END" -v s="$MARKER_START" -v e="$MARKER_END" '
    $0 == os {skip=1; next} skip && $0 == oe {skip=0; next}
    $0 == s {skip=1; next} skip && $0 == e {skip=0; next}
    skip {next}
    {print}
  ' "$RC_FILE" > "$tmp" 2>/dev/null || true
  if [ -f "$RC_FILE" ] && ! cmp -s "$RC_FILE" "$tmp"; then
    backup_file "$RC_FILE"
    mv "$tmp" "$RC_FILE"
    echo "  removed managed block from $RC_FILE"
  else
    rm -f "$tmp"
    echo "  no managed block in $RC_FILE"
  fi

  local f removed=0 preserved=0
  for f in "$CONF_FILE" "$LOADER_FILE" "$PROFILE_LOW" "$PROFILE_NORMAL" "$OLD_CONF_FILE"; do
    if [ -f "$f" ]; then
      if grep -qF "$MARKER_START" "$f" 2>/dev/null || grep -qF "$OLD_MARKER_START" "$f" 2>/dev/null; then
        backup_file "$f"
        rm -f "$f"
        echo "  removed $f"
        removed=1
      else
        echo "  $f exists but is not managed (no marker); leaving it"
        preserved=1
      fi
    fi
  done
  if [ "$removed" -eq 1 ]; then rmdir "$CONF_DIR/profiles" "$CONF_DIR" 2>/dev/null || true; fi
  if [ "$preserved" -eq 1 ]; then
    echo "  Note: some files were preserved because they are not owned by this script."
  fi
}

# ------------------------------------------------------------------ verify

# Extract a flag like -Xmx768m / -Xss512k from a value string.
flag_value() {
  local val="$1" flag="$2"
  printf '%s' "$val" | grep -o -E -- "${flag}[0-9]+[mMgGkK]" 2>/dev/null | head -1 || true
}

# Expected heaps (MB) for the active profile.
profile_heaps() {
  local p="$1"
  case "$p" in
    normal) echo "1024 768 1024 512" ;; # sbt metals bloop jdtls
    *)      echo "768 512 768 384" ;;
  esac
}

verify() {
  echo "=== Verifying low-memory JVM config ==="
  local problems=0

  if [ -f "$LOADER_FILE" ]; then
    if . "$LOADER_FILE" 2>/dev/null; then
      echo "  PASS: $LOADER_FILE sources cleanly"
    else
      echo "  FAIL: could not source $LOADER_FILE" >&2
      problems=$((problems + 1))
    fi
  else
    echo "  FAIL: $LOADER_FILE missing" >&2
    problems=$((problems + 1))
  fi

  if [ -f "$CONF_FILE" ] && grep -qF "PROFILE=" "$CONF_FILE" 2>/dev/null; then
    echo "  PASS: active profile = ${PROFILE:-<unknown>}"
  else
    echo "  FAIL: $CONF_FILE missing or has no PROFILE" >&2
    problems=$((problems + 1))
  fi

  if [ -f "$RC_FILE" ] && grep -qF "$MARKER_START" "$RC_FILE" 2>/dev/null; then
    echo "  PASS: source block registered in $RC_FILE"
  else
    echo "  FAIL: source block missing from $RC_FILE" >&2
    problems=$((problems + 1))
  fi

  echo
  echo "  Effective values (after sourcing $LOADER_FILE):"
  echo "    JDK_JAVA_OPTIONS : ${JDK_JAVA_OPTIONS:-<unset>}"
  echo "    SBT_OPTS         : ${SBT_OPTS:-<unset>}"
  echo "    JAVA_OPTS        : ${JAVA_OPTS:-<unset>}"
  echo "    BLOOP_JAVA_OPTS  : ${BLOOP_JAVA_OPTS:-<unset>}"
  echo "    JDTLS_JVM_ARGS   : ${JDTLS_JVM_ARGS:-<unset>}"

  local read_heaps sbt_t metals_t bloop_t jdtls_t
  read -r sbt_t metals_t bloop_t jdtls_t <<< "$(profile_heaps "${PROFILE:-low}")"

  local val mxmb varname
  for pair in "SBT_OPTS:$sbt_t" "JAVA_OPTS:$metals_t" "BLOOP_JAVA_OPTS:$bloop_t" "JDTLS_JVM_ARGS:$jdtls_t"; do
    varname="${pair%%:*}"
    val=$(flag_value "${!varname:-}" -Xmx)
    if [ -z "$val" ]; then
      echo "  FAIL: $varname has no -Xmx" >&2
      problems=$((problems + 1))
      continue
    fi
    mxmb=$(parse_mb "${val#-Xmx}")
    if [ "$mxmb" -gt "${pair##*:}" ]; then
      echo "  FAIL: $varname $val exceeds profile target ${pair##*:}m" >&2
      problems=$((problems + 1))
    else
      echo "  PASS: $varname $val <= ${pair##*:}m (profile target)"
    fi
  done

  # Duplicate/conflicting flags within each var.
  local var tok count
  for var in JDK_JAVA_OPTIONS SBT_OPTS JAVA_OPTS BLOOP_JAVA_OPTS; do
    for tok in -Xmx -Xms -Xss; do
      count=$({ printf '%s\n' "${!var:-}" | grep -o -F "$tok" 2>/dev/null || true; } | wc -l)
      if [ "$count" -gt 1 ]; then
        echo "  FAIL: $var contains $count '$tok' flags" >&2
        problems=$((problems + 1))
      fi
    done
  done

  # Global ceiling must NOT be a forced Xmx.
  if printf '%s' "${JDK_JAVA_OPTIONS:-}" | grep -q -E -- '-Xmx'; then
    echo "  FAIL: JDK_JAVA_OPTIONS must not force a global -Xmx (found one)" >&2
    problems=$((problems + 1))
  else
    echo "  PASS: no global -Xmx (JDK_JAVA_OPTIONS is a default ceiling only)"
  fi

  echo
  if command -v java >/dev/null 2>&1; then
    local hsize ok
    hsize="$(java -XshowSettings:vm -version 2>&1 | grep -iE 'Max[^:]*Heap' | head -1)"
    ok="$(printf '%s' "$hsize" | awk '{
      for (i=1; i<=NF; i++) if ($i ~ /^[0-9.]+[GMK]m?$/) {
        v=substr($i,1,length($i)-1); u=substr($i,length($i),1);
        if (u=="G") v=v*1024; else if (u=="K") v=v/1024;
        if (v<=1536) ok=1; break;
      }
    } END { print (ok?1:0) }')"
    case "$ok" in
      1) echo "  PASS: default java max heap (config applied): $hsize  [heap max, not RSS]" ;;
      0) echo "  FAIL: default java max heap exceeds 1536 MB: $hsize" >&2
         problems=$((problems + 1)) ;;
      *) echo "  WARN: could not parse java max heap: $hsize" ;;
    esac
  else
    echo "  FAIL: 'java' not found on PATH" >&2
    problems=$((problems + 1))
  fi

  verify_running_jvms

  # sbt: actually launch it and inspect the launcher JVM's arguments.
  if command -v sbt >/dev/null 2>&1 && command -v jps >/dev/null 2>&1; then
    sbt_launch_check
  else
    echo "  WARN: sbt launch check skipped (sbt and/or jps not found)."
  fi

  echo
  echo "  Metals/jdtls: an active LSP process is required for live verification."
  echo "    If Metals/jdtls fail to initialize under their configured heap,"
  echo "    re-run with:  $0 --profile normal"

  echo
  if [ "$problems" -gt 0 ]; then
    echo "Verification FAILED: $problems problem(s)." >&2
    exit 3
  fi
  echo "Verification PASSED."
}

verify_running_jvms() {
  echo
  echo "  Running JVMs (jps -lv):"
  if command -v jps >/dev/null 2>&1; then
    local lines
    lines="$(jps -lv 2>/dev/null || true)"
    if [ -z "$lines" ]; then
      echo "    (none)"
    else
      printf '%s\n' "$lines" | sed 's/^/    /'
    fi
    printf '%s\n' "$lines" | grep -q -E 'sbt-launch|sbt\.boot' 2>/dev/null \
      && echo "    note: an sbt server is already running (check its -Xmx above)" || true
  else
    echo "    (jps not available)"
  fi
}

# Launch sbt in a temp dir and confirm the launcher JVM carries our -Xmx.
sbt_launch_check() {
  echo
  echo "  Launching sbt to verify its JVM arguments (timeout ${SBT_LAUNCH_TIMEOUT}s)..."
  local tmp pid line="" mx want found=""
  local deadline
  tmp="$(mktemp -d)"
  ( cd "$tmp" && timeout "$SBT_LAUNCH_TIMEOUT" sbt -batch "about" >/dev/null 2>&1 ) &
  pid=$!
  deadline=$(( $(date +%s) + SBT_LAUNCH_TIMEOUT ))
  while :; do
    line="$(jps -lv 2>/dev/null | grep -E 'sbt-launch|sbt\.boot' | head -1 || true)"
    if [ -n "$line" ]; then found=1; break; fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    if [ "$(date +%s)" -ge "$deadline" ]; then break; fi
    sleep 0.5
  done
  kill "$pid" 2>/dev/null || true
  pkill -P "$pid" 2>/dev/null || true
  rm -rf "$tmp"
  if [ -n "$found" ]; then
    mx=$(printf '%s' "$line" | grep -o -E -- '-Xmx[0-9]+[mMgGkK]' | head -1 || true)
    if [ -n "$mx" ]; then
      want=$(flag_value "$SBT_OPTS" -Xmx)
      if [ -n "$want" ] && [ "$mx" = "$want" ]; then
        echo "  PASS: sbt launcher JVM running with $mx (matches SBT_OPTS)"
      else
        echo "  WARN: sbt launcher JVM running with $mx (expected $want from SBT_OPTS)"
      fi
    else
      echo "  WARN: sbt launcher JVM found but no -Xmx in its args:"
      printf '    %s\n' "$line"
    fi
  else
    echo "  WARN: sbt did not reach the launcher JVM within ${SBT_LAUNCH_TIMEOUT}s."
    echo "    Run 'sbt -v' manually and inspect 'jps -lv' for the -Xmx from SBT_OPTS."
  fi
}

# ------------------------------------------------------------------ diagnose

diagnose() {
  echo "=== Memory diagnosis ==="
  echo
  echo "-- Physical memory (/proc/meminfo) --"
  if [ -r /proc/meminfo ]; then
    awk '/MemTotal|MemAvailable|SwapTotal|SwapFree/ { printf "    %-16s %s kB (%.1f GiB)\n", $1, $2, $2/1048576 }' /proc/meminfo
  else
    echo "    (no /proc/meminfo)"
  fi

  echo
  echo "-- Largest processes by RSS --"
  if command -v ps >/dev/null 2>&1; then
    ps -eo pid,rss,%mem,comm,args --sort=-rss 2>/dev/null | head -15
  else
    echo "    (ps not available)"
  fi

  echo
  echo "-- JVM processes (jps -lv) --"
  if command -v jps >/dev/null 2>&1; then
    jps -lv 2>/dev/null | sed 's/^/    /' || echo "    (jps found nothing)"
  else
    echo "    (jps not available)"
  fi

  echo
  echo "-- Per-JVM effective flags and RSS --"
  local jvm_total=0
  local identified_any=false
  if command -v jps >/dev/null 2>&1; then
    local pid cmd rss args mx ms xss meta name
    while read -r pid cmd; do
case "$cmd" in
      *Jps*) continue ;;
    esac
      rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)"
      args="$(ps -o args= -p "$pid" 2>/dev/null || true)"
      name="$(identify_process "$cmd" "$args")"
      mx=$(jcmd_vmflag "$pid" MaxHeapSize)
      ms=$(jcmd_vmflag "$pid" InitialHeapSize)
      xss=$(jcmd_vmflag "$pid" ThreadStackSize)
      meta=$(jcmd_vmflag "$pid" MaxMetaspaceSize)
      jvm_total=$((jvm_total + ${rss:-0}))
      [ -n "$name" ] && identified_any=true
      printf '    pid %-8s rss %6d MB  %-14s %s\n' "$pid" "$((rss/1024))" "$name" "$cmd"
      printf '      MaxHeap=%sMB InitialHeap=%sMB Stack=%sKB Metaspace=%sMB\n' \
        "${mx:--}" "${ms:--}" "$xss" "$meta"
      if [ -n "$args" ]; then
        printf '      literal args: %s\n' "$(printf '%s' "$args" | grep -o -E -- '-Xmx[0-9]+[mMgGkK]|-Xms[0-9]+[mMgGkK]|-Xss[0-9]+[mMgGkK]|-XX:MaxMetaspaceSize=[0-9]+[mMgGkK]' | tr '\n' ' ')"
      fi
    done < <(jps -l 2>/dev/null || true)
  fi

  echo
  echo "-- JVM RSS total --"
  echo "    ${jvm_total} MB across running JVMs"
  if ! $identified_any; then
    echo "    (no JVM processes detected)"
  fi

  echo
  echo "-- Identifying workload processes --"
  if command -v ps >/dev/null 2>&1; then
    local target
    for target in nvim metals jdtls sbt bloop brave chrome; do
      local found
      found=$(ps -eo rss=,comm=,args= 2>/dev/null | grep -i -- "$target" | head -3 || true)
      if [ -n "$found" ]; then
        printf '    %-8s\n%s\n' "$target" "$(printf '%s\n' "$found" | sed 's/^/      /')"
      else
        printf '    %-8s not running\n' "$target"
      fi
    done
  fi

  echo
  echo "  Reminder: -Xmx is the heap MAXIMUM, not RSS. RSS = heap + metaspace +"
  echo "  thread stacks + code cache + direct buffers + native + GC structures."
  echo "  Use 'jcmd <pid> GC.heap_info' to see committed vs used heap."
}

identify_process() {
  local cmd="$1" args="$2"
  case "$args" in
    *org.scalameta.metals*) echo "metals" ;;
    *eclipse.jdt.ls*|*jdtls*) echo "jdtls" ;;
    *sbt-launch*|*sbt.boot*) echo "sbt" ;;
    *bloop*) echo "bloop" ;;
    *zio*|*ZioMain*|*zio.app*) echo "zio-app" ;;
    *scala-cli*|*scala.meta*|*dotty*|*scalac*) echo "scala-toolchain" ;;
    *) echo "" ;;
  esac
}

jcmd_vmflag() {
  local pid="$1" flag="$2" out
  if command -v jcmd >/dev/null 2>&1; then
    out="$(jcmd "$pid" VM.flags 2>/dev/null | tr ' ' '\n' | grep -- "-XX:$flag=" | head -1 || true)"
    case "$out" in
      *'='*) printf '%d' "$(( ${out##*=} / 1048576 ))" ;;
    esac
  fi
}

# --------------------------------------------------------------------- main

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
  verify) verify ;;
  diagnose) diagnose ;;
esac
