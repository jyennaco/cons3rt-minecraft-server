#!/bin/bash

# Source the environment
if [ -f /etc/bashrc ] ; then
    . /etc/bashrc
fi
if [ -f /etc/profile ] ; then
    . /etc/profile
fi

# Establish a log file and log tag
logTag="install-minecraft-server"
logDir="/var/log/minecraft"
logFile="${logDir}/${logTag}-$(date "+%Y%m%d-%H%M%S").log"

######################### GLOBAL VARIABLES #########################

# Script dir
scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Management scripts
runMinecraftScript="${scriptDir}/run-minecraft.sh"
stopMinecraftScript="${scriptDir}/stop-minecraft.sh"
restartMinecraftScript="${scriptDir}/restart-minecraft.sh"
backupScript="${scriptDir}/backup-minecraft-servers.sh"
updateScript="${scriptDir}/update-server-version.sh"

# Minecraft directories
minecraftServerDir="/opt/Minecraft_Servers"
worldsDir="${minecraftServerDir}/worlds"
firstWorldDir="${worldsDir}/first_world"
serverJarsDir="${minecraftServerDir}/server_jars"

# Config file for selecting a minecraft world
configFile="${minecraftServerDir}/config.sh"

# Default world directory

# Service script locations
serviceScript="/usr/local/bin/run-minecraft.sh"
stopScript="/usr/local/bin/stop-minecraft.sh"
restartScript="/usr/local/bin/restart-minecraft.sh"

# Minecraft server download URL and version
#serverVersion='1.15.2'
#downloadUrl="https://launcher.mojang.com/v1/objects/bb2b6b1aefcd70dfd1892149ac3a215f6c636b07/server.jar"
serverVersion='1.16-pre2'
downloadUrl="https://launcher.mojang.com/v1/objects/8daeb71269eb164097d7d7ab1fa93fc93ab125c3/server.jar"

# First world server version jar directory
firstWorldServerJarDir="${serverJarsDir}/${serverVersion}"
firstWorldServerJar="${firstWorldServerJarDir}/server.jar"

####################### END GLOBAL VARIABLES #######################

# Logging functions
function timestamp() { date "+%F %T"; }
function logInfo() { echo -e "$(timestamp) ${logTag} [INFO]: ${1}" >> ${logFile}; echo -e "$(timestamp) ${logTag} [INFO]: ${1}"; }
function logWarn() { echo -e "$(timestamp) ${logTag} [WARN]: ${1}" >> ${logFile}; echo -e "$(timestamp) ${logTag} [WARN]: ${1}"; }
function logErr() { echo -e "$(timestamp) ${logTag} [ERROR]: ${1}" >> ${logFile}; echo -e "$(timestamp) ${logTag} [ERROR]: ${1}"; }

function verify_prerequisites() {
    logInfo "Verifying prerequisites..."
    if [ ! -f ${runMinecraftScript} ]; then logErr "run-minecraft script not found: $runMinecraftScript"; return 1; fi
    if [ ! -f ${stopMinecraftScript} ]; then logErr "stop-minecraft script not found: $stopMinecraftScript"; return 1; fi
    if [ ! -f ${restartMinecraftScript} ]; then logErr "restart-minecraft script not found: $restartMinecraftScript"; return 1; fi
    if [ ! -f ${backupScript} ]; then logErr "Backup script not found: $backupScript"; return 1; fi
    if [ ! -f ${updateScript} ]; then logErr "Update script not found: $updateScript"; return 1; fi
    logInfo "All prerequisites verified!"
    return 0
}

function install_java() {
    logInfo "I am installing java and prerequisites for Ubuntu..."
    apt-get -y install software-properties-common >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem installing: software-properties-common"; return 1; fi
    logInfo "Installing Java..."
    apt-get -y install openjdk-8-jdk-headless >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem installing: openjdk-8-jdk-headless"; return 1; fi
    logInfo "Completed installing Java! :D"
    return 0
}

function install_screen() {
    logInfo "Installing screen..."
    apt-get -y install screen >> $logFile 2>&1
    return $?
}

function create_minecraft_users() {
    logInfo "Creating users: minecraft mcbackup"
    useradd -d '/home/minecraft' -s '/bin/bash' -c 'Minecraft User' minecraft >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem with useradd minecraft"; return 1; fi
    mkhomedir_helper minecraft >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem creating home directory for minecraft user"; return 1; fi
    useradd -d '/home/mcbackup' -s '/bin/bash' -c 'Minecraft Backup User' mcbackup >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem with useradd mcbackup"; return 1; fi
    mkhomedir_helper mcbackup >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem creating home directory for mcbackup user"; return 1; fi
    logInfo "Created users: minecraft mcbackup"
    return 0
}

function create_directories() {
    if [ ! -d ${firstWorldDir} ]; then
        logInfo "Creating directory: $firstWorldDir"
        mkdir -p ${firstWorldDir} >> $logFile 2>&1
    fi
    if [ ! -d ${firstWorldServerJarDir} ]; then
        logInfo "Creating directory: $firstWorldServerJarDir"
        mkdir -p ${firstWorldServerJarDir} >> $logFile 2>&1
    fi
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

    cd ${firstWorldServerJarDir} >> $logFile 2>&1
    if [ -f server.jar ]; then
        logInfo "Removing existing server.jar file"
        rm -f server.jar  >> $logFile 2>&1
    fi
    logInfo "Downloading minecraft server using download URL: $downloadUrl"
    curl -O $downloadUrl >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem downloading minecraft server from $downloadUrl"; return 1; fi
    if [ ! -f server.jar ]; then logErr "server.jar file not found"; return 1; fi
    cd -
    logInfo "Minecraft server download complete: ${firstWorldServerJar}"
    return 0
}

