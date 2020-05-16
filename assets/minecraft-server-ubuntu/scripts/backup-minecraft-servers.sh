#!/usr/bin/env bash

# Source the environment
if [ -f /etc/bashrc ] ; then
    . /etc/bashrc
fi
if [ -f /etc/profile ] ; then
    . /etc/profile
fi

# Establish a log file and log tag
logTag="backup-minecraft"
logDir="/var/log/minecraft"
logFile="${logDir}/${logTag}-$(date "+%Y%m%d-%H%M%S").log"

######################### GLOBAL VARIABLES #########################

# Minecraft directories
minecraftServerDir="/opt/Minecraft_Servers"
worldsDir="${minecraftServerDir}/worlds"

# Command paths
awsCmd="/usr/local/bin/aws"
slackCmd="/usr/local/bin/slack"

# Directories
yennacraftRoot="/root/.yennacraft"
backupDir="${memvaultDir}/backup"

####################### END GLOBAL VARIABLES #######################

# Logging functions
function timestamp() { /bin/date "+%F %T"; }
function timestamp_formatted() { /bin/date "+%F_%H%M%S"; }
function logInfo() { /bin/echo -e "$(timestamp) ${logTag} [INFO]: ${1}" >> ${logFile}; }
function logWarn() { /bin/echo -e "$(timestamp) ${logTag} [WARN]: ${1}" >> ${logFile}; }
function logErr() { /bin/echo -e "$(timestamp) ${logTag} [ERROR]: ${1}" >> ${logFile}; }

function report_error() {

logErr "${1}"

${slackCmd} \
--url="${slack_url}" \
--channel="#minecraft" \
--text="Minecraft World Backup" \
--color=danger \
--attachment="${1}"

}

function report_success() {

logInfo "${1}"

${slackCmd} \
--url="${slack_url}" \
--channel="#minecraft" \
--text="Minecraft World Backup" \
--color=good \
--attachment="${1}"

}

function verify_prerequisites() {
    logInfo "Verifying prerequisites..."

    # Ensure the AWS config and credential files exist
    awsDir="/root/.aws"
    awsConfigFile="${awsDir}/config"
    awsCredentialsFile="${awsDir}/credentials"
    if [ ! -f ${awsConfigFile} ]; then
        logErr "AWS config file not found: ${awsConfigFile}"
        return 2
    fi
    if [ ! -f ${awsCredentialsFile} ]; then
        logErr "AWS credentials file not found: ${awsCredentialsFile}"
        return 3
    fi

    logInfo "Prerequisites verified!"
    return 0
}

function compress_file() {
    file_to_compress="${1}"
    if [ -z ${file_to_compress} ]; then
        logErr "Path to file not provided"
        return 1
    fi
    cd ${backupDir}
    if [ ! -f ${file_to_compress} ]; then
        logErr "File to compress not found: ${file_to_compress}"
        return 2
    fi
    compressed_file_path="${file_to_compress}.${compressedFileExt}"
    logInfo "Creating tarball archive: ${compressed_file_path}"
    /bin/tar -cvzf ${compressed_file_path} ${file_to_compress} >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then
        logErr "There was a problem creating tar archive: ${compressed_file_path}"
        return 1
    fi
    logInfo "Created compressed file: ${compressed_file_path}"
    return 0
}

function backup_to_s3() {
    file_to_upload="${1}"
    if [ -z ${file_to_upload} ]; then
        logErr "Path to file not provided"
        return 1
    fi
    if [ ! -f ${file_to_upload} ]; then
        logErr "File to upload not found: ${file_to_upload}"
        return 2
    fi
    logInfo "Copying backup file to AWS S3..."
    ${awsCmd} s3 cp ${file_to_upload} s3://${s3bucket}/ >> ${logFile} 2>&1
    if [ $? -ne 0 ]; then
        logErr "There was a problem backing up the file to AWS S3"
        return 3
    fi
    logInfo "File backed up successfully to AWS S3: ${file_to_upload}"
    return 0
}

function main() {
    report_success "Running memvault database backup..."

    # Create the backup directory
    if [ ! -d ${backupDir} ]; then
        logInfo "Creating backup directory: ${backupDir}"
        mkdir -p ${backupDir} >> ${logFile} 2>&1
    fi

    # Track 0=success, non-zero=failure
    res=0



    # Report completion to Slack
    if [ ${res} -eq 0 ]; then
        report_success "All backups completed successfully!"
    else
        report_error "Backups completed but with an error!"
    fi
    return ${res}
}

# Set up the log file
/bin/mkdir -p ${logDir}
/bin/chmod 700 ${logDir}
/bin/touch ${logFile}
/bin/chmod 644 ${logFile}

main
result=$?

logInfo "Exiting with code ${result} ..."
exit ${result}
