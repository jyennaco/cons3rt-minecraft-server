#!/bin/bash
. common.sh
serverVersion="${1}"
if [ -z "${serverVersion}" ]; then logErr "Please provide the server version"; exit 1; fi
logTag="install-server-versions"
logInfo "Installing Server version: ${serverVersion}"
install_server_version "${serverVersion}"
exit $?