function accept_eula() {
    logInfo "Running the Minecraft server to accept the EULA..."
    cd ${firstWorldDir}
    timeout 20s java -Xmx1024M -Xms1024M -jar ${firstWorldServerJar} nogui >> $logFile 2>&1
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
        mkdir -p $systemdServiceDir >> $logFile 2>&1
    fi
    serviceFile="$systemdServiceDir/minecraft.service"
    if [ -f ${serviceFile} ]; then
        logInfo "Removing existing file: $serviceFile"
        rm -f $serviceFile
    fi

    # Stage the minecraft service script
    logInfo "Staging run-minecraft service script: $serviceScript"
    cp -f $runMinecraftScript $serviceScript >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging $runMinecraftScript to: $serviceScript"; return 1; fi

    # Stage the minecraft session stop script
    logInfo "Staging stop-minecraft service script: $stopScript"
    cp -f $stopMinecraftScript $stopScript >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging $stopMinecraftScript to: $stopScript"; return 1; fi

    # Stage the minecraft session restart script
    logInfo "Staging restart-minecraft service script: $restartScript"
    cp -f $restartMinecraftScript $restartScript >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging $restartMinecraftScript to: $restartScript"; return 1; fi

    # Edit the minecraft servers directory
    sed -i "s|REPLACE_MINECRAFT_SERVER_DIR|${minecraftServerDir}|g" $serviceScript

    # Set permissions on the minecraft service script
    logInfo "Setting permissions on: $serviceScript"
    chown minecraft:minecraft $serviceScript >> $logFile 2>&1
    chmod 750 $serviceScript >> $logFile 2>&1
    logInfo "Created service script: $serviceScript"

    # Set permissions on the stop minecraft sessions script
    logInfo "Setting permissions on: $stopScript"
    chown minecraft:minecraft $stopScript >> $logFile 2>&1
    chmod 750 $stopScript >> $logFile 2>&1
    logInfo "Created stop script: $stopScript"

    # Set permissions on the restart minecraft sessions script
    logInfo "Setting permissions on: $restartScript"
    chown minecraft:minecraft $restartScript >> $logFile 2>&1
    chmod 750 $restartScript >> $logFile 2>&1
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
    chown root:root $serviceFile >> $logFile 2>&1
    chmod 755 $serviceFile >> $logFile 2>&1
    logInfo "Created service file: $serviceFile"
    return 0
}

function run_minecraft_server() {
    logInfo "Running the Minecraft server..."
    accept_eula
    if [ $? -ne 0 ]; then logErr "Problem accepting the EULA"; return 1; fi
    config_minecraft_service
    logInfo "Starting and enabling the minecraft.service..."
    logInfo "Setting permissions on: $minecraftServerDir"
    chown -R minecraft:minecraft $minecraftServerDir
    chown -R minecraft:minecraft $logDir
    systemctl enable minecraft.service >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem enabling minecraft.service"; return 1; fi
    systemctl start minecraft.service >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem start minecraft.service"; return 1; fi
    return 0
}

function install_management_scripts() {
    logInfo "Installing management scripts..."
    cp -f $backupScript /usr/local/bin >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging backup script: $backupScript to /usr/local/bin"; return 1; fi
    cp -f $updateScript /usr/local/bin >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem staging update script: $updateScript to /usr/local/bin"; return 1; fi
    chmod 750 /usr/local/bin/backup-mincraft-servers.sh >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem setting permissions on: /usr/local/bin/backup-mincraft-servers.sh"; return 1; fi
    chmod 750 /usr/local/bin/update-server-version.sh >> $logFile 2>&1
    if [ $? -ne 0 ]; then logErr "Problem setting permissions on: /usr/local/bin/update-server-version.sh"; return 1; fi
    chown mcbackup:mcbackup /usr/local/bin/backup-mincraft-servers.sh
    if [ $? -ne 0 ]; then logErr "Problem setting ownership on: /usr/local/bin/backup-mincraft-servers.sh"; return 1; fi
    chown minecraft:minecraft /usr/local/bin/update-server-version.sh
    if [ $? -ne 0 ]; then logErr "Problem setting ownership on: /usr/local/bin/update-server-version.sh"; return 1; fi
    return 0
}

function main() {
    logInfo "Starting install script: ${logTag}"
    verify_prerequisites
    if [ $? -ne 0 ]; then logErr "Problem verifying prerequisites"; return 1; fi
    install_java
    if [ $? -ne 0 ]; then logErr "Problem installing java or its prerequisites"; return 2; fi
    install_screen
    if [ $? -ne 0 ]; then logErr "Problem installing screen"; return 3; fi
    create_minecraft_users
    if [ $? -ne 0 ]; then logErr "Problem creating the minecraft user"; return 4; fi
    create_directories
    create_config_file
    download_minecraft_server
    if [ $? -ne 0 ]; then logErr "Problem downloading minecraft server"; return 5; fi
    run_minecraft_server
    if [ $? -ne 0 ]; then logErr "Problem running minecraft server"; return 6; fi
    install_management_scripts
    if [ $? -ne 0 ]; then logErr "Problem installing management scripts"; return 7; fi
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
