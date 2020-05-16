#!/bin/bash

# Source the environment
if [ -f /etc/bashrc ] ; then
    . /etc/bashrc
fi
if [ -f /etc/profile ] ; then
    . /etc/profile
fi

# Establish a log file and log tag
logTag="run-minecraft"
logDir="/var/log/minecraft"
logFile="${logDir}/${logTag}-$(date "+%Y%m%d-%H%M%S").log"

######################### GLOBAL VARIABLES #########################

minecraftServerDir='REPLACE_MINECRAFT_SERVER_DIR'
configFile="${minecraftServerDir}/config.sh"
serverJarsDir="${minecraftServerDir}/server_jars"
javaExe='/usr/bin/java'
screenExe='/usr/bin/screen'
xmxConfig='-Xmx1024M'
xmsConfig='-Xms1024M'
minecraftWorldDir=
minecraftWorldServerJar=

####################### END GLOBAL VARIABLES #######################

# Logging functions
function timestamp() { /bin/date "+%F %T"; }
function logInfo() { /bin/echo -e "$(timestamp) ${logTag} [INFO]: ${1}" >> ${logFile}; /bin/echo -e "$(timestamp) ${logTag} [INFO]: ${1}"; }
function logWarn() { /bin/echo -e "$(timestamp) ${logTag} [WARN]: ${1}" >> ${logFile}; /bin/echo -e "$(timestamp) ${logTag} [WARN]: ${1}"; }
function logErr() { /bin/echo -e "$(timestamp) ${logTag} [ERROR]: ${1}" >> ${logFile}; /bin/echo -e "$(timestamp) ${logTag} [ERROR]: ${1}"; }

function verify_prerequisites() {
    logInfo "Verifying prerequisites..."
    if [ ! -d ${minecraftServerDir} ]; then logErr "Directory not found: ${minecraftServerDir}"; return 1; fi
    if [ ! -f ${configFile} ]; then logErr "Config file not found: ${configFile}"; return 1; fi
    if [ ! -e ${javaExe} ]; then logErr "$javaExe not found"; return 1; fi
    if [ ! -e ${screenExe} ]; then logErr "$screenExe not found"; return 1; fi
    logInfo "Sourcing config file: $configFile"
    . ${configFile}
    if [ -z "${MINECRAFT_WORLD}" ]; then logErr "MINECRAFT_WORLD variable not set"; return 1; fi
    minecraftWorldDir="${minecraftServerDir}/worlds/${MINECRAFT_WORLD}"
    if [ ! -d ${minecraftWorldDir} ]; then logErr "Minecraft world directory not found: ${minecraftWorldDir}"; return 1; fi
    minecraftWorldServerVersionFile="${minecraftWorldDir}/server-version.sh"
    if [ ! -f ${minecraftWorldServerVersionFile} ]; then logErr "Minecraft world server version file not found: ${minecraftWorldServerVersionFile}"; return 1; fi
    logInfo "Sourcing Minecraft world version file: $minecraftWorldServerVersionFile"
    . ${minecraftWorldServerVersionFile}
    if [ -z "${SERVER_VERSION}" ]; then logErr "SERVER_VERSION variable not set"; return 1; fi
    minecraftWorldServerJar="${serverJarsDir}/${SERVER_VERSION}/server.jar"
    if [ ! -f ${minecraftWorldServerJar} ]; then logErr "Minecraft world server jar not found: ${minecraftWorldServerJar}"; return 1; fi
    return 0
}

function run_minecraft() {
    logInfo "Running minecraft world: $minecraftWorldDir"
    cd ${minecraftWorldDir}
    minecraftCmd="${javaExe} ${xmxConfig} ${xmsConfig} -jar ${minecraftWorldServerJar} nogui"
    screenName="minecraft_${MINECRAFT_WORLD}"
    logInfo "Launching ${screenName} from screen with command: $minecraftCmd"
    ${screenExe} -dmS ${screenName} ${minecraftCmd}
    result=$?
    if [ $? -ne 0 ]; then logErr "Problem launching screen $screenName command: $minecraftCmd"; return 1; fi
    logInfo "Starting successfully: $screenName"
    return 0
}

function main() {
    logInfo "Starting script: ${logTag}"
    verify_prerequisites
    if [ $? -ne 0 ]; then logErr "Problem verifying prerequisites"; return 1; fi
    run_minecraft
    if [ $? -ne 0 ]; then logErr "Problem running Minecraft"; return 2; fi
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
cat ${logFile}
exit ${result}
