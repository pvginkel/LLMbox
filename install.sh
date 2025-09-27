#!/bin/sh

cd "$(dirname "$0")"

for name in claudebox codexbox; do
    ln -s "$(pwd)/llmbox.sh" $HOME/.local/bin/$name
done
