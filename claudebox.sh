#!/bin/sh

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CALLER_PWD="$(pwd)"

if [ "${CALLER_PWD#"$PROJECT_DIR"}" != "$CALLER_PWD" ]; then
    REL="${CALLER_PWD#"$PROJECT_DIR"}"
    [ -z "$REL" ] && CONTAINER_PATH="/work" || CONTAINER_PATH="/work$REL"
else
    CONTAINER_PATH="/work"
fi

cd "$(dirname "$0")"

export UID=$(id -u) GID=$(id -g)

if [ "$1" = "build" ]; then
    docker compose build
elif [ "$1" = "rebuild" ]; then
    docker compose build --no-cache
elif [ "$1" != "" ]; then
    docker compose run --rm -w $CONTAINER_PATH claudebox $*
else
    docker compose run --rm -w $CONTAINER_PATH claudebox /usr/bin/thunk.sh claude --dangerously-skip-permissions
fi
