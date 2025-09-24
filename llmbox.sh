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

docker compose run --pull=always --rm -w $CONTAINER_PATH llmbox $*
