#!/bin/sh

SCRIPT_DIR="$(dirname "$0")"

if [ "$1" = "" ]; then
    $SCRIPT_DIR/llmbox.sh /usr/bin/thunk.sh codex --model gpt-5-codex
else
    $SCRIPT_DIR/llmbox.sh $*
fi
