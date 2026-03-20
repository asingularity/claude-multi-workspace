#!/bin/bash
set -e

# Pass through ANTHROPIC_API_KEY if set
if [ -n "$ANTHROPIC_API_KEY" ]; then
    export ANTHROPIC_API_KEY
fi

# Symlink so `cd /workspace` still works as a convenience alias
ln -sfn /home/csaba/projects /workspace 2>/dev/null || true

# Auto-detect Tailscale TLS certs if mounted
CERT_DIR="/etc/tailscale/certs"
CERT_FILE=$(ls "$CERT_DIR"/*.crt 2>/dev/null | head -1)
if [ -n "$CERT_FILE" ]; then
    KEY_FILE="${CERT_FILE%.crt}.key"
    if [ -f "$KEY_FILE" ]; then
        CONFIG="/root/.config/code-server/config.yaml"
        sed -i "s|^cert:.*|cert: $CERT_FILE|" "$CONFIG"
        sed -i "s|^cert-key:.*|cert-key: $KEY_FILE|" "$CONFIG"
        echo "TLS enabled: $(basename "$CERT_FILE")"
    fi
else
    echo "No Tailscale certs found — running HTTP"
fi

# Start code-server in the background
echo "Starting code-server on :8080 ..."
code-server /home/csaba/projects &

# Start a tmux session as fallback (for SSH access if you ever need it)
tmux new-session -d -s main -c /home/csaba/projects 2>/dev/null || true

echo "========================================"
echo "  code-server running on port 8080"
echo "  Open in browser to use VS Code"
echo "  Claude Code available in the terminal"
echo "========================================"

# Keep container alive
wait
