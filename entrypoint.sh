#!/bin/bash

###
# This script expects 4 input variables:
#  - intellij-plugin-verifier version
#  - relative plugin path
#  - new-line separated IDE + version
#  - new-line separated Failure Levels
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

set -o errexit
set -o nounset

##
# GitHub Debug Functions
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

# Note: We can *NOT* pass `$LINENO` into the trap, as the `EXIT` trap always shows the line being '1'. Yes, even
#       if it shows something else on your development machine. :(
trap 'exit_trap $?' EXIT
exit_trap() {
  gh_debug "Script exited with status code [$1]."
  case $1 in
    0)  gh_debug "Everything went as desired. Goodbye." ;;
    64) echo "::error::Exiting due to a known, handled exception - duplicate ide-version entries found." ;;
    65) echo "::error::Exiting due to a known, handled exception - invalid download headers when downloading an IDE." ;;
    66) echo "::error::Exiting due to a known, handled exception - invalid zip file downloaded." ;;
    67) echo "::error::Exiting due to a known, handled, plugin validation failure." ;;
    68) echo "::error::Exiting due to an unhandled plugin validation failure." ;;

    *) cat <<EOF
::error::=======================================================
::error::===-------------------------------------------------===
::error::=== An unexpected error occurred. Status code [$1].
::error::===
::error::=== Please consider opening a bug for the developer:
::error::===    - Bug URL: https://github.com/ChrisCarini/intellij-platform-plugin-verifier-action/issues/new
::error::===    - Status Code: $1
::error::===-------------------------------------------------===
::error::=======================================================
EOF
      ;;
  esac
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

# Found from: https://github.com/JetBrains/gradle-intellij-plugin/blob/main/src/master/groovy/org/jetbrains/intellij/tasks/RunPluginVerifierTask.groovy#L29
#
# Easy way to simulate the input:
#
#   FAILURE_LEVELS=$(
#     cat <<-END
#       COMPATIBILITY_WARNINGS
#       COMPATIBILITY_PROBLEMS
#       DEPRECATED_API_USAGES
#       EXPERIMENTAL_API_USAGES
#       INTERNAL_API_USAGES
#       OVERRIDE_ONLY_API_USAGES
#       NON_EXTENDABLE_API_USAGES
#       PLUGIN_STRUCTURE_WARNINGS
#       MISSING_DEPENDENCIES
#       INVALID_PLUGIN
#       NOT_DYNAMIC
#   END
#   )
#
# failure-levels: ['COMPATIBILITY_PROBLEMS', 'INVALID_PLUGIN']
FAILURE_LEVELS="$4"

echo "::group::Initializing..."

gh_debug "INPUT_VERIFIER_VERSION => $INPUT_VERIFIER_VERSION"
gh_debug "INPUT_PLUGIN_LOCATION => $INPUT_PLUGIN_LOCATION"
gh_debug "INPUT_IDE_VERSIONS =>"
echo "$INPUT_IDE_VERSIONS" | while read -r INPUT_IDE_VERSION; do
gh_debug "                   => $INPUT_IDE_VERSION"
done
gh_debug "FAILURE_LEVELS =>"
echo "$FAILURE_LEVELS" | while read -r FAILURE_LEVEL; do
gh_debug "               => $FAILURE_LEVEL"
done

# If the user passed in a file instead of a list, pull the IDE+version combos from the file and use that instead.
if [[ -f "$GITHUB_WORKSPACE/$INPUT_IDE_VERSIONS" ]]; then
  gh_debug "$INPUT_IDE_VERSIONS is a file. Extracting file contents into variable."
  INPUT_IDE_VERSIONS=$(cat "$INPUT_IDE_VERSIONS")
  gh_debug "INPUT_IDE_VERSIONS =>"
  echo "$INPUT_IDE_VERSIONS" | while read -r INPUT_IDE_VERSION; do
    gh_debug "                   => $INPUT_IDE_VERSION"
  done
elif [[ $INPUT_IDE_VERSIONS != *":"* ]]; then
  echo "Did not detect a file at the value given for ide_versions. (If you had specified a file, please make sure you ran the checkout action before running this action). Proceeding to read ide-versions directly from the input..."
  gh_debug "If ide-versions was given as a file path, the file path should be located at $GITHUB_WORKSPACE/$INPUT_IDE_VERSIONS"
