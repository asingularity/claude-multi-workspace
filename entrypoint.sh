#!/bin/bash
set -e

# Pass through ANTHROPIC_API_KEY if set
if [ -n "$ANTHROPIC_API_KEY" ]; then
    export ANTHROPIC_API_KEY
fi

# Trust all mounted directories (host user owns them, container runs as root)
# Write to system-level config since ~/.gitconfig is mounted read-only from host
# git config --global --add safe.directory '*'
git config --system --add safe.directory '*'

# Symlink so `cd /workspace` still works as a convenience alias
ln -sfn "${PROJECTS_DIR}" /workspace 2>/dev/null || true

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

# Start code-server in the background
echo "Starting code-server on :8080 ..."
code-server ${PROJECTS_DIR} &

# Start a tmux session as fallback (for SSH access if you ever need it)
tmux new-session -d -s main -c ${PROJECTS_DIR} 2>/dev/null || true

echo "========================================"
echo "  code-server running on port 8080"
echo "  Open in browser to use VS Code"
echo "  Claude Code available in the terminal"
echo "========================================"

# Keep container alive
wait
