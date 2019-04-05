#!/usr/bin/env bash

#DEPENDENCIES=(
#  sshfs
#  mkdir
#  docker-compose
#)
#
#for util in "${DEPENDENCIES[@]}"
#do
#    hash "${util}" &>/dev/null || log "'${util}' is not found on this system" || exit 1
#done;

if [ ! -d "$CONTAINERS_DIR_PATH" ]; then
    log "Create $CONTAINERS_DIR_PATH";
    mkdir -p "$CONTAINERS_DIR_PATH"
fi
