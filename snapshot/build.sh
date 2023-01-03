#!/bin/bash

if [ ! -f pyhomer3/VERSION.txt ]; then
  echo "Please run from the top-level directory of the homer source code"
  exit 1
fi
workingDir=$(pwd)

function timestamp_formatted() { date "+%F_%H%M%S"; }
version=$(cat pyhomer3/VERSION.txt)
cons3rtBaseVersion=$(echo ${version} | awk -F - '{print $1}')
imageName='homer'
parentDir="${HOME}/Downloads"
binDir="${HOME}/bin"
homerBinDir="${binDir}/homer"
srcDir="${binDir}/homer/src"
ottoSrcDir="${srcDir}/otto"
homerSecretsDir="${homerBinDir}/secrets"
homerMediaDir="${homerBinDir}/media"
sourceAssetDir="./asset/container-asset"
assetPropertiesFile="${sourceAssetDir}/asset.properties"
licenseFile="${sourceAssetDir}/LICENSE"
readmeFile="${sourceAssetDir}/README.md"
assetDataYml="${sourceAssetDir}/asset_data.yml"
ottoDefaultBranch='develop'

all="${1}"
if [ -z "${all}" ]; then all=no; fi

if [ ! -d ${parentDir} ]; then echo "parentDir does not exist: ${parentDir}"; exit 1; fi
if [ ! -d ${sourceAssetDir} ]; then echo "source asset directory does not exist: ${sourceAssetDir}"; exit 1; fi
if [ ! -f ${assetPropertiesFile} ]; then echo "Missing asset.properties file: ${assetPropertiesFile}"; exit 1; fi
if [ ! -f ${licenseFile} ]; then echo "Missing LICENSE file: ${licenseFile}"; exit 1; fi
if [ ! -f ${readmeFile} ]; then echo "Missing README.md file: ${readmeFile}"; exit 1; fi
if [ ! -f ${assetDataYml} ]; then echo "Missing asset_data.yml file: ${assetDataYml}"; exit 1; fi

imageTag="${version}"
imageNameWithTag="${imageName}:${imageTag}"
imageTarFileName="${imageName}.tar"
tmpAssetDir="${parentDir}/${imageName}_${imageTag}_$(timestamp_formatted)"
imageExportPath="${parentDir}/${imageTarFileName}"
imageTarFilePath="${tmpAssetDir}/media/${imageTarFileName}"


function cleanup() {
    if [ -d ${tmpAssetDir} ]; then echo "Cleaning up: ${tmpAssetDir}"; rm -Rf ${tmpAssetDir}; fi
    if [ -d ./otto ]; then echo "Cleaning up the otto directory"; rm -Rf ./otto; fi
}
cleanup

if [ -z "${tmpAssetDir}" ]; then echo "tmpAssetDir not set, exiting"; exit 1; fi

echo "Staging files for the image build..."

# Checkout the proper otto version for staging
mkdir ./otto
cd ${ottoSrcDir}/
echo "pulling otto from git..."
git pull
ottoBranch="${ottoDefaultBranch}"
ottoReleaseBranch="release-$(cut -d '.' -f -2 <<< ${cons3rtBaseVersion})"
echo "Checking for branch: ${ottoReleaseBranch}"
branchCheck=$(git branch -a | grep ${ottoReleaseBranch})
if [ -z "${branchCheck}" ]; then
  echo "No release branch found for: ${ottoReleaseBranch}"
else
  echo "Found release branch: ${branchCheck}"
  ottoBranch="${ottoReleaseBranch}"
fi
echo "Checking out otto branch: ${ottoBranch}"
git checkout ${ottoBranch}
if [ $? -ne  0 ]; then echo "Problem checking out Otto branch: ${ottoBranch}"; cleanup; exit 2; fi
git pull --rebase
if [ $? -ne  0 ]; then echo "Problem pulling Otto branch: ${ottoBranch}"; cleanup; exit 2; fi

