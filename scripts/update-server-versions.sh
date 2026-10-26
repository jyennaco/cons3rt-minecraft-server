#!/bin/bash
#
# update-server-versions.sh
#
# Adds the latest Minecraft release and snapshot from Mojang to server-versions.sh, and sets
# latestRelease and latestSnapshot. Run it in a checkout of this repo, then review and commit:
#
#     ./scripts/update-server-versions.sh
#     git diff scripts/server-versions.sh
#
# Usage:
#     ./scripts/update-server-versions.sh [path to server-versions.sh]
#
# The path defaults to the server-versions.sh next to this script.
#
# Requires curl and jq. Works with the macOS and the Linux versions of sed and awk, and with bash 3.
#
# Reference: https://minecraft.wiki/w/Version_manifest.json
#

manifestUrl='https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'

scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
versionsFile="${1:-${scriptDir}/server-versions.sh}"

logTag='update-server-versions'
function timestamp() { date "+%F %T"; }
function logInfo() { echo -e "$(timestamp) ${logTag} [INFO]: ${1}"; }
function logErr() { echo -e "$(timestamp) ${logTag} [ERROR]: ${1}" >&2; }
function die() { logErr "${1}"; exit 1; }

# fetch_latest <release|snapshot> <manifest>: print "id<TAB>server url<TAB>java major"
function fetch_latest() {
    local kind="${1}" manifest="${2}" id metaUrl meta
    id=$(jq -r ".latest.${kind}" <<< "${manifest}")
    metaUrl=$(jq -r --arg id "${id}" '.versions[] | select(.id == $id) | .url' <<< "${manifest}")
    if [ -z "${id}" ] || [ -z "${metaUrl}" ]; then return 1; fi
    meta=$(curl -fsS -m 60 "${metaUrl}") || return 1
    printf '%s\t%s\t%s\n' "${id}" "$(jq -r '.downloads.server.url' <<< "${meta}")" "$(jq -r '.javaVersion.majorVersion' <<< "${meta}")"
}

# add_version_entry <section comment> <version> <url>: add a version at the end of a section
function add_version_entry() {
    local section="${1}" id="${2}" url="${3}"
    if grep -qF "serverDownloadUrls['${id}']=" "${versionsFile}"; then
        logInfo "${id} is already in ${versionsFile}"
        return 0
    fi
    local entry="serverDownloadUrls['${id}']='${url}'" tmpFile
    tmpFile=$(mktemp)
    SECTION="${section}" ENTRY="${entry}" awk '
        $0 == ENVIRON["SECTION"] { inSection = 1; print; next }
        inSection && $0 == "" { print ENVIRON["ENTRY"]; inSection = 0; added = 1 }
        { print }
        END { if (inSection && !added) print ENVIRON["ENTRY"] }
    ' "${versionsFile}" > "${tmpFile}" && cat "${tmpFile}" > "${versionsFile}"
    rm -f "${tmpFile}"
    grep -qF "${entry}" "${versionsFile}" || die "Could not add ${id} to ${versionsFile}, the section '${section}' was not found"
    logInfo "Added ${id} under '${section}'"
}

# set_latest <latestRelease|latestSnapshot> <version>: set the variable in the file
function set_latest() {
    local variable="${1}" id="${2}" tmpFile
    tmpFile=$(mktemp)
    sed -e "s|^${variable}=.*|${variable}='${id}'|" "${versionsFile}" > "${tmpFile}" && cat "${tmpFile}" > "${versionsFile}"
    rm -f "${tmpFile}"
    grep -qF "${variable}='${id}'" "${versionsFile}" || die "The ${variable} line was not found in ${versionsFile}"
    logInfo "Set ${variable}='${id}'"
}

logInfo "Updating ${versionsFile}..."
if [ ! -f "${versionsFile}" ]; then die "File not found: ${versionsFile}"; fi
for cmd in curl jq; do
    if ! command -v "${cmd}" > /dev/null; then die "Required command not found: ${cmd}"; fi
done

manifest=$(curl -fsS -m 60 "${manifestUrl}")
if [ -z "${manifest}" ]; then die "Unable to get ${manifestUrl}"; fi

releaseInfo=$(fetch_latest release "${manifest}") || die "Unable to get the latest release from Mojang"
snapshotInfo=$(fetch_latest snapshot "${manifest}") || die "Unable to get the latest snapshot from Mojang"

IFS=$'\t' read -r releaseId releaseUrl releaseJava <<< "${releaseInfo}"
IFS=$'\t' read -r snapshotId snapshotUrl snapshotJava <<< "${snapshotInfo}"

# These end up in sed and awk expressions, keep them to plain characters
for value in "${releaseId}" "${snapshotId}"; do
    [[ "${value}" =~ ^[A-Za-z0-9._-]+$ ]] || die "Unexpected version from Mojang: ${value}"
done
for value in "${releaseUrl}" "${snapshotUrl}"; do
    [[ "${value}" =~ ^https://[A-Za-z0-9._/-]+$ ]] || die "Unexpected server URL from Mojang: ${value}"
done

add_version_entry '# Snapshots' "${snapshotId}" "${snapshotUrl}"
add_version_entry '# Releases' "${releaseId}" "${releaseUrl}"
set_latest latestSnapshot "${snapshotId}"
set_latest latestRelease "${releaseId}"

logInfo "Latest release: ${releaseId} (needs Java ${releaseJava}), latest snapshot: ${snapshotId} (needs Java ${snapshotJava})"
logInfo "Done, review the changes with: git diff ${versionsFile}"
exit 0
