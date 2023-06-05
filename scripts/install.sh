#!/bin/bash

# Source the environment
if [ -f /etc/bashrc ] ; then
    . /etc/bashrc
fi
if [ -f /etc/profile ] ; then
    . /etc/profile
fi
if [ ! -f /usr/local/bashcons3rt/bash_cons3rt.sh ]; then
    echo "bashcons3rt is required to be installed for this to work: https://github.com/jyennaco/bachcons3rt"
    echo "1: become root"
    echo "2: git clone https://github.com/jyennaco/bachcons3rt"
    echo "3: cd bashcons3rt"
    echo "4: ./scripts/install_bash_cons3rt.sh"
    echo "Once completed, retry!"
    exit 100
fi

# Establish a log file and log tag
logTag="install-minecraft-server"
logDir="/opt/cons3rt-agent/log"
logFile="${logDir}/${logTag}-$(date "+%Y%m%d-%H%M%S").log"

######################### GLOBAL VARIABLES #########################

# Script dir
sourceScriptsDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Management scripts
backupScript="${sourceScriptsDir}/backup-minecraft-servers.sh"
commonScript="${sourceScriptsDir}/common.sh"
installServerVersionScript="${sourceScriptsDir}/install-server-version.sh"
restartScript="${sourceScriptsDir}/restart-server.sh"
startScript="${sourceScriptsDir}/start-server.sh"
stopScript="${sourceScriptsDir}/stop-server.sh"
versionsScript="${sourceScriptsDir}/server-versions.sh"

# Minecraft directories
minecraftServerDir="/opt/Minecraft_Servers"
worldsDir="${minecraftServerDir}/worlds"
serverJarsDir="${minecraftServerDir}/server_jars"
modsDir="${minecraftServerDir}/mods"
scriptsDir="${minecraftServerDir}/scripts"
backupsDir="${minecraftServerDir}/backups"
firstWorldDir="${worldsDir}/first_world"


# Config file for selecting a minecraft world
configFile="${minecraftServerDir}/config.sh"

# First world server jar
firstWorldServerJar=

# Set the download URL to the latestReleaseDownloadUrl by default
downloadUrl=
latestRelease=

####################### END GLOBAL VARIABLES #######################

function verify_prerequisites() {
    logInfo "Verifying prerequisites..."
    if [ ! -f ${backupScript} ]; then logErr "Script not found: ${backupScript}"; return 1; fi
    if [ ! -f ${commonScript} ]; then logErr "Script not found: ${commonScript}"; return 1; fi
    if [ ! -f ${installServerVersionScript} ]; then logErr "Script not found: ${installServerVersionScript}"; return 1; fi
    if [ ! -f ${restartScript} ]; then logErr "Script not found: ${restartScript}"; return 1; fi
    if [ ! -f ${startScript} ]; then logErr "Script not found: ${startScript}"; return 1; fi
    if [ ! -f ${stopScript} ]; then logErr "Script not found: ${stopScript}"; return 1; fi
    if [ ! -f ${versionsScript} ]; then logErr "Script not found: ${versionsScript}"; return 1; fi

    # Source the common and versions scripts
    . ${commonScript}
    . ${versionsScript}

    # Set the download URL
    downloadUrl="${latestReleaseDownloadUrl}"

    if [ -z "${downloadUrl}" ]; then logErr "The download URL was not set"; return 1; fi
    if [ -z "${latestRelease}" ]; then logErr "The latest release was not found"; return 1; fi
    logInfo "Using latest release version: ${latestRelease}"
    logInfo "Using download URL: ${downloadUrl}"

    firstWorldServerJarDir="${serverJarsDir}/${latestRelease}"
    logInfo "Using first world server release directory: ${firstWorldServerJarDir}"
    logInfo "All prerequisites verified!"
    return 0
}

function install_java() {
    logInfo "I am installing java and prerequisites for Ubuntu..."
    apt-get -y install software-properties-common >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem installing: software-properties-common"; return 1; fi
    logInfo "Installing Java..."
    apt -y install default-jdk >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem installing java"; return 1; fi
    logInfo "Completed installing Java! :D"
    return 0
}

function install_screen() {
    logInfo "Installing screen..."
    apt -y install screen >> ${logFile} 2>&1
    return $?
}

