#!/bin/bash

# Source the environment
if [ -f /etc/bashrc ] ; then
    . /etc/bashrc
fi
if [ -f /etc/profile ] ; then
    . /etc/profile
fi
if [ -f /usr/local/bashcons3rt/bash_cons3rt.sh ] ; then
    . /usr/local/bashcons3rt/bash_cons3rt.sh
fi

######################### GLOBAL VARIABLES #########################

minecraftServerDir='/opt/Minecraft_Servers'
configFile="${minecraftServerDir}/config.sh"
serverJarsDir="${minecraftServerDir}/server_jars"
worldsDir="${minecraftServerDir}/worlds"
modsDir="${minecraftServerDir}/mods"
modPacksDir="${minecraftServerDir}/modpacks"
backupDir="${minecraftServerDir}/backups"
scriptsDir="${minecraftServerDir}/scripts"
logDir="${minecraftServerDir}/log"
versionsFile="${scriptsDir}/server-versions.sh"
serverLockFile="${minecraftServerDir}/minecraft.lck"
awsCmd="/usr/local/bin/aws"
slackCmd="/home/minecraft/venv/bin/slack"
javaExe='/opt/java/jre/bin/java'
java8Exe='/opt/java/jre8/bin/java'
java11Exe='/opt/java/jre11/bin/java'
java17Exe='/opt/java/jre17/bin/java'
screenExe='/usr/bin/screen'
xmxConfig='-Xmx1024M'
xmsConfig='-Xms1024M'
serverJava=
minecraftScreenSession=
. ${configFile}
. ${versionsFile}

######################### GLOBAL VARIABLES #########################

# Establish a log file and log tag
logTag="minecraft"
logFile="${logDir}/minecraft.log"

# Logging functions
function timestamp() { /bin/date "+%F %T"; }
function timestamp_formatted() { /bin/date "+%F_%H%M%S"; }
function logInfo() { /bin/echo -e "$(timestamp) ${logTag} [INFO]: ${1}" >> ${logFile}; /bin/echo -e "$(timestamp) ${logTag} [INFO]: ${1}"; }
function logWarn() { /bin/echo -e "$(timestamp) ${logTag} [WARN]: ${1}" >> ${logFile}; /bin/echo -e "$(timestamp) ${logTag} [WARN]: ${1}"; }
function logErr() { /bin/echo -e "$(timestamp) ${logTag} [ERROR]: ${1}" >> ${logFile}; /bin/echo -e "$(timestamp) ${logTag} [ERROR]: ${1}"; }

function accept_eula() {
    logTag="accept_eula"
    worldDir="${1}"
    if [ -z "${worldDir}" ]; then logErr "World directory not provided"; return 1; fi
    if [ ! -d ${worldDir} ]; then logErr "World directory not found: ${worldDir}"; return 1; fi

    # Remove existing eula.txt file
    if [ -f ${worldDir}/eula.txt ]; then
        logInfo "Removing existing EULA file: ${worldDir}/eula.txt"
        rm -f ${worldDir}/eula.txt
    fi

cat << EOF >> "${worldDir}/eula.txt"
#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://aka.ms/MinecraftEULA).
#$(date)
eula=true

EOF

    logInfo "eula accepted for world: ${worldDir}"
    return 0
}

