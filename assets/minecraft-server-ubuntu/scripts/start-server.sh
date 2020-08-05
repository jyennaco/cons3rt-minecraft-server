#!/bin/bash
. common.sh
logTag="start-server"
world="${1}"
if [ -z "${world}" ]; then logErr "Please provide the world name to start"; exit 1; fi
logInfo "Launching world: ${world}"
start_minecraft_server "${world}"
exit $?
