#!/bin/bash

if output="$(poetry env activate 2>/dev/null)"; then
    eval "$output"
fi

$*