cd ${workingDir}/
rsync -a ${ottoSrcDir}/* ./otto/
if [ $? -ne  0 ]; then echo "Problem staging otto for the image build"; cleanup; exit 2; fi

echo "Attempting to build Homer container image for version: ${version}"

echo "Building image: ${imageNameWithTag} ..."
docker build -t ${imageNameWithTag} .
if [ $? -ne  0 ]; then echo "Problem building image [${imageNameWithTag}]"; cleanup; exit 2; fi
echo "Image build complete: [${imageNameWithTag}]"

if [[ ${all} == "all" ]]; then
    echo "all arg was specified, updating asset..."
else
    read -p "Export the image tar file? (y/n) " do_asset
    if [[ ${do_asset} == "y" ]]; then
        :
    else
        cleanup
        exit 0
    fi
fi

echo "Creating local asset in directory: ${tmpAssetDir}"
if [ -d ${tmpAssetDir} ]; then rm -Rf ${tmpAssetDir}; fi
mkdir -p ${tmpAssetDir}
if [ $? -ne  0 ]; then echo "Problem making directory: ${tmpAssetDir}"; cleanup; exit 2; fi

echo "Saving image [${imageNameWithTag}] to: ${imageExportPath}"
docker save -o ${imageExportPath} ${imageNameWithTag}
if [ $? -ne  0 ]; then
    echo "Problem saving image [${imageNameWithTag}] to file: ${imageExportPath}"
    cleanup
    exit 3
fi

if [[ ${all} == "all" ]]; then
    echo "all arg was specified, updating asset..."
else
    read -p "Zip exported image into a container asset zip file? (y/n) " do_asset
    if [[ ${do_asset} == "y" ]]; then
        :
    else
        cleanup
        exit 0
    fi
fi

echo "Staging asset properties, LICENSE, and README files..."
cp -f ${assetPropertiesFile} ${tmpAssetDir}/
if [ $? -ne  0 ]; then echo "Problem staging asset.properties"; cleanup; exit 4; fi
sed -i~ "s|REPLACE_IMAGE_TAR_FILE|${imageTarFileName}|g" ${tmpAssetDir}/asset.properties
sed -i~ "s|REPLACE_VERSION|${version}|g" ${tmpAssetDir}/asset.properties
if [ -f ${tmpAssetDir}/asset.properties~ ]; then rm -f ${tmpAssetDir}/asset.properties~; fi

cp -f ${licenseFile} ${tmpAssetDir}/
if [ $? -ne  0 ]; then echo "Problem staging LICENSE"; cleanup; exit 5; fi

cp -f ${readmeFile} ${tmpAssetDir}/
if [ $? -ne  0 ]; then echo "Problem staging README.md"; cleanup; exit 6; fi

if [ -f ${assetDataYml} ]; then
    cp -f ${assetDataYml} ${tmpAssetDir}/
    if [ $? -ne  0 ]; then echo "Problem staging asset_data.yml"; cleanup; exit 7; fi
fi

mkdir -p ${tmpAssetDir}/media
if [ -f ${imageExportPath} ]; then
    mv ${imageExportPath} ${imageTarFilePath}
    if [ $? -ne  0 ]; then echo "Problem staging image tar file"; cleanup; exit 8; fi
fi

read -p "Import new (n), update (u), or just leave the zip (z)? (n/u/z) " upload_type
if [[ ${upload_type} == "n" ]]; then
  echo "Importing new asset from: ${tmpAssetDir}"
  asset import --asset_dir=${tmpAssetDir}
elif [[ ${upload_type} == "u" ]]; then
  echo "Updating the asset from: ${tmpAssetDir}"
  asset update --asset_dir=${tmpAssetDir}
elif [[ ${upload_type} == "z" ]]; then
  echo "Creating asset zip from: ${tmpAssetDir}"
  asset create --asset_dir=${tmpAssetDir}
else
    cleanup
    exit 0
fi

if [ $? -ne  0 ]; then echo "Failed to import/update/create asset from directory: ${tmpAssetDir}"; cleanup; exit 9; fi
cleanup
echo "Completed building the container asset from image: ${imageName}"
exit 0