function create_minecraft_users() {
    logInfo "Creating users: minecraft mcbackup"
    create_user "minecraft"
    if [ $? -ne 0 ]; then logErr "Problem creating user: minecraft"; return 1; fi
    create_user "mcbackup"
    if [ $? -ne 0 ]; then logErr "Problem creating user: mcbackup"; return 1; fi
    logInfo "Created users: minecraft mcbackup"
    return 0
}

function create_directories() {
    logInfo "Creating minecraft server directories under: ${minecraftServerDir}"
    mkdir -p ${minecraftServerDir} >> ${logFile} 2>&1
    mkdir -p ${worldsDir} >> ${logFile} 2>&1
    mkdir -p ${serverJarsDir} >> ${logFile} 2>&1
    mkdir -p ${modsDir} >> ${logFile} 2>&1
    mkdir -p ${scriptsDir} >> ${logFile} 2>&1
    mkdir -p ${backupsDir} >> ${logFile} 2>&1
    mkdir -p ${firstWorldDir} >> ${logFile} 2>&1
    mkdir -p ${firstWorldServerJarDir} >> ${logFile} 2>&1
    logInfo "Finished creating directories"
    return 0
}

function create_config_file() {
    logInfo "Creating minecraft world config file: $configFile"

cat << EOF >> "${configFile}"
MINECRAFT_WORLD=first_world
EOF

    return 0
}

function download_minecraft_server() {
    logInfo "Downloading the minecraft server jar..."
    cd ${firstWorldServerJarDir} >> ${logFile} 2>&1
    if [ -f server.jar ]; then
        logInfo "Removing existing server.jar file"
        rm -f server.jar  >> ${logFile} 2>&1
    fi
    logInfo "Downloading minecraft server using download URL: ${downloadUrl}"
    curl -O ${downloadUrl} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem downloading minecraft server from ${downloadUrl}"; return 1; fi
    if [ ! -f server.jar ]; then logErr "server.jar file not found"; return 1; fi
    cd -
    logInfo "Minecraft server download complete: ${firstWorldServerJar}"
    return 0
}

function accept_eula() {
    logInfo "Running the Minecraft server to accept the EULA..."
    cd ${firstWorldDir}
    timeout 20s java -Xmx1024M -Xms1024M -jar ${firstWorldServerJar} nogui >> ${logFile} 2>&1
    if [ ! -f ${firstWorldDir}/eula.txt ]; then logErr "${firstWorldDir}/eula.txt not found"; return 1; fi
    sed -i "s|eula=false|eula=true|g" ${firstWorldDir}/eula.txt
    return 0
}

function config_minecraft_service() {
    logInfo "Setting up the minecraft server as a service..."

    # Create the systemd service directory if it does not exist
    systemdServiceDir="/etc/systemd/system"
    if [ ! -d ${systemdServiceDir} ]; then
        logInfo "Creating directory: $systemdServiceDir"
        mkdir -p $systemdServiceDir >> ${logFile} 2>&1
    fi
    serviceFile="$systemdServiceDir/minecraft.service"
    if [ -f ${serviceFile} ]; then
        logInfo "Removing existing file: $serviceFile"
        rm -f $serviceFile
    fi

    # Stage the minecraft service script
    logInfo "Staging run-minecraft service script: $serviceScript"
    cp -f $runMinecraftScript $serviceScript >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging $runMinecraftScript to: $serviceScript"; return 1; fi

    # Stage the minecraft session stop script
    logInfo "Staging stop-minecraft service script: $stopScript"
    cp -f $stopMinecraftScript $stopScript >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging $stopMinecraftScript to: $stopScript"; return 1; fi

    # Stage the minecraft session restart script
    logInfo "Staging restart-minecraft service script: $restartScript"
    cp -f $restartMinecraftScript $restartScript >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging $restartMinecraftScript to: $restartScript"; return 1; fi

    # Edit the minecraft servers directory
    sed -i "s|REPLACE_MINECRAFT_SERVER_DIR|${minecraftServerDir}|g" $serviceScript

    # Set permissions on the minecraft service script
    logInfo "Setting permissions on: $serviceScript"
    chown minecraft:minecraft $serviceScript >> ${logFile} 2>&1
    chmod 750 $serviceScript >> ${logFile} 2>&1
    logInfo "Created service script: $serviceScript"

    # Set permissions on the stop minecraft sessions script
    logInfo "Setting permissions on: $stopScript"
    chown minecraft:minecraft $stopScript >> ${logFile} 2>&1
    chmod 750 $stopScript >> ${logFile} 2>&1
    logInfo "Created stop script: $stopScript"

    # Set permissions on the restart minecraft sessions script
    logInfo "Setting permissions on: $restartScript"
    chown minecraft:minecraft $restartScript >> ${logFile} 2>&1
    chmod 750 $restartScript >> ${logFile} 2>&1
    logInfo "Created restart script: $restartScript"

    logInfo "Creating file: $serviceFile"

cat << EOF >> "${serviceFile}"
[Unit]
Description=Minecraft Server

[Service]
Type=simple
ExecStart=/bin/bash ${serviceScript}
User=minecraft
RemainAfterExit=no
Restart=no

[Install]
WantedBy=multi-user.target

EOF

    logInfo "Setting permissions on: $serviceFile"
    chown root:root $serviceFile >> ${logFile} 2>&1
    chmod 755 $serviceFile >> ${logFile} 2>&1
    logInfo "Created service file: $serviceFile"
    return 0
}

