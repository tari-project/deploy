#!/bin/bash

set -ea
SCRIPT_DIR=$(pwd)
# Main deployment script for new Tari releases
DATE=$(date +%Y-%m-%d)

# Checks that a file named $1-version.txt exists
function check_release_notes() {
  if [[ ! -e $1 ]]; then
    echo "Missing release notes: ${1}. Update the file and try again"
    exit 1
  fi
}

function edit() {
  file="notes-${1}-${2}.txt"
  vim ${file}
}

function confirm_metadata() {
  echo "Metatdata for release ${1}"
  echo "Android code: ${ANDROID_CODE}"
  echo "Android version: ${ANDROID_VERSION}"
  echo "JNI Libs version: ${JNI_VERSION}"
  echo "Release Notes (Android):"
  cat "notes-Android-${1}.txt"
  echo "Release Notes (iOS):"
  cat "notes-iOS-${1}.txt"
  echo "Release Notes (Base):"
  cat "notes-Base-${1}.txt"
  read -p "Do you wish to continue? " yn
  case $yn in
  [Yy]*) ;;
  *) exit 2 ;;
  esac
}

# pull_latest_code repo branch/tag
function pull_latest_code() {
  echo "Pulling code for $1/$2"
  cd $1
  git checkout $2
  git pull origin $2
  cd $SCRIPT_DIR
}

function build_ffi_libs() {
  echo "Building FF libraries"
}

function tag() {
  echo "Tagging $1 with $2"
  cd $1
  git tag "$2" || true # Don't freak out if tag already exists
  git push origin $2
  cd $SCRIPT_DIR
}

function calculate_hashes() {
  echo "Calculating hashes"
}

function update_android_version_info() {
  ver_string=v${ANDROID_VERSION}-jniLibs-${JNI_VERSION}
  # update strings.xml
  sed -i "s|<string name=\"testnet\">TESTNET .*</string>|<string name=\"testnet\">TESTNET ${ver_string}</string>|" "${ANDROID_STRINGS}"
  # update build.gradle
  sed -i -e "s|versionCode .*|versionCode ${ANDROID_CODE}|" -e "s|versionName \".*\"|versionName \"${ver_string}\"|" "${ANDROID_GRADLE}"
  # update change logs
  sed -i -e "2rnotes-Android-${1}.txt" -e "2i## [${ver_string}] - ${DATE}" "${ANDROID_RELNOTES_FILE}"
  # Create and push a new commit
  git add "${ANDROID_STRINGS}" "${ANDROID_GRADLE}" "${ANDROID_RELNOTES_FILE}"
  git commit -m "Bump version to ${ver_string}"
  git push origin development
  # Tag the release
  cd ${ANDROID_WALLET_REPO}
  git tag -a "${ver_string}" --file "${SCRIPT_DIR}/notes-Android-${1}.txt"
  git push origin "${ver_string}"
  cd ${SCRIPT_DIR}
}

# Compute libwallet hashes and copy the bundles to the tari website staging area
function stage_libwallet() {
  ./libwallet_hashes.sh ${JNI_VERSION}
  cd ${SCRIPT_DIR}
}

function deploy_tari_webite() {
  cd ${TARI_WEBSITE_REPO}
  echo "Deploying to tari.com"
  #  ./deploy.sh production
  cd ${SCRIPT_DIR}
}

function deploy_android() {
  echo "Building and deploying Android app"
}

function build_and_stage_ios_installer() {
  echo "iOS installer not implemented yet"
}

function build_and_stage_ubuntu() {
  echo "Ubuntu tarball not implemented yet"
}

function build_and_stage_windows() {
  echo "Ubuntu tarball not implemented yet"
}

function notify_people() {
  echo "Letting everyone knpow we're ready"
}
#------------------------ Main Script -----------------------------#

# Update source
version=$1
if [[ -z ${version} ]]; then
  echo deploy.sh VERSION
  exit 1
fi
source .env
metadata=versiondata-${1}.env
source ${metadata}

# Collect all the info we need from the user
edit Android ${version}
edit iOS ${version}
edit Base ${version}
confirm_metadata ${version}

pull_latest_code ${TARI_REPO} development
pull_latest_code ${ANDROID_WALLET_REPO} development
pull_latest_code ${ANDROID_WALLET_REPO} development
update_android_version_info ${version}
# FFi library build tag and stage
build_ffi_libs
tag ${TARI_REPO} libwallet-${JNI_VERSION}
stage_libwallet
deploy_tari_webite
deploy_android
build_and_stage_ios_installer
build_and_stage_ubuntu
build_and_stage_windows
notify_people