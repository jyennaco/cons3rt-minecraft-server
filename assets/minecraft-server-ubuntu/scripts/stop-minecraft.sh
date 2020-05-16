#!/bin/bash

# Source the environment
if [ -f /etc/bashrc ] ; then
    . /etc/bashrc
fi
if [ -f /etc/profile ] ; then
    . /etc/profile
fi

# Establish a log file and log tag
logTag="stop-minecraft"
logDir="/var/log/minecraft"
logFile="${logDir}/${logTag}-$(date "+%Y%m%d-%H%M%S").log"

######################### GLOBAL VARIABLES #########################

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
    logInfo "Will attempt to find and stop running minecraft screen sessions..."

    minecraftScreens=( $(screen -list | grep 'minecraft' | grep 'Detached' | awk -F . '{print $2}' | awk '{print $1}') )
    minecraftScreensStr="${minecraftScreens[@]}}"

    if [ ${#minecraftScreens[@]} -lt 1 ]; then
        logInfo "No minecraft screen sessions found, nothing to quit"
        return 0
    fi
    logInfo "Found running minecraft screens: ${minecraftScreensStr}"

    for minecraftScreenSession in "${minecraftScreens[@]}"; do
        logInfo "Attempting to quit minecraft session: ${minecraftScreenSession}"
        screen -X -S ${minecraftScreenSession} quit
        if [ $? -ne 0 ]; then logErr "Problem quitting minecraft screen session: ${minecraftScreenSession}"; return 1; fi
        sleep 2
        logInfo "Quit from minecraft screen session: $minecraftScreenSession"
    done
    logInfo "Successfully quit from all of the minecraft screen sessions!"
    return 0
}

function main() {
    logInfo "Starting script: ${logTag}"
    stop_minecraft_screen_sessions
    if [ $? -ne 0 ]; then logErr "Problem stopping minecraft screen sessions"; return 1; fi
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
