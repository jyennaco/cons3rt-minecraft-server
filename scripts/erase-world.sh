#!/bin/bash
. /opt/Minecraft_Servers/scripts/common.sh
world="${1}"
logTag="erase-world"
logInfo "Erasing world: ${world}"
erase_world "${world}"
exit $?
