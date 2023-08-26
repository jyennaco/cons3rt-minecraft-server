#!/bin/bash
. /opt/Minecraft_Servers/scripts/common.sh
world="${1}"
logTag="create-world"
logInfo "Creating world: ${world}"
create_new_world "${world}"
exit $?
