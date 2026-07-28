#!/usr/bin/env bash
set -euo pipefail

YAY_AVAILABLE=false
if command -v yay &>/dev/null; then
  YAY_AVAILABLE=true
fi

install_zig() {
  echo "=== Installing Zig ==="
  if $YAY_AVAILABLE; then
    yay -S --noconfirm zig
  else
    local version
    version=$(curl -s https://ziglang.org/download/index.json | python3 -c "import sys,json; print(json.load(sys.stdin)['master']['version'])")
    local url="https://ziglang.org/builds/zig-linux-x86_64-${version}.tar.xz"
    curl -fsSL "$url" -o /tmp/zig.tar.xz
    sudo tar -xf /tmp/zig.tar.xz -C /usr/local --strip-components=1
    rm /tmp/zig.tar.xz
    echo "Zig $version installed to /usr/local"
  fi
}

install_sdkman() {
  echo "=== Installing SDKMAN ==="
  if [ -d "$HOME/.sdkman" ]; then
    echo "SDKMAN already installed"
  else
    curl -s "https://get.sdkman.io" | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"
  fi
}

install_nvm() {
  echo "=== Installing NVM ==="
  if [ -d "$HOME/.nvm" ]; then
    echo "NVM already installed"
  else
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts
  fi
}

install_go() {
  echo "=== Installing Go ==="
  if $YAY_AVAILABLE; then
    yay -S --noconfirm go
  else
    local version
    version=$(curl -s https://go.dev/dl/ | grep -oP 'go[\d]+\.[\d]+\.[\d]+\.linux-amd64\.tar\.gz' | head -1 | sed 's/\.linux-amd64\.tar\.gz//')
    curl -fsSL "https://go.dev/dl/${version}.linux-amd64.tar.gz" -o /tmp/go.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
    export PATH="$PATH:/usr/local/go/bin"
    echo "Go installed: $(go version)"
  fi
}

install_golangci_lint() {
  echo "=== Installing golangci-lint ==="
  if $YAY_AVAILABLE; then
    yay -S --noconfirm golangci-lint-bin
  else
    curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "$(go env GOPATH)/bin" v1.60.1
  fi
}

install_nvim() {
  echo "=== Installing Neovim ==="
  if $YAY_AVAILABLE; then
    yay -S --noconfirm neovim
  else
    curl -fsSL https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz -o /tmp/nvim.tar.gz
    sudo rm -rf /opt/nvim
    sudo tar -C /opt -xzf /tmp/nvim.tar.gz
    rm /tmp/nvim.tar.gz
    export PATH="$PATH:/opt/nvim-linux-x86_64/bin"
  fi
}

install_zig
install_sdkman
install_nvm
install_go
install_golangci_lint
install_nvim

echo
echo "=== Setup complete ==="
echo "You may need to restart your shell or source the new files."
