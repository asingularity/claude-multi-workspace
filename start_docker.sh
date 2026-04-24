#!/bin/bash

# export CODE_SERVER_PASSWORD="your-password-here"
# export ANTHROPIC_API_KEY="sk-ant-..."  # optional: API key auth (pay-per-use, bypasses subscription)
# export CLAUDE_CODE_OAUTH_TOKEN="..."      # recommended: long-lived subscription token (run `claude setup-token` to generate)

# Projects folder — mounted into the container at the same absolute path
export PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"

sudo tailscale up

# Ensure SSH agent is running and key is loaded (needed for passphrase-protected keys)
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
fi
ssh-add -l &>/dev/null || ssh-add

export SSH_AUTH_SOCK

# Match container coder UID to host user so bind-mounted files are accessible
export HOST_UID="$(id -u)"

BUILD_FLAGS="--build"
if [ "$1" = "--fresh" ]; then
    echo "Full rebuild (no cache)..."
    docker compose build --no-cache
    BUILD_FLAGS=""
fi

docker compose up -d $BUILD_FLAGS
