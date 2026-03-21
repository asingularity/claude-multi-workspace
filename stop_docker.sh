#!/bin/bash

export PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"
export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-/dev/null}"

docker compose down
