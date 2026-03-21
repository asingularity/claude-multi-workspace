#!/bin/bash
# Auto-attach to a project-specific tmux session.
# Creates the session if it doesn't exist, otherwise attaches.

SESSION_NAME="$(basename "$PWD")"

exec tmux new-session -A -s "$SESSION_NAME"
