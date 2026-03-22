#!/bin/bash
# Auto-attach to a project-specific tmux session.
# Creates the session if it doesn't exist, otherwise attaches.
# Runs as the coder user so claude --dangerously-skip-permissions works.

SESSION_NAME="$(basename "$PWD")"

if [ "$(id -u)" = "0" ]; then
    exec gosu coder tmux new-session -A -s "$SESSION_NAME"
else
    exec tmux new-session -A -s "$SESSION_NAME"
fi