fi

# Check if there are duplicate entries in the list of IDE_VERSIONS, if so, error out and show the user a clear message
detect=$(printf '%s\n' "${INPUT_IDE_VERSIONS[@]}"|awk '!($0 in seen){seen[$0];next} 1')
if [[ ${#detect} -gt 8 ]] ; then
    echo "::error::Duplicate ide-versions found:"
    echo "$detect" | while read -r INPUT_IDE_VERSION; do
      echo "::error::        => $INPUT_IDE_VERSION"
    done
    echo "::error::"
    echo "::error::Please remove the duplicate entries before proceeding."
    exit 64 # An error has occurred - duplicate ide-version entries found.
else
    gh_debug "No duplicate IDE_VERSIONS found, proceeding..."
fi

##
# Resolve verifier values
##
if [[ "$INPUT_VERIFIER_VERSION" == "LATEST" ]]; then
    gh_debug "LATEST verifier version found, resolving version..."
    GH_LATEST_RELEASE_FILE="$HOME/intellij-plugin-verifier_latest_gh_release.json"
    gh_debug "IS GITHUB_TOKEN SET? -> $( [[ -z "${GITHUB_TOKEN-}" ]] && echo "NO" || echo "YES" )"
    if [[ -z "${GITHUB_TOKEN+x}" ]] ; then
        curl --silent --show-error https://api.github.com/repos/JetBrains/intellij-plugin-verifier/releases/latest > "$GH_LATEST_RELEASE_FILE"
        curl https://api.github.com/rate_limit | gh_debug
    else
        gh api repos/JetBrains/intellij-plugin-verifier/releases/latest > "$GH_LATEST_RELEASE_FILE"
        gh api rate_limit | gh_debug
    fi
    VERIFIER_VERSION=$(cat "$GH_LATEST_RELEASE_FILE" | jq -r .tag_name | sed 's/[^[:digit:].]*//g')
    VERIFIER_JAR_FILENAME=$(cat "$GH_LATEST_RELEASE_FILE" | jq -r .assets[].name)
    VERIFIER_DOWNLOAD_URL=$(cat "$GH_LATEST_RELEASE_FILE" | jq -r .assets[].browser_download_url)
else
    gh_debug "Using verifier version [$INPUT_VERIFIER_VERSION]..."

    VERIFIER_VERSION=${INPUT_VERIFIER_VERSION}
    # The filename of the `verifier-cli-*-all.jar` file
    VERIFIER_JAR_FILENAME="verifier-cli-$VERIFIER_VERSION-all.jar"
    VERIFIER_DOWNLOAD_URL="https://packages.jetbrains.team/maven/p/intellij-plugin-verifier/intellij-plugin-verifier/org/jetbrains/intellij/plugins/verifier-cli/$INPUT_VERIFIER_VERSION/$VERIFIER_JAR_FILENAME"
fi

# The full path of the `verifier-cli-*-all.jar` file
VERIFIER_JAR_LOCATION="$HOME/$VERIFIER_JAR_FILENAME"

gh_debug "VERIFIER_VERSION => $VERIFIER_VERSION"
gh_debug "VERIFIER_JAR_FILENAME => $VERIFIER_JAR_FILENAME"
gh_debug "VERIFIER_DOWNLOAD_URL => $VERIFIER_DOWNLOAD_URL"
gh_debug "VERIFIER_JAR_LOCATION => $VERIFIER_JAR_LOCATION"

##
# Other Variables
##

# Set the correct JAVA_HOME path for the container because this is overwritten by the setup-java action.
# We use the docker image `adoptopenjdk/openjdk11:alpine-slim` - https://hub.docker.com/layers/adoptopenjdk/openjdk11/alpine-slim/images/sha256-ef65f9b755ba9d70580d3b5e4ea7f133c68cecc096171959d011b38c4728f6b2?context=explore
#  and pull the `JAVA_HOME` property from it's image (ie, its definition has `ENV JAVA_HOME=/opt/java/openjdk`).
JAVA_HOME="/opt/java/openjdk"

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

isFailureLevelSet () {
  CHECK_OUTPUT_FILENAME="$1"
  CHECK_FAILURE_LEVEL="$2"
  CHECK_MESSAGE="$3"

  # Turn off 'exit on error'; we want to capture the exit code, and handle it accordingly.
  set +o errexit

  # Check if the specified failure level is in the input list
  echo "$FAILURE_LEVELS" | grep -q "$CHECK_FAILURE_LEVEL"
  FAILURE_LEVELS_CONTAINS=$?

  # Check if the specified message exists in the specified file
  egrep -q "$CHECK_MESSAGE" "$CHECK_OUTPUT_FILENAME"
  FILE_CONTAINS=$?

  # Restore 'exit on error' to "ON", as the test is over.
  set -o errexit

  gh_debug ""
  echo "Checking for the presence of [$CHECK_MESSAGE] in the verifier output..."
  gh_debug "FAILURE_LEVELS_CONTAINS = $FAILURE_LEVELS_CONTAINS"
  gh_debug "FILE_CONTAINS = $FILE_CONTAINS"
  gh_debug "Is [$CHECK_FAILURE_LEVEL] in [$(echo "$FAILURE_LEVELS" | xargs | sed -e 's/ /, /g')]? = $FAILURE_LEVELS_CONTAINS"
  gh_debug "Is [$CHECK_MESSAGE] in the file [$CHECK_OUTPUT_FILENAME]? = $FILE_CONTAINS"

  if [ ${FAILURE_LEVELS_CONTAINS} == 0 ] && [ ${FILE_CONTAINS} == 0 ]; then
    # We end the block here, as the next thing that will be printed is the failure banner.
    gh_debug "Both checks are true(0)."
    echo "[$CHECK_MESSAGE] was found in the verifier output. Failing check."
    echo "::endgroup::" # END "Running validations against output..." block.

    return 0
  else
    gh_debug "One or more of the above checks is false(1)."
    return 1
  fi
}

##
# Setup
##

echo "Downloading plugin verifier [version '$INPUT_VERIFIER_VERSION'] from [$VERIFIER_DOWNLOAD_URL] to [$VERIFIER_JAR_LOCATION]..."
curl -L --silent --show-error --output "$VERIFIER_JAR_LOCATION" "$VERIFIER_DOWNLOAD_URL"

echo "::endgroup::" # END "Initializing..." block

# temp file for storing IDE Directories we download and unzip
tmp_ide_directories="/tmp/ide_directories.txt"

# temp file for storing messages to display after the below loop.
# we use this, as each iteration of the loop has it's respective
# log messages hidden via a log group, which hides the output
# from the user; by printing any messages after the loop, it is
# more obvious to the user.
post_loop_messages="/tmp/post_loop_messages.txt"

touch "$post_loop_messages"

echo "Preparing all IDE versions specified..."
echo "$INPUT_IDE_VERSIONS" | while read -r IDE_VERSION; do
  echo "::group::Preparing [$IDE_VERSION]..."
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

  echo "Downloading $IDE $IDE_VERSION from [$DOWNLOAD_URL] into [$ZIP_FILE_PATH]..."
  CURL_RESP=$(curl -L --silent --show-error -w 'HTTP/%{http_code} - content-type: %{content_type}' --output "$ZIP_FILE_PATH" "$DOWNLOAD_URL")

  gh_debug "Checking response code and content type for the download of [$DOWNLOAD_URL] to ensure download successful..."
  # Turn off 'exit on error'; if we error out when testing the response code,
  # we want to first print a friendly message to the user and then exit.
  set +o errexit
  echo "$CURL_RESP" | grep "HTTP/200 - content-type: application/octet-stream"
  if [[ $? -eq 0 ]]; then
    gh_debug "Download of [$DOWNLOAD_URL] to [$ZIP_FILE_PATH] was successful."
  else
    read -r -d '' message <<EOF
::error::=======================================================================================
::error::It appears the download of $DOWNLOAD_URL did not contain the following:
::error::    - status: 200
::error::    - content-type: application/octet-stream
::error::
::error::Actual response: $CURL_RESP
::error::
::error::This can happen if $IDE_VERSION is not a valid IDE / version. If you believe it is a
::error::valid ide/version, please open an issue on GitHub:
::error::     https://github.com/ChrisCarini/intellij-platform-plugin-verifier-action/issues/new
::error::
::error::As a precaution, we are failing this execution.
::error::=======================================================================================
EOF
    # Print the message once in this log group, and then save for after so it's more visible to the user.
    echo "$message" ; echo "$message" >> $post_loop_messages
    exit 65 # An error has occurred - invalid download headers.
  fi
  # Restore 'exit on error', as the test is over.
  set -o errexit

  gh_debug "Testing [$ZIP_FILE_PATH] to ensure it is a valid zip file..."
  # Turn off 'exit on error'; if we error out when testing the zip file,
  # we want to first print a friendly message to the user and then exit.
  set +o errexit
  zip -T "$ZIP_FILE_PATH"
  if [[ $? -eq 0 ]]; then
    gh_debug "[$ZIP_FILE_PATH] appears to be a valid zip file. Proceeding..."
  else
    read -r -d '' message <<EOF
::error::=======================================================================================
::error::It appears $ZIP_FILE_PATH is not a valid zip file.
::error::
::error::This can happen when the download did not work properly, or if $IDE_VERSION is
::error::not a valid IDE / version. If you believe it is a valid version, please open
::error::an issue on GitHub:
::error::     https://github.com/ChrisCarini/intellij-platform-plugin-verifier-action/issues/new
::error::
::error::As a precaution, we are failing this execution.
::error::=======================================================================================
EOF
    # Print the message once in this log group, and then save for after so it's more visible to the user.
    echo "$message" ; echo "$message" >> $post_loop_messages
    exit 66 # An error has occurred - invalid zip file.
  fi
  # Restore 'exit on error', as the test is over.
  set -o errexit

  IDE_EXTRACT_LOCATION="$HOME/ides/$IDE-$VERSION"
  echo "Extracting [$ZIP_FILE_PATH] into [$IDE_EXTRACT_LOCATION]..."
  mkdir -p "$IDE_EXTRACT_LOCATION"
  unzip -q -d "$IDE_EXTRACT_LOCATION" "$ZIP_FILE_PATH"

  gh_debug "Removing [$ZIP_FILE_PATH] to save storage space..."
  rm "$ZIP_FILE_PATH"

  # Append the extracted location to the variable of IDEs to validate against.
  gh_debug "Adding $IDE_EXTRACT_LOCATION to '$tmp_ide_directories'..."
  printf "%s " "$IDE_EXTRACT_LOCATION" >> $tmp_ide_directories
  echo "::endgroup::" # END "Processing IDE:Version = \"$IDE_VERSION\"" block.
done

# Print any messages from the loop - we do this outside of the loop so that
# any warning / error messages are not masked by the log group.
cat $post_loop_messages

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
echo "::endgroup::" # END "Running verification on $PLUGIN_LOCATION for $IDE_DIRECTORIES..." block.

##
# Run the verification
##
VERIFICATION_OUTPUT_LOG="verification_result.log"
echo "::group::Running verification on $PLUGIN_LOCATION for $IDE_DIRECTORIES..."

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

# Turn off 'exit on error'; if we error out when testing the response code,
# we want to first print a friendly message to the user and then exit.
set +o errexit

# shellcheck disable=SC2086
java -jar "$VERIFIER_JAR_LOCATION" check-plugin $PLUGIN_LOCATION $IDE_DIRECTORIES 2>&1 | tee "$VERIFICATION_OUTPUT_LOG"
# We use `${PIPESTATUS[0]}` here instead of `$?` as the later returns the status code for the `tee` call, and we want the status code of the `java` invocation of the verifier, which `${PIPESTATUS[0]}` provides.
VERIFICATION_SUCCESSFUL=${PIPESTATUS[0]}

# Restore 'exit on error', as the test is over.
set -o errexit

echo "::endgroup::" # END "Running verification on $PLUGIN_LOCATION for $IDE_DIRECTORIES..." block.

echo "::set-output name=verification-output-log-filename::$VERIFICATION_OUTPUT_LOG"

error_wall() {
  echo "::error::=============================================="
  echo "::error::=============================================="
  echo "::error::===                                        ==="
  echo "::error::===    PLUGIN FAILED VERIFICATION CHECK    ==="
  echo "::error::===                                        ==="
  echo "::error::=============================================="
  echo "::error::=============================================="
  exit 67 # An error has occurred - plugin verification failure.
}

# Validate the log; fail if we find compatibility problems.

echo "::group::Running validations against output..."
# The below if/elif blocks are taken from the `gradle-intellij-plugin`'s RunPluginVerifierTask.groovy file, where
# the `FailureLevel` Enum is specified with the below information. A link is below for reference:
# Link: https://github.com/JetBrains/gradle-intellij-plugin/blob/ea5eb75548af4b368f2bd981d8c2d338edb3208d/src/main/groovy/org/jetbrains/intellij/tasks/RunPluginVerifierTask.groovy#L29

# COMPATIBILITY_WARNINGS("Compatibility warnings"),
if isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "COMPATIBILITY_WARNINGS" "Compatibility warnings"; then
  error_wall

# COMPATIBILITY_PROBLEMS("Compatibility problems"),
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "COMPATIBILITY_PROBLEMS" "^Plugin (.*) against .*: .* compatibility problems?"; then
  error_wall
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "COMPATIBILITY_PROBLEMS" "Compatibility problems"; then
  error_wall

# DEPRECATED_API_USAGES("Deprecated API usages"),
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "DEPRECATED_API_USAGES" "Deprecated API usages"; then
  error_wall

# EXPERIMENTAL_API_USAGES("Experimental API usages"),
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "EXPERIMENTAL_API_USAGES" "Experimental API usages"; then
  error_wall

# INTERNAL_API_USAGES("Internal API usages"),
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "INTERNAL_API_USAGES" "Internal API usages"; then
  error_wall

# OVERRIDE_ONLY_API_USAGES("Override-only API usages"),
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "OVERRIDE_ONLY_API_USAGES" "Override-only API usages"; then
  error_wall

# NON_EXTENDABLE_API_USAGES("Non-extendable API usages"),
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "NON_EXTENDABLE_API_USAGES" "Non-extendable API usages"; then
  error_wall

# PLUGIN_STRUCTURE_WARNINGS("Plugin structure warnings"),
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "PLUGIN_STRUCTURE_WARNINGS" "Plugin structure warnings"; then
  error_wall

# MISSING_DEPENDENCIES("Missing dependencies"),
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "MISSING_DEPENDENCIES" "Missing dependencies"; then
  error_wall

# INVALID_PLUGIN("The following files specified for the verification are not valid plugins"),
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "INVALID_PLUGIN" "The following files specified for the verification are not valid plugins"; then
  error_wall

# NOT_DYNAMIC("Plugin cannot be loaded/unloaded without IDE restart");
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "NOT_DYNAMIC" "Plugin cannot be loaded/unloaded without IDE restart"; then
  error_wall

elif [ ${VERIFICATION_SUCCESSFUL} == 1 ]; then
  # We end the block here, as only `isFailureLevelSet` sets the endgroup for us.
  echo "::endgroup::" # END "Running validations against output..." block.

  echo "::error::======================================================="
  echo "::error::======================================================="
  echo "::error::===                                                 ==="
  echo "::error::===    UNKNOWN FAILURE DURING VERIFICATION CHECK    ==="
  echo "::error::===                                                 ==="
  echo "::error::===   NOTICE!  NOTICE!  NOTICE!  NOTICE!  NOTICE!   ==="
  echo "::error::===                                                 ==="
  echo "::error::===   The verifier exited with a status code of 0   ==="
  echo "::error::===   and was unable to identify a known failure    ==="
  echo "::error::===   from the verifier. Consider opening an        ==="
  echo "::error::===   issue with the maintainers of this GitHub     ==="
  echo "::error::===   Action to notify them. A link is provided     ==="
  echo "::error::===   below:                                        ==="
  echo "::error::===-------------------------------------------------==="
  echo "::error::=== Bug URL: https://github.com/ChrisCarini/intellij-platform-plugin-verifier-action/issues/new?labels=enhancement%2C+unknown-failure&template=unknown-failure-during-verification-check.md&title=Unknown+Failure+Identified%21"
  echo "::error::===-------------------------------------------------==="
  exit 68 # An error has occurred - plugin verification failure.
else
  # We end the block here, nothing else would have ended it.
  echo "::endgroup::" # END "Running validations against output..." block.
fi

# Everything verified ok.
exit 0
