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
serverJarsDir="${minecraftServerDir}/server_jars"
configFile="${minecraftServerDir}/config.sh"

# Establish a log file and log tag
logTag="minecraft"
logFile="${logDir}/minecraft.log"

######################### GLOBAL VARIABLES #########################

logInfo "Attempting to sync server jars to the S3 bucket..."

# Ensure the config file is found
if [ ! -f ${configFile} ]; then logErr "Config file not found: ${configFile}"; exit 1; fi

# Read the config file
. ${configFile}

# Ensure the S3_BUCKET_NAME variable was found
if [ -z "${S3_BUCKET_NAME}" ]; then logErr "The S3_BUCKET_NAME variable was not set in the config file: ${configFile}" ; exit 1; fi

# Ensure the server jars directory exists
if [ ! -d ${serverJarsDir} ]; then
    logErr "No server jars directory to sync: ${serverJarsDir}"
    exit 1
fi

# Ensure the aws command is found
which aws
if [ $? -ne 0 ]; then logErr "aws command not found, please install the AWS CLI and then re-try"; exit 1; fi

# Run the aws s3 sync command to sync the server jars directory with S3
logInfo "Syncing [serverJarsDir] with: [s3://${S3_BUCKET_NAME}/server_jars]..."
aws s3 sync ${serverJarsDir} s3://${S3_BUCKET_NAME}/server_jars
if [ $? -ne 0 ]; then logErr "Problem syncing the server jars from [${serverJarsDir}] to: [s3://${S3_BUCKET_NAME}/server_jars]"; exit 1; fi

logInfo "Completed syncing up the server_jars directory: ${serverJarsDir}"
exit 0
