#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REQ_FILE="$REPO_DIR/github_requirements.txt"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

detect_asset() {
  local assets="$1"
  local arch
  arch="$(uname -m)"
  local os
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"

  # normalize arch names
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
  esac

  # try matching os + arch first, then os only, then any
  for pattern in "${os}_${arch}" "${os}-${arch}" "${os}" "${arch}"; do
    echo "$assets" | tr ',' '\n' | grep -i "$pattern" | head -1 && return 0
  done
  echo "$assets" | tr ',' '\n' | head -1
}

install_github_release() {
  local repo="$1"
  local tag url name

  echo "--- Installing $repo ---"

  local release_json
  release_json=$(curl -s "https://api.github.com/repos/${repo}/releases/latest")
  tag=$(echo "$release_json" | grep '"tag_name"' | cut -d'"' -f4)
  [ -z "$tag" ] && { echo "  Warning: could not fetch latest release"; return; }

  local pairs selected
  pairs=$(echo "$release_json" | awk -F'"' '
    /"assets":/ {a=1; next}
    a && /"name":/ {n=$4}
    a && /"browser_download_url":/ {print n "|" $4; n=""}
  ')

  [ -z "$pairs" ] && { echo "  Warning: no assets found"; return; }

  selected=$(detect_asset "$(echo "$pairs" | cut -d'|' -f1 | paste -sd, -)")
  url=$(echo "$pairs" | grep -F "$selected" | cut -d'|' -f2 | head -1)
  [ -z "$url" ] && url=$(echo "$pairs" | cut -d'|' -f2 | head -1)

  name="${repo##*/}"

  echo "  Downloading $name $tag..."
  curl -fsSL "$url" -L -o "/tmp/${name}.download"

  # try to extract or just make executable
  mkdir -p "/tmp/${name}_extract"
  case "$url" in
    *.tar.gz|*.tgz)
      tar -xzf "/tmp/${name}.download" -C "/tmp/${name}_extract"
      find "/tmp/${name}_extract" -type f -executable -exec cp {} "$BIN_DIR/${name}" \;
      ;;
    *.zip)
      unzip -o "/tmp/${name}.download" -d "/tmp/${name}_extract"
      find "/tmp/${name}_extract" -type f -exec cp {} "$BIN_DIR/${name}" 2>/dev/null \; || true
      ;;
    *)
      cp "/tmp/${name}.download" "$BIN_DIR/${name}"
      chmod +x "$BIN_DIR/${name}"
      ;;
  esac

  rm -f "/tmp/${name}.download"
  rm -rf "/tmp/${name}_extract"

  echo "  Installed to $BIN_DIR/${name}"
}

while IFS= read -r line; do
  line="${line%%#*}"
  line="${line// /}"
  [ -z "$line" ] && continue
  install_github_release "$line"
done < "$REQ_FILE"

echo
echo "=== GitHub releases installed ==="
echo "  PATH includes: $BIN_DIR"
