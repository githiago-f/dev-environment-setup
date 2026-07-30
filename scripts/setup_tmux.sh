#!/usr/bin/env bash
set -euo pipefail

echo "=== Configuring tmux ==="
TMUX_DIR="$HOME/.config/tmux"
TMUX_CONF="$TMUX_DIR/tmux.conf"
mkdir -p "$TMUX_DIR"

if [ -f "$TMUX_CONF" ]; then
  echo "$TMUX_CONF already exists, backing up to ${TMUX_CONF}.bak"
  cp "$TMUX_CONF" "${TMUX_CONF}.bak"
fi

cat > "$TMUX_CONF" << 'TMUX_EOF'
# Base settings
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"
set -g update-environment "DISPLAY WAYLAND_DISPLAY SSH_AUTH_SOCK KITTY_PID KITTY_WINDOW_ID"
set -g mouse on
set -g history-limit 50000
set -g escape-time 10
set -g base-index 1
setw -g pane-base-index 1

# Splitting panes
bind | split-window -h
bind - split-window -v

# Reload config
bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"

# Vi-style copy mode
setw -g mode-keys vi
bind-key -T copy-mode-vi v send-keys -X begin-selection
bind-key -T copy-mode-vi y send-keys -X copy-selection
bind-key -T copy-mode-vi r send-keys -X rectangle-toggle

# Status bar
set -g status-interval 5
set -g status-style bg=colour235,fg=white
set -g status-left '#[fg=white,bg=colour235] #S '
set -g status-right '#[fg=brightgrey,bg=colour235] %Y-%m-%d %H:%M '
TMUX_EOF
echo "Wrote $TMUX_CONF"

echo
echo "=== Configuring kitty ==="
KITTY_CONF="$HOME/.config/kitty/kitty.conf"
mkdir -p "$(dirname "$KITTY_CONF")"

if grep -qF "confirm_os_window_close" "$KITTY_CONF" 2>/dev/null; then
  echo "Kitty confirm_os_window_close already set in $KITTY_CONF"
else
  printf '\nconfirm_os_window_close 0\n' >> "$KITTY_CONF"
  echo "Added confirm_os_window_close 0 to $KITTY_CONF"
fi

echo
echo "=== Registering tmux auto-start in bashrc ==="
RC_FILE="$HOME/.bashrc"

TMUX_MARKER_START="# >>> tmux >>>"
TMUX_MARKER_END="# <<< tmux <<<"

TMUX_BLOCK=$(cat << 'BLOCK_EOF'
# >>> tmux >>>
if command -v tmux >/dev/null 2>&1 && [ -z "$TMUX" ]; then
    tmux attach-session -t main || tmux new-session -s main
fi
# <<< tmux <<<
BLOCK_EOF
)

if grep -qF "$TMUX_MARKER_START" "$RC_FILE" 2>/dev/null; then
  echo "Tmux auto-start already registered in $RC_FILE"
else
  if grep -qF "tmux attach-session -t main" "$RC_FILE" 2>/dev/null; then
    echo "Note: existing tmux block found without markers. Appending managed block."
    echo "      You can remove the old block manually."
  fi
  printf '\n%s\n' "$TMUX_BLOCK" >> "$RC_FILE"
  echo "Added tmux auto-start to $RC_FILE"
fi

echo
echo "=== Tmux setup complete ==="
