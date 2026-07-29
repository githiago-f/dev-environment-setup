#!/usr/bin/env bash
set -euo pipefail

EMAIL="tfarias@protonmail.com"
SSH_KEY="$HOME/.ssh/id_ed25519"

if (ssh -T git@github.com 2>&1 || true) | grep -q "successfully authenticated"; then
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
echo "3. Add it as an Authentication key (for Git push/pull) — click Save"
echo "4. Add it again as a Signing key   (for commit verification) — click Save"
echo
echo "   The same key can be used for both; just choose the Key type"
echo "   from the dropdown in GitHub when adding each one."
echo
read -rp "Press Enter after you have added the key to GitHub..."

echo
echo "Testing connection to GitHub..."
if (ssh -T git@github.com 2>&1 || true) | grep -q "successfully authenticated"; then
  echo "  ✓ Authentication works"
else
  echo "  ⚠ SSH connection failed — check your key"
  exit 1
fi

echo
echo "=== Configuring Git for SSH commit signing ==="

git config --global gpg.format ssh
git config --global user.signingkey "${SSH_KEY}.pub"
git config --global commit.gpgsign true
git config --global tag.gpgsign true
echo "  ✓ Git is now configured to sign all commits and tags with your SSH key"

ALLOWED_SIGNERS="$HOME/.ssh/allowed_signers"
if ! grep -q "$EMAIL" "$ALLOWED_SIGNERS" 2>/dev/null; then
  echo "$EMAIL namespaces=\"git\" $(cat "${SSH_KEY}.pub")" >> "$ALLOWED_SIGNERS"
  echo "  ✓ Added your key to $ALLOWED_SIGNERS for local verification"
else
  echo "  ✓ Your key is already in $ALLOWED_SIGNERS"
fi
git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"
echo "  ✓ Git is configured to use $ALLOWED_SIGNERS"

echo
echo "=== SSH signing setup complete ==="
echo "Your next commit can be signed with: git commit -S -m \"message\""
