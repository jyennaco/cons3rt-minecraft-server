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
configFile="${minecraftServerDir}/config.sh"
serverJarsDir="${minecraftServerDir}/server_jars"
worldsDir="${minecraftServerDir}/worlds"
modsDir="${minecraftServerDir}/mods"

######################### GLOBAL VARIABLES #########################

# Establish a log file and log tag
logTag="minecraft"
logDir="/var/log/minecraft"
logFile="${logDir}/minecraft-$(date "+%Y%m%d-%H%M%S").log"

# Logging functions
function timestamp() { date "+%F %T"; }
function logInfo() { echo -e "$(timestamp) ${logTag} [INFO]: ${1}" >> ${logFile}; echo -e "$(timestamp) ${logTag} [INFO]: ${1}"; }
function logWarn() { echo -e "$(timestamp) ${logTag} [WARN]: ${1}" >> ${logFile}; echo -e "$(timestamp) ${logTag} [WARN]: ${1}"; }
function logErr() { echo -e "$(timestamp) ${logTag} [ERROR]: ${1}" >> ${logFile}; echo -e "$(timestamp) ${logTag} [ERROR]: ${1}"; }

function accept_eula() {
    logTag="accept_eula"
    worldDir="${1}"
    serverJar="${2}"
    if [ -z "${worldDir}" ]; then logErr "World directory not provided"; return 1; fi
    if [ -z "${serverJar}" ]; then logErr "Server jar not provided"; return 1; fi
    if [ ! -d ${worldDir} ]; then logErr "World directory not found: ${worldDir}"; return 1; fi
    if [ ! -f ${serverJar} ]; then logErr "Server jar file not found: ${serverJar}"; return 1; fi
    if [ ! -f ${worldDir}/eula.txt ]; then
        logInfo "Running the Minecraft server jar ${serverJar} to accept the EULA in world directory: ${worldDir}"
        cd ${worldDir}
        timeout 20s java -Xmx1024M -Xms1024M -jar ${serverJar} nogui >> $logFile 2>&1
        if [ ! -f ${worldDir}/eula.txt ]; then logErr "${worldDir}/eula.txt not found"; return 1; fi
        cd -
    else
        logInfo "eula.txt file found, no need to re-generate..."
    fi
    sed -i "s|eula=false|eula=true|g" ${worldDir}/eula.txt
    logInfo "eula accepted for server jar ${serverJar} in world: ${worldDir}"
    return 0
}

