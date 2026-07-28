#!/usr/bin/env bash
set -euo pipefail

EMAIL="tfarias@protonmail.com"
SSH_KEY="$HOME/.ssh/id_ed25519"

if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  echo "GitHub SSH already configured — skipping"
  exit 0
fi

if [ -f "$SSH_KEY" ]; then
  echo "SSH key already exists at $SSH_KEY"
else
  echo "Generating a new Ed25519 SSH key..."
  ssh-keygen -t ed25519 -C "$EMAIL" -f "$SSH_KEY" -N ""
fi

echo
echo "=== Your public SSH key ==="
cat "${SSH_KEY}.pub"
echo
echo "1. Copy the key above"
echo "2. Go to https://github.com/settings/ssh/new"
echo "3. Paste it and save"
echo
read -rp "Press Enter after you have added the key to GitHub..."

echo
echo "Testing connection to GitHub..."
ssh -T git@github.com || true
