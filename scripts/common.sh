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
backupDir="${minecraftServerDir}/backups"
scriptsDir="${minecraftServerDir}/scripts"
logDir="${minecraftServerDir}/log"
versionsFile="${scriptsDir}/server-versions.sh"
awsCmd="/usr/local/bin/aws"
slackCmd="/usr/local/bin/slack"
javaExe='/opt/java/jre/bin/java'
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
    #serverJar="${2}"
    if [ -z "${worldDir}" ]; then logErr "World directory not provided"; return 1; fi
    #if [ -z "${serverJar}" ]; then logErr "Server jar not provided"; return 1; fi
    if [ ! -d ${worldDir} ]; then logErr "World directory not found: ${worldDir}"; return 1; fi
    #if [ ! -f ${serverJar} ]; then logErr "Server jar file not found: ${serverJar}"; return 1; fi

    # TODO remove when no longer needed, the odl way of accepting the EULA
    #if [ ! -f ${worldDir}/eula.txt ]; then
    #    logInfo "Running the Minecraft server jar ${serverJar} to accept the EULA in world directory: ${worldDir}"
    #    cd ${worldDir}
    #    timeout 20s java -Xmx1024M -Xms1024M -jar ${serverJar} nogui >> ${logFile} 2>&1
    #    if [ ! -f ${worldDir}/eula.txt ]; then logErr "${worldDir}/eula.txt not found"; return 1; fi
    #    cd -
    #else
    #    logInfo "eula.txt file found, no need to re-generate..."
    #fi
    #sed -i "s|eula=false|eula=true|g" ${worldDir}/eula.txt

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

function install_forge() {
    logTag="install_forge"
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

function compress_world_dir() {
    logTag="compress_world_dir"
    worldName="${1}"

    if [ -z "${worldName}" ]; then logErr "World name not provided"; return 1; fi
    worldDirPathToCompress="${worldsDir}/${worldName}"
    if [ ! -d ${worldDirPathToCompress} ]; then logErr "Path to world directory is not a directory: ${worldDirPathToCompress}" return 1; fi

    tarFilePath="${backupDir}/${worldName}_$(timestamp_formatted).tar.gz"
    logInfo "Backing up world ${worldName} to archive: ${tarFilePath}"
    /bin/tar -cvzf ${tarFilePath} ${worldDirPathToCompress} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "There was a problem creating archive: ${tarFilePath}"; return 1; fi
    logInfo "Created world archive: ${tarFilePath}"
    return 0
}

function backup_to_s3() {
    logTag="backup_to_s3"
    file_to_upload="${1}"

    if [ -z ${file_to_upload} ]; then logErr "Path to file not provided"; return 1; fi
    if [ ! -f ${file_to_upload} ]; then logErr "File to upload not found: ${file_to_upload}"; return 2; fi
    if [ -z ${BACKUP_S3_BUCKET} ]; then logErr "BACKUP_S3_BUCKET is not configured"; return 1; fi

    logInfo "Copying backup file to AWS S3..."
    ${awsCmd} s3 cp ${file_to_upload} s3://${BACKUP_S3_BUCKET}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then
        logErr "There was a problem backing up the file to AWS S3 bucket: ${BACKUP_S3_BUCKET}"
        return 3
    fi
    logInfo "File backed up successfully to AWS S3 bucket ${BACKUP_S3_BUCKET}: ${file_to_upload}"
    return 0
}

function backup_servers() {
    logTag="backup_servers"

    report_backup_success "Running Minecraft server backup..."

    # Create the backup directory
    if [ ! -d ${backupDir} ]; then
        logInfo "Creating backup directory: ${backupDir}"
        mkdir -p ${backupDir} >> ${logFile} 2>&1
    fi

    # Ensure the S3 bucket exists
    logInfo "Checking existence of AWS S3 bucket for backup: ${BACKUP_S3_BUCKET}"
    ${awsCmd} s3 ls s3://${BACKUP_S3_BUCKET}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then report_backup_error "AWS S3 bucket not found: ${BACKUP_S3_BUCKET}"; return 1; fi

    # Track 0=success, non-zero=failure
    res=0

    minecraftScreens=( $(screen -list | grep 'minecraft' | grep 'Detached' | awk -F . '{print $2}' | awk '{print $1}') )
    minecraftScreensStr="${minecraftScreens[@]}"
    logInfo "Stopping running minecraft servers: [${minecraftScreensStr}]"

    logInfo "Stopping all minecraft servers for backup..."
    stop_all_minecraft_servers
    if [ $? -ne 0 ]; then report_backup_error "Problem stopping Minecraft servers"; return 1; fi
    logTag="backup_servers"

    logInfo "Sleeping before proceeding..."
    sleep 3

    # Collect a list of all the worlds for backup
    logInfo "Getting a list of worlds in: ${worldsDir}"
    worlds=( $(ls ${worldsDir}) )
    worldsStr="${worlds[@]}"
    logInfo "Found ${#worlds[@]} worlds to backup: [${worldsStr}]"

    # Create the backup archives first
    for world in "${worlds[@]}"; do
        logInfo "Backing up world: ${world}"
        compress_world_dir "${world}"
        if [ $? -ne 0 ]; then report_backup_error "Problem creating backup for world: ${world}"; res=1; fi
        logTag="backup_servers"
    done

    # Restart servers that were running
    logInfo "Restarting servers that were running: ${minecraftScreensStr}"
    for runningWorldScreenName in "${minecraftScreens}"; do
        runningWorldName=$(echo ${runningWorldScreenName##minecraft_})
        logInfo "Restarting minecraft world: ${runningWorldScreenName}"
        start_minecraft_server "${runningWorldName}"
        if [ $? -ne 0 ]; then report_backup_error "Problem restarting minecraft server world: ${runningWorldName}"; res=1; fi
        logTag="backup_servers"
        logInfo "Waiting to start the new one..."
        sleep 20
    done

    # Upload the archives to S3
    archives=( $(ls ${backupDir}) )
    archivesStr="${archives[@]}"
    logInfo "Uploading ${#archives[@]} archives: [${archivesStr}]"

    for archive in "${archives[@]}"; do
        archivePath="${backupDir}/${archive}"
        if [ ! -f ${archivePath} ]; then
            report_backup_error "Backup archive not found: ${archivePath}"
            logTag="backup_servers"
            res=1
            continue
        fi
        logInfo "First check if the archive was already backed up: ${archive}"
        existingArchive=$(${awsCmd} s3 ls s3://${BACKUP_S3_BUCKET} | grep "${archive}")
        if [ -z ${existingArchive} ]; then
            logInfo "Uploading archive: ${archive}"
            archivePath="${backupDir}/${archive}"
            ${awsCmd} s3 cp ${archivePath} s3://${BACKUP_S3_BUCKET}/ >> ${logFile} 2>&1
            if [ $? -ne 0 ]; then
                report_backup_error "Problem uploading archive: ${archivePath}"
                logTag="backup_servers"
                res=1
                continue
            fi
            logInfo "Backup complete for ${archive} to AWS S3 bucket: ${BACKUP_S3_BUCKET}, removing local backup..."
            /bin/rm -f ${archivePath} >> ${logFile} 2>&1
        else
            logInfo "Found existing upload for ${archive} in AWS S3 bucket: ${BACKUP_S3_BUCKET}: [${existingArchive}], removing local backup..."
            /bin/rm -f ${archivePath} >> ${logFile} 2>&1
        fi
    done

    # Report completion to Slack
    if [ ${res} -eq 0 ]; then
        report_backup_success "All backups completed successfully!"
    else
        report_error "Backups had an error!"
    fi
    return ${res}
}
