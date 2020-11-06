#!/bin/bash

###
# This script expects 3 input variables:
#  - intellij-plugin-verifier version
#  - relative plugin path
#  - new-line separated IDE + version
#
# See below for examples of these inputs.
#
# This script expects the following CLI tools be available:
#   - curl
#   - jq
#
# NOTE: This script works with GitHub Actions Debug Logging. Read more about it here: https://help.github.com/en/actions/configuring-and-managing-workflows/managing-a-workflow-run#enabling-step-debug-logging
#       To enable, set the following secret in the repository that contains the workflow using this action:
#             - ACTIONS_STEP_DEBUG to true
###

set -eu

##
# GitHub Debug Function
##
gh_debug() {
  if [[ "$#" -eq 0 ]] ; then
    while read line; do
      echo "::debug::${line}"
    done
  else
    echo "::debug::${1}"
  fi
}

##
# Input Variables
##

# verifier-version: '1.231'
INPUT_VERIFIER_VERSION="$1"

# plugin-location: 'build/distributions/sample-intellij-plugin-*'
INPUT_PLUGIN_LOCATION="$2"

# Found from: https://www.jetbrains.com/intellij-repository/releases/
#
# ideaIU:2019.3.4    -> https://www.jetbrains.com/intellij-repository/releases/com/jetbrains/intellij/idea/ideaIU/2019.3.4/ideaIU-2019.3.4.zip
# ideaIC:2019.3.4    -> https://www.jetbrains.com/intellij-repository/releases/com/jetbrains/intellij/idea/ideaIC/2019.3.4/ideaIC-2019.3.4.zip
# pycharmPC:2019.3.4 -> https://www.jetbrains.com/intellij-repository/releases/com/jetbrains/intellij/pycharm/pycharmPC/2019.3.4/pycharmPC-2019.3.4.zip
# goland:2019.3.3    -> https://www.jetbrains.com/intellij-repository/releases/com/jetbrains/intellij/goland/goland/2019.3.3/goland-2019.3.3.zip
# clion:2019.3.4     -> https://www.jetbrains.com/intellij-repository/releases/com/jetbrains/intellij/clion/clion/2019.3.4/clion-2019.3.4.zip
#
# Easy way to simulate the input:
#
#   INPUT_IDE_VERSIONS=$(
#     cat <<-END
#       ideaIU:2019.3.4
#       ideaIC:2019.3.4
#       pycharmPC:2019.3.4
#       goland:2019.3.3
#       clion:2019.3.4
#   END
#   )
#
# ide-versions: ['ideaIU:2019.3.4','ideaIC:2019.3.4','pycharmPC:2019.3.4','goland:2019.3.3','clion:2019.3.4']
INPUT_IDE_VERSIONS="$3"

gh_debug "INPUT_VERIFIER_VERSION => $INPUT_VERIFIER_VERSION"
gh_debug "INPUT_PLUGIN_LOCATION => $INPUT_PLUGIN_LOCATION"
gh_debug "INPUT_IDE_VERSIONS =>"
echo "$INPUT_IDE_VERSIONS" | while read -r INPUT_IDE_VERSION; do
gh_debug "                   => $INPUT_IDE_VERSION"
done

# If the user passed in a file instead of a list, pull the IDE+version combos from the file and use that instead.
if [[ -f "$GITHUB_WORKSPACE/$INPUT_IDE_VERSIONS" ]]; then
  gh_debug "$INPUT_IDE_VERSIONS is a file. Extracting file contents into variable."
  INPUT_IDE_VERSIONS=$(cat "$INPUT_IDE_VERSIONS")
  gh_debug "INPUT_IDE_VERSIONS =>"
  echo "$INPUT_IDE_VERSIONS" | while read -r INPUT_IDE_VERSION; do
    gh_debug "                   => $INPUT_IDE_VERSION"
  done
fi

##
# Resolve verifier values
##
if [[ "$INPUT_VERIFIER_VERSION" == "LATEST" ]]; then
    gh_debug "LATEST verifier version found, resolving version..."
    GH_LATEST_RELEASE_FILE="$HOME/intellij-plugin-verifier_latest_gh_release.json"
    curl -s https://api.github.com/repos/JetBrains/intellij-plugin-verifier/releases/latest > "$GH_LATEST_RELEASE_FILE"
    VERIFIER_VERSION=$(cat "$GH_LATEST_RELEASE_FILE" | jq -r .tag_name | sed 's/[^[:digit:].]*//g')
    VERIFIER_DOWNLOAD_URL=$(cat "$GH_LATEST_RELEASE_FILE" | jq -r .assets[].browser_download_url)
    VERIFIER_JAR_FILENAME=$(cat "$GH_LATEST_RELEASE_FILE" | jq -r .assets[].name)
