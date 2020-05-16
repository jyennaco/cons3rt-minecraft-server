#!/bin/bash

# Source the environment
if [ -f /etc/bashrc ] ; then
    . /etc/bashrc
fi
if [ -f /etc/profile ] ; then
    . /etc/profile
fi

# Establish a log file and log tag
logTag="update-minecraft-server"
logDir="/var/log/minecraft"
logFile="${logDir}/${logTag}-$(date "+%Y%m%d-%H%M%S").log"

######################### GLOBAL VARIABLES #########################

# Minecraft directories
minecraftServerDir="/opt/Minecraft_Servers"
serverJarsDir="${minecraftServerDir}/server_jars"

# Minecraft server download URL and version
#serverVersion='20w16a'
#downloadUrl="https://launcher.mojang.com/v1/objects/754bbd654d8e6bd90cd7a1464a9e68a0624505dd/server.jar"
#serverVersion='20w17a'
#downloadUrl="https://launcher.mojang.com/v1/objects/0b7e36b084577fb26148c6341d590ac14606db21/server.jar"
#serverVersion='20w19a'
#downloadUrl="https://launcher.mojang.com/v1/objects/fbb3ad3e7b25e78723434434077995855141ff07/server.jar"
serverVersion='20w20b'
downloadUrl="https://launcher.mojang.com/v1/objects/0393774fb1f9db8288a56dbbcf45022b71f7939f/server.jar"

# Server jar location
serverJarDir="${serverJarsDir}/${serverVersion}"
serverJar="${serverJarDir}/server.jar"

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

function create_directories() {
    if [ ! -d ${serverJarDir} ]; then
        logInfo "Creating directory: $serverJarDir"
        mkdir -p ${serverJarDir} >> $logFile 2>&1
    fi
}

function download_minecraft_server() {
    logInfo "Downloading the minecraft server jar version: $serverVersion"

    cd ${serverJarDir} >> $logFile 2>&1
    if [ -f server.jar ]; then
        logInfo "Removing existing server.jar file"
        rm -f server.jar  >> $logFile 2>&1
    fi
    logInfo "Downloading minecraft server using download URL: $downloadUrl"
    curl -O $downloadUrl >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem downloading minecraft server from $downloadUrl"; return 1; fi
    if [ ! -f server.jar ]; then logErr "server.jar file not found"; return 1; fi
    cd -
    logInfo "Minecraft server download complete: ${serverJar}"
    return 0
}

function update_latest() {
    logInfo "Updating the latest..."
    if [ -e ${serverJarsDir}/latest ]; then
        logInfo "Removing existing link: $serverJarsDir/latest"
        rm -f $serverJarsDir/latest >> $logFile 2>&1
    fi
    logInfo "Adding link $serverJarDir to: $serverJarsDir/latest"
    ln -sf $serverJarDir $serverJarsDir/latest >> $logFile 2>&1
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
    create_directories
    download_minecraft_server
    if [ $? -ne 0 ]; then logErr "Problem downloading minecraft server"; return 2; fi
    update_latest
    if [ $? -ne 0 ]; then logErr "Problem updating the latest"; return 3; fi
    start_minecraft_screen_sessions
    if [ $? -ne 0 ]; then logErr "Problem starting the minecraft server"; return 4; fi
    logInfo "Successfully completed: ${logTag}"
    logInfo "GO PLAY SOME MINECRAFT!!!!"
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
