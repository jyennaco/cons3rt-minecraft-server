#!/bin/bash

# Source the environment
if [ -f /etc/bashrc ] ; then
    . /etc/bashrc
fi
if [ -f /etc/profile ] ; then
    . /etc/profile
fi

# Establish a log file and log tag
logTag="restart-minecraft"
logDir="/var/log/minecraft"
logFile="${logDir}/${logTag}-$(date "+%Y%m%d-%H%M%S").log"

######################### GLOBAL VARIABLES #########################

# Stop minecraft script
stopScript='/usr/local/bin/stop-minecraft.sh'

# Run minecraft script
runScript='/usr/local/bin/run-minecraft.sh'

####################### END GLOBAL VARIABLES #######################

# Logging functions
function timestamp() { date "+%F %T"; }
function logInfo() { echo -e "$(timestamp) ${logTag} [INFO]: ${1}" >> ${logFile}; echo -e "$(timestamp) ${logTag} [INFO]: ${1}"; }
function logWarn() { echo -e "$(timestamp) ${logTag} [WARN]: ${1}" >> ${logFile}; echo -e "$(timestamp) ${logTag} [WARN]: ${1}"; }
function logErr() { echo -e "$(timestamp) ${logTag} [ERROR]: ${1}" >> ${logFile}; echo -e "$(timestamp) ${logTag} [ERROR]: ${1}"; }

function stop_minecaft() {
    logInfo "Stopping minecraft server..."
    systemctl stop minecraft.service >> $logFile 2>&1
    return $?
}

function stop_minecraft_screen_sessions() {
    if [ ! -f ${stopScript} ]; then logErr "Script to stop the sessions not found: $stopScript"; return 1; fi
    logInfo "Running script to stop minecraft server sessions: $stopScript"
    ${stopScript}
    return $?
}

function start_minecaft() {
    logInfo "Starting minecraft server..."
    sleep 5
    systemctl start minecraft.service >> $logFile 2>&1
    return $?
}

function start_minecraft_screen_sessions() {
    if [ ! -f ${runScript} ]; then logErr "Script to start the server not found: $runScript"; return 1; fi
    logInfo "Restarting the minecraft server with screen in 5 seconds..."
    sleep 5
    ${runScript}
    return $?
}

function main() {
    logInfo "Starting script: ${logTag}"
    stop_minecraft_screen_sessions
    if [ $? -ne 0 ]; then logErr "Problem stopping minecraft screen sessions"; return 1; fi
    start_minecraft_screen_sessions
    if [ $? -ne 0 ]; then logErr "Problem starting the minecraft server"; return 2; fi
    logInfo "Successfully completed: ${logTag}"
    return 0
}

# Set up the log file
mkdir -p ${logDir}
chmod 700 ${logDir}
touch ${logFile}
chmod 644 ${logFile}

main
result=$?
logInfo "Exiting with code ${result} ..."
exit ${result}
