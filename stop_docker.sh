#!/bin/bash
# Stop and remove the workspace container. This ends every tmux/Claude session
# inside it. Volumes (VS Code state, code-server config) are kept.
cd "$(dirname "$0")"

export PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"

docker compose down
