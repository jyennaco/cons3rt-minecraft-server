#!/bin/bash

# World name is always "world" for container servers per the mount point
worldName='world'

# Replace variables configured in Dockerfile
serverJar='REPLACE_SERVER_JAR'
worldDir="REPLACE_WORLDS_DIR/${worldName}"
scriptsDir='REPLACE_SCRIPTS_DIR'
serverVersion='REPLACE_VERSION'

# Configure the yennacraft.config.sh script
sed -i '/^SERVER_VERSION=.*/d' ${worldDir}/yennacraft.config.sh
echo "SERVER_VERSION=${serverVersion}" >> ${worldDir}/yennacraft.config.sh

# Change into the scripts directory
cd ${scriptsDir}

# Start the server
${scriptsDir}/start-server.sh "${worldName}"
if [ $? -ne 0 ]; then /bin/echo "Problem starting server for world: ${worldName}"; exit 1; fi

# Execute the provided command
#exec "$@"

# Keep the shell accessible for minecraft commands
/bin/bash
