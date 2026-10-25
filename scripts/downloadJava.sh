#!/bin/bash
#
# downloadJava.sh
#
# This script downloads java binaries for this directory using the binary API download from Adoptium
#
# https://api.adoptium.net/v3/binary/latest/{feature_version}/{release_type}/{os}/{arch}/{image_type}/{jvm_impl}/{heap_size}/{vendor}
#
# Reference: https://api.adoptium.net/q/swagger-ui/#/Binary/getBinary
#
# Usage:
#     ./scripts/downloadJava.sh [javaMajorVersion]
#
# Arguments:
#     javaMajorVersion    Java major (feature) version to download, defaults to 25
#
# Java is downloaded and extracted to ${HOME}/java
#

. /opt/Minecraft_Servers/scripts/common.sh

logInfo "Downloading java..."
javaDir="${HOME}/java"
javaSymlink="${javaDir}/jre"

# Java major version, defaults to 25
javaMajorVersion="${1:-25}"
javaVersionSymlink="${javaDir}/jre${javaMajorVersion}"

if [ ! -d ${javaDir} ]; then
    logInfo "Creating java directory: ${javaDir}"
    mkdir -p ${javaDir}
fi
logInfo "Using java directory: ${javaDir}"
cd ${javaDir}

# Array of query strings to download
queryStrings=()

# Java file name
fileName=

# Script exit code
res=0

# Base URL
baseUrl="https://api.adoptium.net/v3/binary/latest"

# Parameters for Linux x64
feature_version="${javaMajorVersion}"
release_type='ga'
os='linux'
arch='x64'
image_type='jre'
jvm_impl='hotspot'
heap_size='normal'
vendor='eclipse'

# Query String for Linux x64
queryStringLinuxX64="${feature_version}/${release_type}/${os}/${arch}/${image_type}/${jvm_impl}/${heap_size}/${vendor}"
queryStrings+=("${queryStringLinuxX64}")

# Download the binaries using the provided query strings
for queryString in "${queryStrings[@]}"; do
    apiUrl="${baseUrl}/${queryString}"
    fileName=$(curl -sI ${apiUrl} | grep 'Location' | awk '{print $2}' | awk -F / '{print $NF}' | tr -d '\r')
    existingFile="${javaDir}/${fileName}"
    logInfo "Checking for existing file: [${existingFile}]"
    if [ -f ${existingFile} ]; then
        logInfo "Found file already downloaded: ${existingFile}"
        continue
    fi
    logInfo "Downloading Java binary from URL: ${apiUrl}"
    curl -OJL ${apiUrl}
    if [ $? -ne 0 ]; then
        logInfo "ERROR: Unable to download java binary from URL: ${apiUrl}"
        res=1
    else
        logInfo "Java download completed from URL: ${apiUrl}"
    fi
done

# Exit with a non-zero code if errors encountered
if [ ${res} -ne 0 ]; then
    logErr "ERROR: Completed downloading Java binaries with errors!"
    exit 1
fi

# Extract the tar.gz file
logInfo "Extracting java file: ${fileName}"
tar -xvzf ${fileName}
if [ $? -ne 0 ]; then logErr "Problem extracting the downloaded java file: ${fileName}"; exit 1; fi

# Get the directory the archive extracted to, read from the archive because its name differs
# by version: jdk-25.0.5+8-jre, jdk-11.0.32.1+1-jre, but jdk8u504-b01-jre for Java 8
versionDirectoryName=$(tar -tzf ${fileName} | head -n 1 | cut -d/ -f1)
if [ -z "${versionDirectoryName}" ]; then logErr "Unable to determine the java directory name from the archive: ${fileName}"; exit 1; fi
logInfo "Found java directory name in the archive: ${versionDirectoryName}"

# Ensure the version directory was found
versionDirectory="${javaDir}/${versionDirectoryName}"
if [ ! -d ${versionDirectory} ]; then logErr "Java version directory not found: ${versionDirectory}"; exit 1; fi

# Create the generic and version-specific symlinks
for symlink in "${javaSymlink}" "${javaVersionSymlink}"; do
    if [ -e ${symlink} ] || [ -L ${symlink} ]; then
        logInfo "Removing existing symlink: ${symlink}"
        rm -f ${symlink}
    fi
    logInfo "Creating new java symlink [${symlink}] pointing to: ${versionDirectory}"
    ln -sf ${versionDirectory} ${symlink}
    if [ $? -ne 0 ]; then logErr "Problem creating java symlink: ${symlink} to directory: ${versionDirectory}"; exit 1; fi
done

logInfo "Completed downloading and installing Java successfully!"

cd -
exit 0
