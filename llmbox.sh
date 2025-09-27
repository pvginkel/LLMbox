#!/bin/sh

set -se

DIR=$(pwd)

while [ "$DIR" != "/" ]; do
    if [ -d "$DIR/.llmbox" ]; then
        break
    fi
    DIR=$(dirname "$DIR")
done

if [ "$DIR" = "/" ]; then
    echo "Cannot find .llmbox folder"
    exit 1
fi

COMPOSE_FILE="$DIR/.llmbox/docker-compose.yml"

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Expected .llmbox/docker-compose.yml file to exist"
    exit 1
fi

export UID=$(id -u) GID=$(id -g)

if [ "$(basename "$0")" = "claudebox" ]; then
    RUN="/usr/bin/thunk.sh claude --dangerously-skip-permissions"
elif [ "$(basename "$0")" = "codexbox" ]; then
    RUN="/usr/bin/thunk.sh codex --model gpt-5-codex --dangerously-bypass-approvals-and-sandbox"
else
    RUN=$*
fi

docker compose -f $COMPOSE_FILE --project-directory $DIR run --pull=always --rm llmbox $RUN
