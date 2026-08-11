#!/bin/bash
set -euo pipefail

echo "=== NVIM copy ==="
rm -rf ./config/nvim/
cp ~/.config/nvim/ ./config/nvim/ -rf

echo "=== UPDATED ==="