else
    gh_debug "Using verifier version [$INPUT_VERIFIER_VERSION]..."

    VERIFIER_VERSION=${INPUT_VERIFIER_VERSION}
    VERIFIER_DOWNLOAD_URL="https://dl.bintray.com/jetbrains/intellij-plugin-service/org/jetbrains/intellij/plugins/verifier-cli/$INPUT_VERIFIER_VERSION/$VERIFIER_JAR_FILENAME"
    # The filename of the `verifier-cli-*-all.jar` file
    VERIFIER_JAR_FILENAME="verifier-cli-$VERIFIER_VERSION-all.jar"
fi

# The full path of the `verifier-cli-*-all.jar` file
VERIFIER_JAR_LOCATION="$HOME/$VERIFIER_JAR_FILENAME"

gh_debug "VERIFIER_VERSION => $VERIFIER_VERSION"
gh_debug "VERIFIER_DOWNLOAD_URL => $VERIFIER_DOWNLOAD_URL"
gh_debug "VERIFIER_JAR_FILENAME => $VERIFIER_JAR_FILENAME"
gh_debug "VERIFIER_JAR_LOCATION => $VERIFIER_JAR_LOCATION"

##
# Other Variables
##

# Set the correct JAVA_HOME path for the container because this is overwritten by the setup-java action.
# We use the docker image `openjdk:8-jdk-alpine` - https://hub.docker.com/layers/openjdk/library/openjdk/8-jdk-alpine/images/sha256-210ecd2595991799526a62a7099718b149e3bbefdb49764cc2a450048e0dd4c0?context=explore
#  and pull the `JAVA_HOME` property from it's image (ie, its definition has `ENV JAVA_HOME=/usr/lib/jvm/java-1.8-openjdk`).
JAVA_HOME="/usr/lib/jvm/java-1.8-openjdk"

# The location of the plugin
PLUGIN_LOCATION="$GITHUB_WORKSPACE/$INPUT_PLUGIN_LOCATION"

gh_debug "VERIFIER_JAR_FILENAME => $VERIFIER_JAR_FILENAME"
gh_debug "VERIFIER_JAR_LOCATION => $VERIFIER_JAR_LOCATION"
gh_debug "PLUGIN_LOCATION => $PLUGIN_LOCATION"

# Variable to store the string of IDE tmp_ide_directories we're going to use for verification.
IDE_DIRECTORIES=""

##
# Functions
##
release_type_for() {
  # release_type_for "2019.3-EAP-SNAPSHOT" -> 'snapshots'
  # release_type_for "2019.3-SNAPSHOT" -> 'nightly'
  # release_type_for "2019.3" -> 'releases'
  case $1 in
  *-EAP-SNAPSHOT | *-EAP-CANDIDATE-SNAPSHOT | *-CUSTOM-SNAPSHOT)
    echo "snapshots"
    return
    ;;
  *-SNAPSHOT)
    echo "nightly"
    return
    ;;
  *)
    echo "releases"
    return
    ;;
  esac
}

##
# Setup
##

echo "Downloading plugin verifier [version '$INPUT_VERIFIER_VERSION'] from [$VERIFIER_DOWNLOAD_URL] to [$VERIFIER_JAR_LOCATION]..."
curl -L --output "$VERIFIER_JAR_LOCATION" "$VERIFIER_DOWNLOAD_URL"

# temp file for storing IDE Directories we download and unzip
tmp_ide_directories="/tmp/ide_directories.txt"

