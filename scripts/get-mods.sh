#!/bin/bash

# Source the environment
if [ -f /etc/bashrc ] ; then
    . /etc/bashrc
fi
if [ -f /etc/profile ] ; then
    . /etc/profile
fi

######################### GLOBAL VARIABLES #########################

minecraftServerDir='/opt/Minecraft_Servers'
modsDir="${minecraftServerDir}/mods"
configFile="${minecraftServerDir}/config.sh"

# Establish a log file and log tag
logTag="minecraft"
logFile="${logDir}/minecraft.log"

######################### GLOBAL VARIABLES #########################

logInfo "Attempting to sync mods from the S3 bucket..."

# Ensure the config file is found
if [ ! -f ${configFile} ]; then logErr "Config file not found: ${configFile}"; exit 1; fi

# Read the config file
. ${configFile}

# Ensure the S3_BUCKET_NAME variable was found
if [ -z "${S3_BUCKET_NAME}" ]; then logErr "The S3_BUCKET_NAME variable was not set in the config file: ${configFile}" ; exit 1; fi

# Ensure the mods directory exists
if [ ! -d ${modsDir} ]; then
    logInfo "Creating mods directory: ${modsDir}"
    mkdir -p ${modsDir}
fi

# Ensure the aws command is found
which aws
if [ $? -ne 0 ]; then logErr "aws command not found, please install the AWS CLI and then re-try"; exit 1; fi

# Run the aws s3 sync command to sync the mods directory with S3
logInfo "Syncing [s3://${S3_BUCKET_NAME}/mods] with: [${modsDir}]..."
aws s3 sync s3://${S3_BUCKET_NAME}/mods ${modsDir}
if [ $? -ne 0 ]; then logErr "Problem syncing the mods from S3 [s3://${S3_BUCKET_NAME}/mods] to: [${modsDir}]"; exit 1; fi

logInfo "Completed syncing up the mods directory: ${modsDir}"
logInfo "Next step, copy mods into your world mod directory"
exit 0
