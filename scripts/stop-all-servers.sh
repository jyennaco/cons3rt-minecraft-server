#!/bin/bash
. common.sh
logTag="stop-all-servers"
logInfo "Stopping all minecraft servers"
stop_all_minecraft_servers
exit $?
