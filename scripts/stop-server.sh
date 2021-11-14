#!/bin/bash
. common.sh
logTag="stop-server"
world="${1}"
if [ -z "${world}" ]; then logErr "Please provide the world name to stop"; exit 1; fi
logInfo "Stopping world: ${world}"
stop_minecraft_server "${world}"
exit $?
