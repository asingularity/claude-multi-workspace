#!/bin/bash
set -e

CODER_HOME="/home/coder"

# Pass through ANTHROPIC_API_KEY if set
if [ -n "$ANTHROPIC_API_KEY" ]; then
    export ANTHROPIC_API_KEY
fi

# Trust all mounted directories (host user owns them, container runs as root)
git config --system --add safe.directory '*'

# Copy SSH keys from staging mount and fix permissions for the coder user.
# -T copies the *contents* into .ssh even when .ssh already exists (container
# restart); plain -r would nest a second copy at .ssh/ssh-host/.
if [ -d /etc/ssh-host ]; then
    cp -rT /etc/ssh-host "$CODER_HOME/.ssh"
    chmod 700 "$CODER_HOME/.ssh"
    chmod 600 "$CODER_HOME/.ssh"/* 2>/dev/null || true
    [ -f "$CODER_HOME/.ssh/config" ] && chmod 600 "$CODER_HOME/.ssh/config"
    chmod 644 "$CODER_HOME/.ssh"/*.pub 2>/dev/null || true
    chown -R coder:coder "$CODER_HOME/.ssh"
fi

# Allow coder to traverse /root so symlinks into it work
chmod 711 /root

# Link host gitconfig for the coder user
ln -sf /root/.gitconfig "$CODER_HOME/.gitconfig" 2>/dev/null || true

# Link Claude config for the coder user
ln -sfn /root/.claude "$CODER_HOME/.claude" 2>/dev/null || true
ln -sf /root/.claude.json "$CODER_HOME/.claude.json" 2>/dev/null || true

# Symlink so `cd /workspace` still works as a convenience alias. The Dockerfile's
# WORKDIR created /workspace as a real (empty) directory; drop it first, or the
# link would land inside it as /workspace/<basename>.
[ -d /workspace ] && [ ! -L /workspace ] && rmdir /workspace 2>/dev/null || true
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
PORT=$(sed -nE 's/^bind-addr:.*:([0-9]+)[[:space:]]*$/\1/p' "$CONFIG")

# Print the cert's expiry; warn loudly if it has already expired.
report_cert_expiry() {
    local end
    end=$(openssl x509 -in "$CERT_FILE" -noout -enddate 2>/dev/null | cut -d= -f2)
    [ -n "$end" ] || return 0
    if openssl x509 -in "$CERT_FILE" -noout -checkend 0 >/dev/null 2>&1; then
        echo "TLS cert valid until: $end"
    else
        echo "WARNING: TLS cert EXPIRED on $end - browsers will warn or refuse to connect."
        echo "         On the host run ./renew_cert.sh; code-server restarts by itself."
    fi
}

# Auto-detect Tailscale TLS certs if mounted (first *.crt with a matching .key)
CERT_DIR="/etc/tailscale/certs"
CERT_FILE=$(ls "$CERT_DIR"/*.crt 2>/dev/null | head -1)
KEY_FILE=""
if [ -n "$CERT_FILE" ] && [ -f "${CERT_FILE%.crt}.key" ]; then
    KEY_FILE="${CERT_FILE%.crt}.key"
    sed -i "s|^cert:.*|cert: $CERT_FILE|" "$CONFIG"
    sed -i "s|^cert-key:.*|cert-key: $KEY_FILE|" "$CONFIG"
    echo "TLS enabled: $(basename "$CERT_FILE")"
    report_cert_expiry
    SCHEME=https
else
    CERT_FILE=""
    echo "No Tailscale cert+key pair found in $CERT_DIR - running HTTP"
    SCHEME=http
fi

# --- code-server supervisor ---------------------------------------------------
# code-server reads the TLS cert only at startup, and the host renews the cert
# in place (renew_cert.sh, weekly cron). Watch the cert+key and restart
# code-server when they change. Only code-server restarts: the tmux server (and
# any Claude session inside it) is not a child of code-server, so terminals
# simply reattach to their sessions after the browser reloads.
cert_fingerprint() {
    [ -n "$CERT_FILE" ] || return 0
    cat "$CERT_FILE" "$KEY_FILE" 2>/dev/null | md5sum | cut -c1-32
}

supervise_code_server() {
    set +e
    local pid seen now pending
    while true; do
        code-server "${PROJECTS_DIR}" &
        pid=$!
        seen=$(cert_fingerprint); pending=""
        while sleep 30; kill -0 "$pid" 2>/dev/null; do
            now=$(cert_fingerprint)
            if [ -n "$now" ] && [ "$now" != "$seen" ]; then
                # Renewal writes .crt and .key separately: wait until the new
                # contents are stable for two ticks before restarting.
                if [ "$now" = "$pending" ]; then
                    echo "TLS cert changed on disk - restarting code-server (tmux sessions are unaffected)"
                    kill "$pid"
                    break
                fi
                pending=$now
            else
                pending=""
            fi
        done
        wait "$pid" 2>/dev/null
        echo "code-server stopped (exit $?) - restarting in 2s"
        sleep 2
    done
}

# On `docker stop`, forward SIGTERM to everything so code-server and tmux shut
# down cleanly instead of waiting for Docker's SIGKILL.
trap 'echo "Shutting down..."; kill -TERM -- -1 2>/dev/null; wait; exit 0' TERM INT

echo "Starting code-server on :${PORT} ..."
supervise_code_server &

# Start a tmux session as fallback (for SSH access if you ever need it)
tmux new-session -d -s main -c ${PROJECTS_DIR} 2>/dev/null || true

echo "========================================"
echo "  code-server: ${SCHEME}://<tailscale-hostname>:${PORT}"
echo "  Open in browser to use VS Code"
echo "  Claude Code available in the terminal"
echo "  Run claude as: gosu coder claude"
echo "========================================"

# Keep container alive (the supervisor never exits on its own)
wait
