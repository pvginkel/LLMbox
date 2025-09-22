#!/bin/sh

SCRIPT_DIR="$(dirname "$0")"

if "$1" = ""; then
    $SCRIPT_DIR/llmbox.sh /usr/bin/thunk.sh claude --dangerously-skip-permissions
else
    $SCRIPT_DIR/llmbox.sh $*
fi
