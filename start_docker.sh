#!/bin/bash

# export CODE_SERVER_PASSWORD="" # TODO get from secrets folder locally!

# Projects folder — mounted into the container at the same absolute path
export PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"

sudo tailscale up

docker compose up -d --build
