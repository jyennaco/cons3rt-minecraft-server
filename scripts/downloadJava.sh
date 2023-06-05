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
#     ./scripts/downloadJava.sh
#

logInfo "Downloading java..."
javaDir='/opt/java'
javaSymlink="${javaDir}/jre"
profileScript='/etc/profile.d/java.sh'

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
feature_version='17'
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

# Get the specific version
specificVersion=$(echo "${fileName}" | awk -F _ '{print $5}')
specificVersionModifier=$(echo "${fileName}" | awk -F _ '{print $6}' | awk -F . '{print $1}')
versionDirectoryName="jdk-${specificVersion}+${specificVersionModifier}-jre"

logInfo "Found specific version: ${specificVersion}"
logInfo "Found specific version modifier: ${specificVersionModifier}"
logInfo "Computed java directory name: ${versionDirectoryName}"

# Ensure the version directory was found
versionDirectory="${javaDir}/${versionDirectoryName}"
if [ ! -d ${versionDirectory} ]; then logErr "Java version directory not found: ${versionDirectory}"; exit 1; fi

# Create the symlink
if [ -e ${javaSymlink} ]; then
    logInfo "Removing existing symlink: ${javaSymlink}"
    rm -f ${javaSymlink}
fi
logInfo "Creating new java symlink [${javaSymlink}] pointing to: ${versionDirectory}"
ln -sf ${versionDirectory} ${javaSymlink}
if [ $? -ne 0 ]; then logErr "Problem creating java symlink: ${javaSymlink} to directory: ${versionDirectory}"; exit 1; fi

# Create the java profile.d script
logInfo "Creating java profile.d script: ${profileScript}"
echo 'export JAVA_HOME=/opt/java/jre' > ${profileScript}
echo 'export PATH=${JAVA_HOME}/bin:${PATH}' >> ${profileScript}
. ${profileScript}

logInfo "Completed downloading and installing Java successfully!"

cd -
exit 0
