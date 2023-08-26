#!/bin/bash
. /opt/Minecraft_Servers/scripts/common.sh
logTag="start-server"
world="${1}"
if [ -z "${world}" ]; then
    logInfo "No world provided, determining the world from config file: /opt/Minecraft_Servers/config.sh"
    world=$(/usr/bin/grep 'MINECRAFT_WORLD' /opt/Minecraft_Servers/config.sh | /usr/bin/awk -F= '{print $2}')
fi
logInfo "Launching world: ${world}"
start_minecraft_server "${world}"
exit $?