function backup_servers() {
    logTag="backup_servers"

    report_backup_success "Running Minecraft server backup..."
    logTag="backup_servers"

    # Ensure the S3 bucket exists
    logInfo "Checking existence of AWS S3 bucket for backup: ${S3_BUCKET_NAME}"
    ${awsCmd} s3 ls s3://${S3_BUCKET_NAME}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then
        report_backup_error "AWS S3 bucket not found: ${S3_BUCKET_NAME}"
        logTag="backup_servers"
        return 1
    fi

    # Create the backup directory
    if [ ! -d ${backupDir} ]; then
        logInfo "Creating backup directory: ${backupDir}"
        mkdir -p ${backupDir} >> ${logFile} 2>&1
    fi

    # Track 0=success, non-zero=failure
    local backupRes=0

    minecraftScreens=( $(screen -list | grep 'minecraft' | grep 'Detached' | awk -F . '{print $2}' | awk '{print $1}') )
    minecraftScreensStr="${minecraftScreens[@]}"

    # Creating lock file to prevent servers from starting
    logInfo "Creating lock file to prevent servers from starting during the backup process: ${serverLockFile}"
    touch ${serverLockFile}

    logInfo "Stopping running minecraft servers: [${minecraftScreensStr}]"

    if [ ${#minecraftScreens[@]} -gt 0 ]; then
        logInfo "Stopping all minecraft servers for backup..."
        stop_all_minecraft_servers
        if [ $? -ne 0 ]; then
            report_backup_error "Problem stopping Minecraft servers"
            logTag="backup_servers"
            logInfo "Removing lock file: ${serverLockFile}"
            rm -f ${serverLockFile}
            return 1
        fi
        logTag="backup_servers"
        logInfo "Waiting 3 seconds to proceed..."
        sleep 3
    else
        logInfo "No minecraft servers running, nothing to stop!"
    fi

    # Collect a list of all the worlds for backup
    logInfo "Getting a list of worlds in: ${worldsDir}"
    worlds=( $(ls ${worldsDir}) )
    worldsStr="${worlds[@]}"
    logInfo "Found ${#worlds[@]} worlds to backup: [${worldsStr}]"

    # Create the backup archives first
    for world in "${worlds[@]}"; do
        # Get the timestamp of the latest log file
        latestLogFile="${worldsDir}/${world}/logs/latest.log"
        if [ ! -f ${latestLogFile} ]; then
            logWarn "latest.log file not found for world ${world}: ${latestLogFile}"
        else
            logInfo "Getting timestamp from file: ${latestLogFile}"
            logTimestamp=$(stat -c "%y" ${latestLogFile})
            formattedLogTimestamp=$(date -d "${logTimestamp}" "+%Y-%m-%d_%H-%M-%S")
            logInfo "Found timestamp of ${formattedLogTimestamp} for log file: ${latestLogFile}"
            check_for_s3_backup "${world}" "${formattedLogTimestamp}"
            if [ $? -eq 0 ]; then
                logInfo "Backing up world: ${world}"
                compress_world_dir "${world}" "${formattedLogTimestamp}"
                if [ $? -ne 0 ]; then report_backup_error "Problem creating backup for world: ${world}"; backupRes=1; fi
                logTag="backup_servers"
            fi
        fi
    done

    # Remove the lock file to allow servers to start
    logInfo "Removing the lock file to so servers can start again: ${serverLockFile}"
    rm -f ${serverLockFile}

    # Restart servers that were running
    if [ ${#minecraftScreens[@]} -gt 0 ]; then
        logInfo "Starting servers that were running prior to the update: ${minecraftScreensStr}"
        for runningWorldScreenName in "${minecraftScreens[@]}"; do
            runningWorldName=$(echo ${runningWorldScreenName##minecraft_})
            logInfo "Waiting to start server: ${runningWorldName}"
            sleep 10
            logInfo "Restarting minecraft world: ${runningWorldName}"
            start_minecraft_server "${runningWorldName}"
            if [ $? -ne 0 ]; then report_backup_error "Problem starting minecraft server world: ${runningWorldName}"; res=1; fi
            logTag="backup_servers"
        done
    else
        logInfo "No minecraft servers were running before the backup, nothing to restart..."
    fi

    # Run the aws s3 sync command to sync the backups directory with S3
    logInfo "Syncing ${backupDir} to: [s3://${S3_BUCKET_NAME}/backups]..."
    aws s3 sync ${backupDir} s3://${S3_BUCKET_NAME}/backups
    if [ $? -ne 0 ]; then logErr "Problem syncing ${backupDir} to: [s3://${S3_BUCKET_NAME}/backups]"; exit 1; fi

    # Clean up the backup directory
    logInfo "Cleaning up the backup directory: ${backupDir}"
    rm -Rf ${backupDir}/*

    # Report completion to Slack
    if [ ${backupRes} -eq 0 ]; then
        report_backup_success "All backups completed successfully!"
    else
        report_backup_error "Backups had an error!"
    fi
    logTag="backup_servers"
    return ${backupRes}
}

function check_for_s3_backup() {
    # Return 0 if the s3 backup was not found
    # Return 1 if the s3 backup exists
    logTag="check_for_s3_backup"
    local checkWorldName="${1}"
    local checkTimestamp="${2}"
    logInfo "Checking for a backup in s3://${S3_BUCKET_NAME}/backups/ with name ${checkWorldName} and timestamp ${checkTimestamp}..."
    local existingBackup=$(${awsCmd} s3 ls s3://${S3_BUCKET_NAME}/backups/ | grep "${checkWorldName}" | grep ${checkTimestamp})
    if [ -z ${existingBackup} ]; then
        logInfo "Existing backup not found for world ${checkWorldName} and timestamp ${checkTimestamp}"
        return 0
    else
        logInfo "Found existing backup for world ${checkWorldName} and timestamp ${checkTimestamp}: ${existingBackup}"
        return 1
    fi
}

function check_for_running_server() {
    # Return 0 if running server not found
    # Return 1 if running server found
    logTag="check_for_running_server"
    worldName="${1}"
    screenName="minecraft_${worldName}"

    if [ -z "${worldName}" ]; then logErr "Please provide a world name arg"; return 1; fi

    logInfo "Checking for a running server: ${worldname}"

    minecraftScreenSession=$(screen -list | grep 'Detached' | grep "${screenName}")
    if [ -z "${minecraftScreenSession}" ]; then
        logInfo "Minecraft server not running: ${screenName}"
        return 0
    fi

    logInfo "Found running server: ${minecraftScreenSession}"
    return 1
}

function compress_world_dir() {
    logTag="compress_world_dir"
    local compressWorldName="${1}"
    local compressWorldTimestamp="${2}"

    if [ -z "${compressWorldName}" ]; then logErr "World name not provided"; return 1; fi
    if [ -z "${compressWorldTimestamp}" ]; then
        logWarn "Timestamp not provided, creating..."
        compressWorldTimestamp=$(timestamp_formatted)
    fi
    worldDirPathToCompress="${worldsDir}/${compressWorldName}"
    if [ ! -d ${worldDirPathToCompress} ]; then logErr "Path to world directory is not a directory: ${worldDirPathToCompress}" return 1; fi

    tarFilePath="${backupDir}/${compressWorldName}_${compressWorldTimestamp}.tar.gz"
    logInfo "Backing up world ${compressWorldName} to archive: ${tarFilePath}"
    /bin/tar -cvzf ${tarFilePath} ${worldDirPathToCompress} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "There was a problem creating archive: ${tarFilePath}"; return 1; fi
    logInfo "Created world archive: ${tarFilePath}"
    return 0
}

function create_new_world() {
    logTag="create_new_world"
    worldName="${1}"
    worldDir="${worldsDir}/${worldName}"
    serverConfigFile="${worldDir}/yennacraft.config.sh"
    sampleConfigFile="${scriptsDir}/sample-yennacraft.config.sh"
    serverProperties="${worldDir}/server.properties"
    sampleServerProperties="${scriptsDir}/sample-server.properties"

    if [ -z "${worldName}" ]; then logErr "Please provide a world name arg"; return 1; fi

    # Create the world directory
    logInfo "Creating new world: ${worldName}"
    mkdir -p ${worldDir} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem creating world directory: ${worldDir}"; return 1; fi

    # Ensure the sample config file exists
    if [ ! -f ${sampleConfigFile} ]; then logErr "Sample config file not found: ${sampleConfigFile}"; return 1; fi

    # Create the sample config file
    logInfo "Staging a sample config file to: ${serverConfigFile}"
    cp -f ${sampleConfigFile} ${serverConfigFile} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem creating staging server config file: ${serverConfigFile}"; return 1; fi

    logInfo "!!! Customize your world first here: ${serverConfigFile}"
    logInfo "!!! Customize your server properties: ${serverProperties}"

    logInfo "Finished creating new world: ${worldName}"
    return 0
}

function erase_world() {
    logTag="erase_world"
    worldName="${1}"
    worldDir="${worldsDir}/${worldName}"

    if [ -z "${worldName}" ]; then logErr "Please provide a world name arg"; return 1; fi

    logInfo "Erasing world: ${worldName}"
    cd ${worldDir}
    itemsToDelete=( $(ls | grep -v 'yennacraft.config.sh' | grep -v 'server.properties') )

    # Delete items
    for item in "${itemsToDelete[@]}"; do
        logInfo "Deleting item: ${item}"
        itemPath="${worldDir}/${item}"
        rm -Rf ${itemPath} >> ${logFile} 2>&1
        if [ $? -ne 0 ]; then logErr "Problem deleting item: ${itemPath}"; return 1; fi
    done
    logInfo "Completed erasing world: ${worldName}"
    return 0
}

function install_forge() {
    logTag="install_forge"
    worldName="${1}"
    worldDir="${worldsDir}/${worldName}"
    serverConfigFile="${worldDir}/yennacraft.config.sh"

    logInfo "Sourcing Minecraft world version file: ${serverConfigFile}"
    . ${serverConfigFile}

    # Ensure SERVER_VERSION is set
    if [ -z "${SERVER_VERSION}" ]; then logErr "SERVER_VERSION variable not set"; return 1; fi
    if [ -z "${VANILLA_VERSION}" ]; then logErr "VANILLA_VERSION variable not set"; return 1; fi

    # Set the java version
    set_java_version
    if [ $? -ne 0 ]; then logErr "Problem setting the java version"; return 1; fi

    # Determine the forge installer file name and install destination in the world directory
    forgeInstallerFileName="${SERVER_VERSION}-installer.jar"
    forgeInstallerDestination="${worldDir}/${forgeInstallerFileName}"

    # Determine the path to the forge installer jar file (it will be called server.jar due to how they download)
    forgeInstaller="${serverJarsDir}/${SERVER_VERSION}/server.jar"

    # Ensure the forge installer exists
    if [ ! -f ${forgeInstaller} ]; then logErr "Forge installer file not found: ${forgeInstaller}"; return 1; fi

    # Copy the forge installer
    logInfo "Copying forge installer [${forgeInstaller}] to world directory: ${forgeInstallerDestination}"
    cp -f ${forgeInstaller} ${forgeInstallerDestination} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem copying forge installer [${forgeInstaller}] to world directory: ${forgeInstallerDestination}"; return 1; fi

    # Determine the path to the vanilla minecraft server jar
    minecraftServerJar="${serverJarsDir}/${VANILLA_VERSION}/server.jar"

    # Ensure the vanilla minecraft server jar exists
    if [ ! -f ${minecraftServerJar} ]; then logErr "Minecraft world server jar not found: ${minecraftServerJar}, please run install-server-version.sh ${VANILLA_VERSION}"; return 1; fi

    # Run the forge installer from the world directory
    cd ${worldDir}/

    # Create the forge installer command
    forgeInstallCmd="${serverJava} -jar ${forgeInstallerFileName} --installServer"

    # Run the forge installer, this generates a new jar file in the world directory that will be used to start the server
    logInfo "Running the forge install command: [${forgeInstallCmd}]"
    ${forgeInstallCmd} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem installing forge with command: [${forgeInstallCmd}]"; return 1; fi

    logInfo "Completed forge install of [${forgeInstallerFileName}] in: ${worldDir}"
    return 0
}

function install_modpacks() {
    logTag="install_modpacks"
    worldName="${1}"
    worldDir="${worldsDir}/${worldName}"
    serverConfigFile="${worldDir}/yennacraft.config.sh"

    logInfo "Sourcing Minecraft world version file: ${serverConfigFile}"
    . ${serverConfigFile}

    # Ensure SERVER_VERSION is set
    if [ -z "${SERVER_VERSION}" ]; then logErr "SERVER_VERSION variable not set"; return 1; fi
    if [ -z "${VANILLA_VERSION}" ]; then logErr "VANILLA_VERSION variable not set"; return 1; fi

    # Check for mods
    logInfo "Checking for SERVER_MODPACKS..."
    if [ -z "${SERVER_MODPACKS}" ]; then
        logInfo "SERVER_MODPACKS variable not set, no modpacks to configure"
        return 0
    fi

    logInfo "Found SERVER_MODPACKS variable to configure: ${SERVER_MODPACKS}"

    # Split the comma-separated mods into an array
    serverModPacksArr=(${SERVER_MODPACKS//,/ })

    # Check if the mods are for forge or fabric
    if [[ "${MOD_FRAMEWORK}" == "forge" ]]; then
        logInfo "Installing forge mods for minecraft version ${VANILLA_VERSION}..."
        versionModPacksDir="${modPacksDir}/forge/${VANILLA_VERSION}"
    elif [[ "${MOD_FRAMEWORK}" == "fabric" ]]; then
        logInfo "Installing fabric mods for minecraft version ${VANILLA_VERSION}..."
        versionModPacksDir="${modPacksDir}/fabric/${VANILLA_VERSION}"
    else
        logErr "MOD_FRAMEWORK [${MOD_FRAMEWORK}] not recognized, expected forge or fabric"
        return 1
    fi

    # Ensure the mods dir exists for this version
    if [ ! -d ${versionModPacksDir} ]; then logErr "mods directory for this minecraft version not found: ${versionModPacksDir}"; return 1; fi
    logInfo "Checking for mods in: ${versionModPacksDir}"

    # Install modpacks
    for modPack in "${serverModPacksArr[@]}"; do
        logInfo "Installing modpack: ${modPack}"

        # Get the modpack file name
        modPackFileName=$(ls ${versionModPacksDir}/ | grep 'zip' | grep "${modPack}")
        if [ -z "${modPackFileName}" ]; then logErr "Modpack file [${modPack}] not found in mods directory: ${versionModPacksDir}"; return 1; fi
        modPackFile="${versionModPacksDir}/${modPackFileName}"
        if [ ! -f "${modPackFile}" ]; then logErr "Modpack file not found: ${modPackFile}"; return 1; fi

        # Extract the modpack to the world directory
        logInfo "Extracting modpack file [${modPackFile}] to world directory: ${worldDir}"
        unzip -o ${modPackFile} -d ${worldDir}/ >> ${logFile} 2>&1
        if [ $? -ne 0 ]; then logErr "Problem extracting modpack file [${modPackFile}] to world mod directory: ${worldModsDir}"; return 1; fi
    done
    logInfo "Completed setting up modpacks!"
}

function install_mods() {
    logTag="install_mods"
    worldName="${1}"
    worldDir="${worldsDir}/${worldName}"
    serverConfigFile="${worldDir}/yennacraft.config.sh"

    logInfo "Sourcing Minecraft world version file: ${serverConfigFile}"
    . ${serverConfigFile}

    # Ensure SERVER_VERSION is set
    if [ -z "${SERVER_VERSION}" ]; then logErr "SERVER_VERSION variable not set"; return 1; fi
    if [ -z "${VANILLA_VERSION}" ]; then logErr "VANILLA_VERSION variable not set"; return 1; fi

    # Check for mods
    logInfo "Checking for SERVER_MODS..."
    if [ -z "${SERVER_MODS}" ]; then
        logInfo "SERVER_MODS variable not set, no mods to configure"
        return 0
    fi

    logInfo "Found SERVER_MODS variable to configure: ${SERVER_MODS}"

    # Split the comma-separated mods into an array
    serverModsArr=(${SERVER_MODS//,/ })

    # Create the mods directory
    worldModsDir="${worldDir}/mods"
    logInfo "Creating mods directory: ${worldModsDir}"
    mkdir -p ${worldModsDir} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem creating mods directory: ${worldModsDir}"; return 1; fi

    # Check if the mods are for forge or fabric
    if [[ "${MOD_FRAMEWORK}" == "forge" ]]; then
        logInfo "Installing forge mods for minecraft version ${VANILLA_VERSION}..."
        versionModsDir="${modsDir}/forge/${VANILLA_VERSION}"
    elif [[ "${MOD_FRAMEWORK}" == "fabric" ]]; then
        logInfo "Installing fabric mods for minecraft version ${VANILLA_VERSION}..."
        versionModsDir="${modsDir}/fabric/${VANILLA_VERSION}"
    else
        logErr "MOD_FRAMEWORK [${MOD_FRAMEWORK}] not recognized, expected forge or fabric"
        return 1
    fi

    # Ensure the mods dir exists for this version
    if [ ! -d ${versionModsDir} ]; then logErr "mods directory for this minecraft version not found: ${versionModsDir}"; return 1; fi
    logInfo "Checking for mods in: ${versionModsDir}"

    # Install mods mods
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
}


function install_server_version() {
    logTag="install_server_version"
    serverVersionToInstall="${1}"

    if [ -z "${serverVersionToInstall}" ]; then logErr "Server version not provided"; return 1; fi
    #if [ -z "${serverDownloadUrls}" ]; then logErr "Server version download URLs not found"; return 1; fi
    if [ -z "${latestSnapshot}" ]; then logErr "Latest snapshot version not found"; return 1; fi
    if [ -z "${latestRelease}" ]; then logErr "Latest release version not found"; return 1; fi
    if [ -z "${latestSnapshotDownloadUrl}" ]; then logErr "Latest snapshot version download URL not found"; return 1; fi
    if [ -z "${latestReleaseDownloadUrl}" ]; then logErr "Latest release version download URL not found"; return 1; fi

    downloadUrl="${serverDownloadUrls[${serverVersionToInstall}]}"
    if [ -z "${downloadUrl}" ]; then logErr "Download URL not found for server version: ${serverVersionToInstall}"; return 1; fi
    logInfo "Using download URL: ${downloadUrl}"

    # Server jar location
    serverJarDir="${serverJarsDir}/${serverVersionToInstall}"
    serverJar="${serverJarDir}/server.jar"

    if [ ! -d ${serverJarDir} ]; then
        logInfo "Creating server version directory: ${serverJarDir}"
        mkdir -p ${serverJarDir} >> ${logFile} 2>&1
    fi

    cd ${serverJarDir} >> ${logFile} 2>&1
    if [ -f server.jar ]; then
        logInfo "Removing existing server.jar file"
        rm -f server.jar  >> ${logFile} 2>&1
    fi
    logInfo "Downloading minecraft server using download URL: ${downloadUrl}"
    curl -o server.jar ${downloadUrl} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem downloading minecraft server from URL: ${downloadUrl}"; return 1; fi
    if [ ! -f server.jar ]; then logErr "server.jar file not found"; return 1; fi
    cd -
    logInfo "Minecraft server download complete: ${serverJar}"

    update_latest_snapshot "${latestSnapshot}"
    if [ $? -ne 0 ]; then logErr "Problem setting latest snapshot to: ${latestSnapshot}"; fi
    update_latest_release "${latestRelease}"
    if [ $? -ne 0 ]; then logErr "Problem setting latest release to: ${latestRelease}"; fi
    logTag="install_server_version"
    logInfo "Completed server installation of version: ${serverVersionToInstall}"
    return 0
}

function report_backup_error() {
    logTag="report_backup_error"
    errMsg="${1}"
    if [ -z "${errMsg}" ]; then logErr "Error message not provided"; return 1; fi
    if [ -z "${SLACK_URL}" ]; then logErr "SLACK_URL not configured"; return 1; fi
    if [ -z "${SLACK_CHANNEL}" ]; then logErr "SLACK_CHANNEL not configured"; return 1; fi
    logErr "${errMsg}"

${slackCmd} \
--url="${SLACK_URL}" \
--channel="${SLACK_CHANNEL}" \
--text="Minecraft World Backup" \
--color=danger \
--attachment="${errMsg}"

}

function report_backup_success() {
    logTag="report_backup_success"
    msg="${1}"
    if [ -z "${msg}" ]; then logErr "Success message not provided"; return 1; fi
    if [ -z "${SLACK_URL}" ]; then logErr "SLACK_URL not configured"; return 1; fi
    if [ -z "${SLACK_CHANNEL}" ]; then logErr "SLACK_CHANNEL not configured"; return 1; fi
    logInfo "${msg}"

${slackCmd} \
--url="${SLACK_URL}" \
--channel="${SLACK_CHANNEL}" \
--text="Minecraft World Backup" \
--color=good \
--attachment="${msg}"

}

function set_java_version() {
    logInfo "Determining the java version to use..."
    if [[ "${1}" == "forge" ]]; then
        defaultJava="${java11Exe}"
        logInfo "Forge is using default java: ${java11Exe}"
    else
        defaultJava="${javaExe}"
    fi

    # Source the server config filr
    . ${serverConfigFile}

    # Check the JAVA_VERSION
    if [ -z "${JAVA_VERSION}" ]; then
        logInfo "No java version specified, using java 11 for forge by default..."
        serverJava="${defaultJava}"
    else
        case ${JAVA_VERSION} in
            8)
                serverJava="${java8Exe}"
                ;;
            11)
                serverJava="${java11Exe}"
                ;;
            17)
                serverJava="${java17Exe}"
                ;;
            *)
                logErr "Unrecognized java version, expected 8, 11, or 17: ${JAVA_VERSION}"
                return 1
        esac
    fi
    logInfo "Using java version: ${serverJava}"
    return 0
}

function start_minecraft_server() {
    logTag="start_minecraft_server"
    worldName="${1}"
    worldDir="${worldsDir}/${worldName}"
    serverConfigFile="${worldDir}/yennacraft.config.sh"

    if [ -f ${serverLockFile} ]; then logInfo "Lockfile found, not starting the server: ${serverLockFile}"; return 0; fi
    if [ -z "${worldName}" ]; then logErr "World name not provided"; return 1; fi
    if [ -z "${worldDir}" ]; then logErr "World directory not provided"; return 1; fi
    if [ ! -d ${worldDir} ]; then logErr "World directory not found: ${worldDir}"; return 1; fi
    if [ ! -e ${javaExe} ]; then logErr "${javaExe} not found"; return 1; fi
    if [ ! -e ${java8Exe} ]; then logErr "${java8Exe} not found"; return 1; fi
    if [ ! -e ${java11Exe} ]; then logErr "${java11Exe} not found"; return 1; fi
    if [ ! -e ${java17Exe} ]; then logErr "${java17Exe} not found"; return 1; fi
    if [ ! -e ${screenExe} ]; then logErr "${screenExe} not found"; return 1; fi
    if [ ! -f ${serverConfigFile} ]; then logErr "Minecraft world server version file not found: ${serverConfigFile}"; return 1; fi

    # Set the java version
    set_java_version
    if [ $? -ne 0 ]; then logErr "Problem setting the java version"; return 1; fi

    # Ensure the server java is found
    if [ ! -e ${serverJava} ]; then logErr "Server java [${serverJava}] not found"; return 1; fi

    logInfo "Sourcing Minecraft world version file: ${serverConfigFile}"
    . ${serverConfigFile}

    # Ensure SERVER_VERSION is set
    if [ -z "${SERVER_VERSION}" ]; then logErr "SERVER_VERSION variable not set"; return 1; fi

    # Check for running server
    check_for_running_server "${worldName}"
    local runningRes=$?
    logTag="start_minecraft_server"
    if [ ${runningRes} -eq 0 ]; then
        logInfo "Server is not running: ${worldName}"
    else
        logInfo "Server is already running: ${worldName}"
        logInfo "Exiting startup..."
        return 0
    fi

    # Print out settings
    logInfo "SERVER_VERSION: ${SERVER_VERSION}"
    logInfo "MOD_FRAMEWORK: ${MOD_FRAMEWORK}"
    logInfo "SERVER_MODS: ${SERVER_MODS}"
    logInfo "SERVER_MODPACKS: ${SERVER_MODPACKS}"

    # Set the xmx and xms java memory configurations
    if [ -z "${XMX_CONFIG}" ]; then
        logInfo "Using the default setting for java xmx arg: ${xmxConfig}"
    else
        xmxConfig="${XMX_CONFIG}"
        logInfo "Using server-configured java xmx arg: ${xmxConfig}"
    fi
    if [ -z "${XMS_CONFIG}" ]; then
        logInfo "Using the default setting for java xms arg: ${xmxConfig}"
    else
        xmsConfig="${XMS_CONFIG}"
        logInfo "Using server-configured java xms arg: ${xmsConfig}"
    fi

    # Install modpacks
    logInfo "Installing modpacks if any are configured..."
    install_modpacks "${worldName}"
    modPackRes=$?
    logTag="start_minecraft_server"
    if [ ${modPackRes} -ne 0 ]; then logErr "Problem installing modpacks for world: ${worldName}"; return 1; fi

    # Install mods
    logInfo "Installing mods if any are configured..."
    install_mods "${worldName}"
    modRes=$?
    logTag="start_minecraft_server"
    if [ ${modRes} -ne 0 ]; then logErr "Problem installing mods for world: ${worldName}"; return 1; fi

    if [[ "${MOD_FRAMEWORK}" == "forge" ]]; then
        logInfo "This is a forge server..."
        install_forge "${worldName}"
        forgeInstallRes=$?
        logTag="start_minecraft_server"
        if [ ${forgeInstallRes} -ne 0 ]; then logErr "Problem installing forge server"; return 1; fi
        serverJarFileName=$(ls ${worldDir}/ | grep 'jar' | grep 'forge' | grep -v 'installer')
        serverJar="${worldDir}/${serverJarFileName}"
    else
        serverJar="${serverJarsDir}/${SERVER_VERSION}/server.jar"
    fi

    # Ensure the server jar file is found
    if [ ! -f ${serverJar} ]; then logErr "Minecraft world server jar not found: ${serverJar}"; return 1; fi

    accept_eula "${worldDir}" "${serverJar}"
    logTag="start_minecraft_server"
    
    logInfo "Running minecraft world: ${worldDir}"
    cd ${worldDir}/
    minecraftCmd="${serverJava} ${xmxConfig} ${xmsConfig} -jar ${serverJar} nogui"
    screenName="minecraft_${worldName}"
    logInfo "Launching ${screenName} from screen with command: $minecraftCmd"
    ${screenExe} -d -m -L -Logfile ${logFile} -S ${screenName} ${minecraftCmd}
    if [ $? -ne 0 ]; then logErr "Problem launching screen ${screenName} command: $minecraftCmd"; return 1; fi
    logInfo "Started minecraft background screen successfully: ${screenName}"

    # Wait for server startup
    logInfo "Waiting 10 seconds to check for server startup..."
    sleep 10s

    # Check for running server
    check_for_running_server "${worldName}"
    local runningRes=$?
    logTag="start_minecraft_server"
    if [ ${runningRes} -eq 0 ]; then
        logErr "Server not started: ${worldName}"
        return 1
    fi
    logInfo "Completed starting server: ${worldName}"
    return 0
}

function stop_all_minecraft_servers() {
    logTag="stop_all_minecraft_servers"
    logInfo "Will attempt to find and stop all running minecraft screen sessions..."

    minecraftScreens=( $(screen -list | grep 'minecraft_' | grep 'Detached' | awk -F . '{print $2}' | awk '{print $1}') )
    minecraftScreensStr="${minecraftScreens[@]}}"

    if [ ${#minecraftScreens[@]} -lt 1 ]; then
        logInfo "No minecraft screen sessions found, nothing to quit"
        return 0
    fi
    logInfo "Found running minecraft screens: ${minecraftScreensStr}"

    # Create the lock file
    logInfo "Setting the lock file: ${serverLockFile}"
    touch ${serverLockFile}

    for minecraftScreen in "${minecraftScreens[@]}"; do
        logInfo "Attempting to quit minecraft session: ${minecraftScreen}"

        # Get the world name
        local stopWorldName=$(echo ${minecraftScreen} | awk -F _ '{print $2}')
        logInfo "Stopping server: ${stopWorldName}"
        stop_minecraft_server "${stopWorldName}"
        local stopRes=$?
        logTag="stop_all_minecraft_servers"
        if [ ${stopRes} -ne 0 ]; then logErr "Problem quitting minecraft screen session: ${minecraftScreen}"; return 1; fi
        logInfo "Stopped server with screen session: ${minecraftScreen}"
        logInfo "Waiting 2 seconds to stop the next server..."
        sleep 2
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

    # Check for running server
    check_for_running_server "${worldName}"
    local checkRes=$?
    logTag="stop_minecraft_server"
    if [ ${checkRes} -eq 0 ]; then
        logInfo "Minecraft server not running: ${screenName}"
        return 0
    fi

    # Create the lock file
    logInfo "Setting the lock file: ${serverLockFile}"
    touch ${serverLockFile}

    logInfo "Stopping the minecraft server: ${screenName}"
    screen -S ${screenName} -X stuff "/stop^M"
    logInfo "Waiting 60 seconds for the world to shut down..."
    sleep 60

    # Check for running server
    check_for_running_server "${worldName}"
    local checkRes=$?
    logTag="stop_minecraft_server"
    if [ ${checkRes} -eq 0 ]; then
        logInfo "Minecraft server not running: ${screenName}"
        return 0
    fi
    logInfo "Screen session still found: ${screenName}"
    logInfo "Quitting screen session: ${screenName}..."
    screen -X -S ${screenName} quit
    if [ $? -ne 0 ]; then logErr "Problem quitting minecraft screen session: ${screenName}"; return 1; fi
    logInfo "Successfully from minecraft screen session: ${screenName}"
    return 0
}

function update_latest_release() {
    logTag="update_latest_release"
    latestReleaseServerVersion="${1}"

    if [ -z "${latestReleaseServerVersion}" ]; then logErr "Server version not provided"; return 1; fi

    # Server jar location
    serverJarDir="${serverJarsDir}/${latestReleaseServerVersion}"
    if [ ! -d ${serverJarDir} ]; then logErr "Server directory not found: ${serverJarDir}"; return 1; fi

    logInfo "Updating the links to the latest release..."
    if [ -e ${serverJarsDir}/release ]; then
        logInfo "Removing existing link: ${serverJarsDir}/release"
        rm -f ${serverJarsDir}/release >> ${logFile} 2>&1
    fi
    logInfo "Adding link ${serverJarDir} to: ${serverJarsDir}/release"
    ln -sf $serverJarDir ${serverJarsDir}/release >> ${logFile} 2>&1
    return $?
}

function update_latest_snapshot() {
    logTag="update_latest_snapshot"
    latestSnapshotServerVersion="${1}"

    if [ -z "${latestSnapshotServerVersion}" ]; then logErr "Server version not provided"; return 1; fi

    # Server jar location
    serverJarDir="${serverJarsDir}/${latestSnapshotServerVersion}"

    logInfo "Updating the links to the latest snapshot..."
    if [ -e ${serverJarsDir}/latest ]; then
        logInfo "Removing existing link: ${serverJarsDir}/latest"
        rm -f ${serverJarsDir}/latest >> ${logFile} 2>&1
    fi
    logInfo "Adding link ${serverJarDir} to: ${serverJarsDir}/latest"
    ln -sf ${serverJarDir} ${serverJarsDir}/latest >> ${logFile} 2>&1
    return $?
}