function install_forge() {
    logTag="install_forge"
    javaExe='/usr/bin/java'
    worldDir="${1}"
    serverVersion="${2}"
    serverConfigFile="${worldDir}/server-version.sh"
    forgeInstallerFileName="${serverVersion}-installer.jar"
    forgeInstaller="${serverJarsDir}/${serverVersion}/${forgeInstallerFileName}"

    if [ ! -f ${forgeInstaller} ]; then logErr "Forge installer file not found: ${forgeInstaller}"; return 1; fi

    # Copy the forge installer
    logInfo "Copying forge installer [${forgeInstaller}] to world directory: ${worldDir}"
    cp -f ${forgeInstaller} ${worldDir}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem copying forge installer [${forgeInstaller}] to world directory: ${worldDir}"; return 1; fi

    # Determine the main minecraft version and find the server har
    minecraftVersion=$(echo "${serverVersion}" | awk -F - '{print $2}')
    if [ -z "${minecraftVersion}" ]; then logErr "Unable to determine the minecraft version from forge version: ${serverVersion}"; return 1; fi
    logInfo "Found minecraft version: ${minecraftVersion}"
    minecraftServerJar="${serverJarsDir}/${minecraftVersion}/server.jar"
    if [ ! -f ${minecraftServerJar} ]; then logErr "Minecraft world server jar not found: ${minecraftServerJar}"; return 1; fi

    # Copy the server jar to the work directory (forge likes everything together)
    logInfo "Copying minecraft server jar [${minecraftServerJar}] to world directory: ${worldDir}"
    cp -f ${minecraftServerJar} ${worldDir}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem copying minecraft server jar [${minecraftServerJar}] to world directory: ${worldDir}"; return 1; fi

    # Run the forge installer
    cd ${worldDir}/
    forgeInstallCmd="${javaExe} -jar ${forgeInstallerFileName} --installServer"
    logInfo "Running the forge install command: ${forgeInstallCmd}"
    ${forgeInstallCmd} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem installing forge"; return 1; fi
    logInfo "Completed forge install in: ${worldDir}"

    # Check for mods
    logInfo "Sourcing Minecraft world version file: ${serverConfigFile}"
    . ${serverConfigFile}
    if [ -z "${SERVER_MODS}" ]; then
        logInfo "SERVER_MODS variable not set, no mods to configure"
        return 0
    fi
    logInfo "Found SERVER_MODS variable to configure: ${SERVER_MODS}"
    serverModsArr=(${SERVER_MODS//,/ })

    # Ensure the mods dir exists for this version
    versionModsDir="${modsDir}/forge/${minecraftVersion}"
    if [ ! -d ${versionModsDir} ]; then logErr "Mods directory for this minecraft version not found: ${versionModsDir}"; return 1; fi
    logInfo "Checking for mods in: ${versionModsDir}"

    # Create the mods directory
    worldModsDir="${worldDir}/mods"
    logInfo "Creating mods directory: ${worldModsDir}"
    mkdir -p ${worldModsDir} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem creating mods directory: ${worldModsDir}"; return 1; fi

    # Configure mods
    for mod in "${serverModsArr[@]}"; do
        logInfo "Installing mod: ${mod}"

        # Get the mod file name
        modFileName=$(ls ${versionModsDir}/ | grep 'jar' | grep "${mod}")
        if [ -z "${modFileName}" ]; then logErr "Mod file [${mod}] not found in mods directory: ${versionModsDir}"; return 1; fi
        modFile="${versionModsDir}/${modFileName}"
        if [ ! -f "${modFile}" ]; then logErr "Mod file not found: ${modFile}"; return 1; fi

        # Copy the mod
        logInfo "Copying mod file [${modFile}] to world mod directory: ${worldModsDir}"
        cp -f ${modFile} ${worldModsDir}/ >> ${logFile} 2>&1
        if [ $? -ne 0 ]; then logErr "Problem copying mod file [${modFile}] to world mod directory: ${worldModsDir}"; return 1; fi
    done
    logInfo "Completed setting up mods!"
    return 0
}

function start_minecraft_server() {
    logTag="start_minecraft_server"
    javaExe='/usr/bin/java'
    screenExe='/usr/bin/screen'
    xmxConfig='-Xmx1024M'
    xmsConfig='-Xms1024M'
    worldName="${1}"
    worldDir="${worldsDir}/${worldName}"
    serverConfigFile="${worldDir}/server-version.sh"

    if [ -z "${worldName}" ]; then logErr "World name not provided"; return 1; fi
    if [ -z "${worldDir}" ]; then logErr "World directory not provided"; return 1; fi
    if [ ! -d ${worldDir} ]; then logErr "World directory not found: ${worldDir}"; return 1; fi
    if [ ! -e ${javaExe} ]; then logErr "${javaExe} not found"; return 1; fi
    if [ ! -e ${screenExe} ]; then logErr "${screenExe} not found"; return 1; fi
    if [ ! -f ${serverConfigFile} ]; then logErr "Minecraft world server version file not found: ${serverConfigFile}"; return 1; fi

    logInfo "Sourcing Minecraft world version file: ${serverConfigFile}"
    . ${serverConfigFile}

    if [ -z "${SERVER_VERSION}" ]; then logErr "SERVER_VERSION variable not set"; return 1; fi

    if [[ ${SERVER_VERSION} == "forge"* ]]; then
        logInfo "This is a forge server..."
        install_forge "${worldDir}" "${SERVER_VERSION}"
        forgeInstallRes=$?
        logTag="start_minecraft_server"
        if [ ${forgeInstallRes} -ne 0 ]; then logErr "Problem installing forge server"; return 1; fi
        serverJarFileName=$(ls ${worldDir}/ | grep 'forge' | grep 'jar' | grep -v 'installer')
        serverJar="${worldDir}/${serverJarFileName}"
    else
        serverJar="${serverJarsDir}/${SERVER_VERSION}/server.jar"
    fi

    if [ ! -f ${serverJar} ]; then logErr "Minecraft world server jar not found: ${serverJar}"; return 1; fi

    accept_eula "${worldDir}" "${serverJar}"
    logTag="start_minecraft_server"
    
    logInfo "Running minecraft world: ${worldDir}"
    cd ${worldDir}/
    minecraftCmd="${javaExe} ${xmxConfig} ${xmsConfig} -jar ${serverJar} nogui"
    screenName="minecraft_${worldName}"
    logInfo "Launching ${screenName} from screen with command: $minecraftCmd"
    ${screenExe} -dmS ${screenName} ${minecraftCmd}
    if [ $? -ne 0 ]; then logErr "Problem launching screen $screenName command: $minecraftCmd"; return 1; fi
    logInfo "Started minecraft background screen successfully: $screenName"
    return 0
}

function stop_all_minecraft_servers() {
    logTag="stop_all_minecraft_servers"
    logInfo "Will attempt to find and stop all running minecraft screen sessions..."

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

function stop_minecraft_server() {
    logTag="stop_minecraft_server"
    worldName="${1}"
    screenName="minecraft_${worldName}"

    if [ -z "${worldName}" ]; then logErr "World name not provided"; return 1; fi

    logInfo "Attempting to stop minecraft world: ${worldName}"

    minecraftScreenSession=$(screen -list | grep 'Detached' | grep "${screenName}")
    if [ -z "${minecraftScreenSession}" ]; then
        logInfo "Minecraft server not running: ${minecraftScreenSession}"
        return 0
    fi
    logInfo "Found running server: ${minecraftScreenSession}"
    logInfo "Quitting: ${screenName}..."
    screen -X -S ${screenName} quit
    if [ $? -ne 0 ]; then logErr "Problem quitting minecraft screen session: ${screenName}"; return 1; fi
    sleep 2
    logInfo "Quit from minecraft screen session: ${screenName}"
    return 0
}
