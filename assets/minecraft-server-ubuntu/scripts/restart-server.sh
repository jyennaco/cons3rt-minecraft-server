#!/bin/bash
. common.sh
logTag="restart-server"
world="${1}"
if [ -z "${world}" ]; then logErr "Please provide the world name to restart"; exit 1; fi
logInfo "Stopping world: ${world}"
stop_minecraft_server "${world}"
sleep 2
logInfo "Launching world: ${world}"
start_minecraft_server "${world}"
exit $?
