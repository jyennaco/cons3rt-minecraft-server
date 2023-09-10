#!/bin/bash
. /opt/Minecraft_Servers/scripts/common.sh
logTag="backup-minecraft-servers"
logInfo "Backing up minecraft servers"
backup_servers
exit $?