echo "Processing all IDE versions..."
echo "$INPUT_IDE_VERSIONS" | while read -r IDE_VERSION; do
  echo "Processing IDE:Version = \"$IDE_VERSION\""
  if [ -z "$IDE_VERSION" ]; then
    gh_debug "IDE_VERSION is empty; continuing with next iteration."
    break
  fi

  # IDE = ideaIU, ideaIC, pycharmPC, goland, clion, etc.
  IDE=$(echo "$IDE_VERSION" | cut -f1 -d:)

  # IDE_DIR = idea, pycharm, goland, clion, etc.
  IDE_DIR=$(echo "$IDE" | grep -E -o "^[[:lower:]]+")

  # VERSION = 2019.3, 2019.3.4, 193.6911.18 (ideaIC) - pulled from the `Version` column of https://www.jetbrains.com/intellij-repository/releases/
  VERSION=$(echo "$IDE_VERSION" | cut -f2 -d:)

  # RELEASE_TYPE = snapshots, nightly, releases
  RELEASE_TYPE=$(release_type_for "$VERSION")

  DOWNLOAD_URL="https://www.jetbrains.com/intellij-repository/$RELEASE_TYPE/com/jetbrains/intellij/$IDE_DIR/$IDE/$VERSION/$IDE-$VERSION.zip"

  ZIP_FILE_PATH="$HOME/$IDE-$VERSION.zip"

  echo "Downloading [$DOWNLOAD_URL] into [$ZIP_FILE_PATH]..."
  curl -L --output "$ZIP_FILE_PATH" "$DOWNLOAD_URL"

  IDE_EXTRACT_LOCATION="$HOME/ides/$IDE-$VERSION"
  echo "Extracting [$ZIP_FILE_PATH] into [$IDE_EXTRACT_LOCATION]..."
  mkdir -p "$IDE_EXTRACT_LOCATION"
  unzip -q -d "$IDE_EXTRACT_LOCATION" "$ZIP_FILE_PATH"

  gh_debug "Removing [$ZIP_FILE_PATH] to save storage space..."
  rm "$ZIP_FILE_PATH"

  # Append the extracted location to the variable of IDEs to validate against.
  gh_debug "Adding $IDE_EXTRACT_LOCATION to '$tmp_ide_directories'..."
  printf "%s " "$IDE_EXTRACT_LOCATION" >>$tmp_ide_directories
done

##
# Print ENVVARs for debugging.
##
gh_debug "=========================================================="
# Get the contents of the file which stores the location of the extracted IDE directories,
# removing whitespace from the beginning & end of the string.
IDE_DIRECTORIES=$(cat "$tmp_ide_directories" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
gh_debug "IDE_DIRECTORIES => [$IDE_DIRECTORIES]"
gh_debug "=========================================================="
gh_debug "which java: $(which java)"
gh_debug "JAVA_HOME: $JAVA_HOME"
gh_debug "=========================================================="
gh_debug "Contents of \$HOME => [$HOME] :"
ls -lash $HOME | gh_debug
gh_debug "=========================================================="
gh_debug "Contents of \$GITHUB_WORKSPACE => [$GITHUB_WORKSPACE] :"
ls -lash $GITHUB_WORKSPACE | gh_debug
gh_debug "=========================================================="
gh_debug "Contents of \$PLUGIN_LOCATION => [$PLUGIN_LOCATION] :"
ls -lash $PLUGIN_LOCATION | gh_debug
gh_debug "=========================================================="
gh_debug "Contents of the current directory => [$(pwd)] :"
ls -lash "$(pwd)" | gh_debug
gh_debug "=========================================================="

##
# Run the verification
##
VERIFICATION_OUTPUT_LOG="verification_result.log"
echo "Running verification on $PLUGIN_LOCATION for $IDE_DIRECTORIES..."

gh_debug "RUNNING COMMAND: java -jar \"$VERIFIER_JAR_LOCATION\" check-plugin $PLUGIN_LOCATION $IDE_DIRECTORIES"

# We don't wrap $IDE_DIRECTORIES in quotes at the end of this to allow
# the single string of args (ie, `"a b c"`) be broken into multiple
# arguments instead of being wrapped in quotes when passed to the command.
#     ie, we want:
#         cat a b c
#     not:
#         cat "a b c"
# Thus, we are disabling the `shellcheck` below - https://github.com/koalaman/shellcheck/wiki/SC2086
#
# shellcheck disable=SC2086
java -jar "$VERIFIER_JAR_LOCATION" check-plugin $PLUGIN_LOCATION $IDE_DIRECTORIES 2>&1 | tee "$VERIFICATION_OUTPUT_LOG"

echo "::set-output name=verification-output-log-filename::$VERIFICATION_OUTPUT_LOG"

error_wall() {
  echo "::error::=============================================="
  echo "::error::=============================================="
  echo "::error::===                                        ==="
  echo "::error::===    PLUGIN FAILED VERIFICATION CHECK    ==="
  echo "::error::===                                        ==="
  echo "::error::=============================================="
  echo "::error::=============================================="
  exit 1 # An error has occurred.
}

# Validate the log; fail if we find compatibility problems.
if (grep -E -q "^Plugin (.*) against .*: .* compatibility problems?" "$VERIFICATION_OUTPUT_LOG"); then
  error_wall
elif egrep -q "^The following files specified for the verification are not valid plugins:$" "$VERIFICATION_OUTPUT_LOG"; then
  error_wall
fi

# Everything verified ok.
exit 0
