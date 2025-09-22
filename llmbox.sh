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
else
    # Check if container is more than 1 day old and rebuild if needed
    CONTAINER_AGE=$(docker inspect -f '{{.Created}}' llmbox-llmbox:latest 2>/dev/null | xargs -I{} date -d {} +%s 2>/dev/null)
    CURRENT_TIME=$(date +%s)
    if [ -n "$CONTAINER_AGE" ]; then
        AGE_DIFF=$((CURRENT_TIME - CONTAINER_AGE))
        if [ $AGE_DIFF -gt 86400 ]; then
            cat <<EOF
  ____  _____ ____  _   _ ___ _     ____ ___ _   _  ____
 |  _ \| ____| __ )| | | |_ _| |   |  _ \_ _| \ | |/ ___|
 | |_) |  _| |  _ \| | | || || |   | | | | ||  \| | |  _
 |  _ <| |___| |_) | |_| || || |___| |_| | || |\  | |_| |_ _ _
 |_| \_\_____|____/ \___/|___|_____|____/___|_| \_|\____(_|_|_)

EOF

            docker compose build --no-cache
        fi
    fi

    docker compose run --rm -w $CONTAINER_PATH llmbox $*
fi
