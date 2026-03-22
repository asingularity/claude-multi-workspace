#!/bin/bash
set -e

CODER_HOME="/home/coder"

# Pass through ANTHROPIC_API_KEY if set
if [ -n "$ANTHROPIC_API_KEY" ]; then
    export ANTHROPIC_API_KEY
fi

# Trust all mounted directories (host user owns them, container runs as root)
git config --system --add safe.directory '*'

# Copy SSH keys from staging mount and fix permissions for the coder user
if [ -d /etc/ssh-host ]; then
    cp -r /etc/ssh-host "$CODER_HOME/.ssh"
    chmod 700 "$CODER_HOME/.ssh"
    chmod 600 "$CODER_HOME/.ssh"/* 2>/dev/null || true
    [ -f "$CODER_HOME/.ssh/config" ] && chmod 600 "$CODER_HOME/.ssh/config"
    chmod 644 "$CODER_HOME/.ssh"/*.pub 2>/dev/null || true
    chown -R coder:coder "$CODER_HOME/.ssh"
fi

# Link host gitconfig for the coder user
ln -sf /root/.gitconfig "$CODER_HOME/.gitconfig" 2>/dev/null || true

# Link Claude config for the coder user
ln -sfn /root/.claude "$CODER_HOME/.claude" 2>/dev/null || true
ln -sf /root/.claude.json "$CODER_HOME/.claude.json" 2>/dev/null || true

# Symlink so `cd /workspace` still works as a convenience alias
ln -sfn "${PROJECTS_DIR}" /workspace 2>/dev/null || true

# Set code-server default terminal to tmux-shell (auto-attaches to project sessions)
SETTINGS_DIR="/root/.local/share/code-server/User"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi
# Merge tmux-shell as default terminal profile (preserves existing settings)
python3 -c "
import json, sys
f = '$SETTINGS_FILE'
with open(f) as fh: s = json.load(fh)
s['terminal.integrated.defaultProfile.linux'] = 'tmux'
s.setdefault('terminal.integrated.profiles.linux', {})['tmux'] = {'path': '/usr/local/bin/tmux-shell'}
with open(f, 'w') as fh: json.dump(s, fh, indent=2)
"

# Always write code-server config from template (ensures it stays in sync)
CONFIG="/root/.config/code-server/config.yaml"
mkdir -p /root/.config/code-server
cp /etc/code-server-config.yaml "$CONFIG"

# Auto-detect Tailscale TLS certs if mounted
CERT_DIR="/etc/tailscale/certs"
CERT_FILE=$(ls "$CERT_DIR"/*.crt 2>/dev/null | head -1)
if [ -n "$CERT_FILE" ]; then
    KEY_FILE="${CERT_FILE%.crt}.key"
    if [ -f "$KEY_FILE" ]; then
        sed -i "s|^cert:.*|cert: $CERT_FILE|" "$CONFIG"
        sed -i "s|^cert-key:.*|cert-key: $KEY_FILE|" "$CONFIG"
        echo "TLS enabled: $(basename "$CERT_FILE")"
    fi
else
    echo "No Tailscale certs found — running HTTP"
fi

# Start code-server in the background (runs as root — it needs access to volumes)
echo "Starting code-server on :8080 ..."
code-server ${PROJECTS_DIR} &

# Start a tmux session as fallback (for SSH access if you ever need it)
tmux new-session -d -s main -c ${PROJECTS_DIR} 2>/dev/null || true

echo "========================================"
echo "  code-server running on port 8080"
echo "  Open in browser to use VS Code"
echo "  Claude Code available in the terminal"
echo "  Run claude as: gosu coder claude"
echo "========================================"

# Keep container alive
wait
