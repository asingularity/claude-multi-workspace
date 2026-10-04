#!/bin/bash
# Build (if needed) and start the workspace container.
#   ./start_docker.sh          # incremental (cached) build + up
#   ./start_docker.sh --fresh  # full rebuild without cache
#
# Secrets/config come from the environment or from a .env file next to this
# script (docker compose reads .env automatically; it is gitignored):
#   CODE_SERVER_PASSWORD="..."      # browser login password (default: changeme)
#   CLAUDE_CODE_OAUTH_TOKEN="..."   # recommended: long-lived token from `claude setup-token`
#   ANTHROPIC_API_KEY="sk-ant-..."  # optional alternative: API billing, bypasses subscription
#   PROJECTS_DIR=/path/to/projects  # default: $HOME/projects
# Changing any of these recreates the container (tmux sessions are lost), so
# keep them identical between runs.
cd "$(dirname "$0")"

# Projects folder - mounted into the container at the same absolute path
export PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"

# Fail fast on an unfilled .env before asking for sudo or passphrases.
if grep -qsE '^[A-Za-z_]+=.*CHANGE-ME' .env; then   # assignment lines only, not comments
    echo "ERROR: .env still contains CHANGE-ME placeholders - fill them in first (see .env.example)" >&2
    exit 1
fi
if [ -z "$CODE_SERVER_PASSWORD" ] && ! grep -qs '^CODE_SERVER_PASSWORD=' .env; then
    echo "WARNING: CODE_SERVER_PASSWORD is not set - the code-server password will be 'changeme'"
fi

sudo tailscale up

# Renew the Tailscale HTTPS cert when it is close to expiry (90-day Let's
# Encrypt certs; nothing else renews them). Non-fatal: the container still
# starts with the existing cert if this fails (offline, other Tailscale profile).
./renew_cert.sh || echo "WARNING: cert renewal failed - continuing with the existing cert"

# SSH agent for the container. A dedicated agent listens on a socket inside
# ~/.eeviac, and docker-compose.yml mounts that *directory* (not the socket):
# the directory exists at boot, so Docker's restart policy can bring the
# container back after a reboot even though no agent is running yet. Re-running
# this script after login (re)creates the socket in place and the container
# picks it up without a restart. Passphrases are asked for once per boot.
AGENT_DIR="$HOME/.eeviac"                 # must match the volume in docker-compose.yml
AGENT_SOCK="$AGENT_DIR/ssh-agent.sock"
mkdir -p "$AGENT_DIR"
if [ ! -w "$AGENT_DIR" ]; then
    echo "ERROR: $AGENT_DIR is not writable (created by Docker as root?). Fix: sudo chown $USER $AGENT_DIR" >&2
    exit 1
fi
SSH_AUTH_SOCK="$AGENT_SOCK" ssh-add -l >/dev/null 2>&1
if [ $? -eq 2 ]; then                      # 2 = nothing listening on the socket
    rm -f "$AGENT_SOCK"
    ssh-agent -a "$AGENT_SOCK" >/dev/null
fi
export SSH_AUTH_SOCK="$AGENT_SOCK"
ssh-add -l &>/dev/null || ssh-add

# Match container coder UID to host user so bind-mounted files are accessible
export HOST_UID="$(id -u)"

BUILD_FLAGS="--build"
if [ "$1" = "--fresh" ]; then
    echo "Full rebuild (no cache)..."
    docker compose build --no-cache
    BUILD_FLAGS=""
fi

docker compose up -d $BUILD_FLAGS
