#!/bin/bash
. common.sh
logTag="backup-minecraft-servers"
logInfo "Backing up minecraft servers"
backup_servers
exit $?
