#!/bin/bash

# export CODE_SERVER_PASSWORD="" # TODO get from secrets folder locally!

# Projects folder — mounted into the container at the same absolute path
export PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"

sudo tailscale up

# Ensure SSH agent is running and key is loaded (needed for passphrase-protected keys)
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
fi
ssh-add -l &>/dev/null || ssh-add

export SSH_AUTH_SOCK

docker compose up -d --build