function run_minecraft_service() {
    logInfo "Running the Minecraft server..."
    accept_eula
    if [ $? -ne 0 ]; then logErr "Problem accepting the EULA"; return 1; fi
    config_minecraft_service
    logInfo "Starting and enabling the minecraft.service..."
    logInfo "Setting permissions on: $minecraftServerDir"
    chown -R minecraft:minecraft $minecraftServerDir
    chown -R minecraft:minecraft $logDir
    systemctl enable minecraft.service >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem enabling minecraft.service"; return 1; fi
    systemctl start minecraft.service >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem start minecraft.service"; return 1; fi
    return 0
}

function install_management_scripts() {
    logInfo "Installing management scripts to: ${scriptsDir}"
    cp -f ${backupScript} ${scriptsDir}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging backup script: ${backupScript} to ${scriptsDir}"; return 1; fi
    cp -f ${commonScript} ${scriptsDir}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging backup script: ${commonScript} to ${scriptsDir}"; return 1; fi
    cp -f ${installServerVersionScript} ${scriptsDir}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging backup script: ${installServerVersionScript} to ${scriptsDir}"; return 1; fi
    cp -f ${restartScript} ${scriptsDir}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging backup script: ${restartScript} to ${scriptsDir}"; return 1; fi
    cp -f ${startScript} ${scriptsDir}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging backup script: ${startScript} to ${scriptsDir}"; return 1; fi
    cp -f ${stopScript} ${scriptsDir}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging backup script: ${stopScript} to ${scriptsDir}"; return 1; fi
    cp -f ${versionsScript} ${scriptsDir}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging backup script: ${versionsScript} to ${scriptsDir}"; return 1; fi
    logInfo "Completed installing management script to: ${scriptsDir}"
    return 0
}

function main() {
    logInfo "Starting install script: ${logTag}"
    verify_prerequisites
    if [ $? -ne 0 ]; then logErr "Problem verifying prerequisites"; return 1; fi
    create_directories
    if [ $? -ne 0 ]; then logErr "Problem creating directories"; return 2; fi
    install_management_scripts
    if [ $? -ne 0 ]; then logErr "Problem installing management scripts"; return 3; fi
    install_java
    if [ $? -ne 0 ]; then logErr "Problem installing java or its prerequisites"; return 4; fi
    install_screen
    if [ $? -ne 0 ]; then logErr "Problem installing screen"; return 5; fi
    create_minecraft_users
    if [ $? -ne 0 ]; then logErr "Problem creating the minecraft user"; return 6; fi
    create_config_file
    if [ $? -ne 0 ]; then logErr "Problem creating config file"; return 7; fi
    download_minecraft_server
    if [ $? -ne 0 ]; then logErr "Problem downloading minecraft server"; return 8; fi
    accept_eula
    if [ $? -ne 0 ]; then logErr "Problem accepting the eula"; return 9; fi
    #run_minecraft_service
    #if [ $? -ne 0 ]; then logErr "Problem running minecraft service"; return 6; fi
    logInfo "Successfully completed: ${logTag}"
    logInfo "GO PLAY SOME MINECRAFT!!!!"
    return 0
}

# Set up the log file
mkdir -p ${logDir}
chmod 755 ${logDir}
touch ${logFile}
chmod 644 ${logFile}
main
result=$?
logInfo "Exiting with code ${result} ..."
cat ${logFile}
exit ${result}
