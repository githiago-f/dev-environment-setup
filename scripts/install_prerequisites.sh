#!/usr/bin/env bash
set -euo pipefail

install_with_pacman() {
  local pkg="$1"
  if pacman -Qi "$pkg" &>/dev/null; then
    echo "  $pkg already installed"
    return 0
  fi
  echo "  Installing $pkg..."
  sudo pacman -S --noconfirm "$pkg"
}

echo "=== Installing prerequisites ==="

install_with_pacman zip
install_with_pacman unzip

if command -v yay &>/dev/null; then
  echo "  yay already installed"
else
  echo "  Installing yay..."
  sudo pacman -S --needed --noconfirm base-devel git
  git clone https://aur.archlinux.org/yay.git /tmp/yay-install
  (cd /tmp/yay-install && makepkg -si --noconfirm)
  rm -rf /tmp/yay-install
fi

echo "=== Prerequisites installed ==="
