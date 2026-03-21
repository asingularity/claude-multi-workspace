#!/bin/bash
# Auto-attach to a project-specific tmux session.
# Multiple terminals share the session but get independent views.

SESSION_NAME="$(basename "$PWD")"

if tmux has-session -t "=$SESSION_NAME" 2>/dev/null; then
    # Session exists — create a linked session for an independent view
    exec tmux new-session -t "=$SESSION_NAME" \; set-option destroy-unattached on
else
    # First terminal — create the session
    exec tmux new-session -s "$SESSION_NAME"
fi
