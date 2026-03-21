#!/bin/bash

docker exec -it claude-workspace bash -c "cd ${PROJECTS_DIR:-$HOME/projects} && exec bash"
