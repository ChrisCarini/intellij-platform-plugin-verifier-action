#!/bin/bash

###
# This script expects 8 input variables:
#  - intellij-plugin-verifier version
#  - relative plugin path
#  - new-line separated IDE + version
#  - new-line separated Failure Levels
#  - comma-separated mute plugin problems list
#  - colon-separated external class prefixes list
#  - comma-separated verification report format list
#  - comma-separated report filenames/aliases to add to job summary
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
    69) echo "::error::Exiting due to a known, handled exception - failed to get latest release info for JetBrains/intellij-plugin-verifier." ;;
    70) echo "::error::Exiting due to a known, handled exception - failed to get GitHub rate limit information." ;;
    71) echo "::error::Exiting due to a known, handled exception - failed to download plugin verifier." ;;
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

# Found from: https://github.com/JetBrains/intellij-plugin-verifier?tab=readme-ov-file#specific-options
#
# Input string can be a comma separated list
#
# mute-plugin-problems: 'ForbiddenPluginIdPrefix,TemplateWordInPluginId,TemplateWordInPluginName'
INPUT_MUTE_PLUGIN_PROBLEMS="${5-}"

# external-prefixes: 'org.jetbrains.jps:com.example'
INPUT_EXTERNAL_PREFIXES="${6-}"

# verification-reports-formats: 'plain,markdown'
INPUT_VERIFICATION_REPORTS_FORMATS="${7-}"

# add-to-summary: 'verification-verdict.txt,compatibility-problems.txt' or aliases 'markdown', 'plain'
INPUT_ADD_TO_SUMMARY="${8-}"

# verify the specified content-type is one of the defined accepted content-types
function is_valid_response_content_type() {
  # Remove everything after the first semicolon (;) - e.g. "application/json; charset=utf-8" -> "application/json"
  local response_content_type="${1%%;*}"
  local accepted_content_types=$2
  for valid_content_type in $accepted_content_types; do
    if [[ "$response_content_type" = "$valid_content_type" ]]; then
        return 0
    fi
  done
  return 1
}

function curl_with_retry() {
  OUTPUT_FILE=$1
  URL=$2
  ACCEPTED_CONTENT_TYPES=$3
  ERROR_CODE=$4
  ADDITIONAL_ARGS="${*:5}" # Capture all arguments starting from the second one as an array

  local retries=3
  local delay=3
  local attempt=0
  local success=false

  while (( attempt < retries )); do
    (( attempt=attempt+1 ))
    echo "[$attempt of $retries] Downloading [${URL}] to [${OUTPUT_FILE}]..."

    CURL_RESP=$(curl --silent --show-error -L --output "${OUTPUT_FILE}" -w '%{json}' $ADDITIONAL_ARGS "${URL}")
    curl_success=$?
    http_code=$(echo "${CURL_RESP}" | jq -r '.response_code // empty')
    content_type=$(echo "${CURL_RESP}" | jq -r '.content_type // empty')
    size_download=$(echo "${CURL_RESP}" | jq -r '.size_download // empty')
    speed_download=$(echo "${CURL_RESP}" | jq -r '.speed_download // empty')

    gh_debug "[${URL}] curl_success:           $curl_success"
    gh_debug "[${URL}] http_code:              $http_code"
    gh_debug "[${URL}] content_type:           $content_type"
    gh_debug "[${URL}] size_download:          $size_download"
    gh_debug "[${URL}] speed_download:         $speed_download"
    gh_debug "[${URL}] ACCEPTED_CONTENT_TYPES: $ACCEPTED_CONTENT_TYPES"
    if [ $curl_success -eq 0 ] && [ "$http_code" = "200" ] && is_valid_response_content_type "${content_type}" "${ACCEPTED_CONTENT_TYPES}"; then
      echo "[$attempt of $retries] Successfully downloaded [${URL}] to [${OUTPUT_FILE}]."
      success=true
      break
    fi

    echo "[$attempt of $retries] Failed downloading [${URL}] to [${OUTPUT_FILE}]. Retrying in $delay seconds..."
    sleep $delay
  done

  if [ "$success" = false ]; then
    echo "All $retries attempts failed!"
    read -r -d '' message <<EOF
::error::=======================================================================================
::error::It appears the download of $URL did not contain the following:
::error::    - curl return code: 0
::error::    - http status code: 200
::error::    - http content-type: one of ${ACCEPTED_CONTENT_TYPES}
::error::
::error::Actual response:
::error::   - curl response code: $curl_success
::error::   - HTTP/${http_code} - content-type: ${content_type}
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
    exit $ERROR_CODE
  fi
}

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
gh_debug "INPUT_MUTE_PLUGIN_PROBLEMS => $INPUT_MUTE_PLUGIN_PROBLEMS"
gh_debug "INPUT_EXTERNAL_PREFIXES => $INPUT_EXTERNAL_PREFIXES"
gh_debug "INPUT_VERIFICATION_REPORTS_FORMATS => $INPUT_VERIFICATION_REPORTS_FORMATS"
gh_debug "INPUT_ADD_TO_SUMMARY => $INPUT_ADD_TO_SUMMARY"

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
    function downloadVerifierLatestReleaseJson() {
      gh_debug "IS GITHUB_TOKEN SET? -> $( [[ -z "${GITHUB_TOKEN-}" ]] && echo "NO" || echo "YES" )"
      if [[ -z "${GITHUB_TOKEN+x}" ]] ; then
          curl_with_retry "$GH_LATEST_RELEASE_FILE" https://api.github.com/repos/JetBrains/intellij-plugin-verifier/releases/latest "application/json" 69
          curl_with_retry rate_limit.json https://api.github.com/rate_limit "application/json" 70 && cat rate_limit.json | gh_debug
      else
          gh api repos/JetBrains/intellij-plugin-verifier/releases/latest > "$GH_LATEST_RELEASE_FILE"
          gh api rate_limit | gh_debug
      fi
      cat "$GH_LATEST_RELEASE_FILE" | gh_debug
    }
    downloadVerifierLatestReleaseJson
    if [ ! -s "$GH_LATEST_RELEASE_FILE" ]; then
      echo "$GH_LATEST_RELEASE_FILE appears to be empty. Retrying."
      downloadVerifierLatestReleaseJson
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

# The location that the IDE zip files will be extracted into.
IDE_BASE_EXTRACT_LOCATION="$HOME/ides"

##
# Functions
##

# Parse a comma-separated string into a trimmed array stored in the named variable.
# Usage: parse_csv "a, b, c" RESULT_ARRAY
parse_csv() {
  local input="$1"
  local -n _arr="$2"
  gh_debug "parse_csv: input=[$input]"
  _arr=()
  [ -z "$input" ] && gh_debug "parse_csv: input is empty, returning empty array." && return
  IFS=',' read -ra _raw <<< "$input"
  for _item in "${_raw[@]}"; do
    _item="${_item#"${_item%%[![:space:]]*}"}"
    _item="${_item%"${_item##*[![:space:]]}"}"
    [ -n "$_item" ] && _arr+=("$_item")
  done
  gh_debug "parse_csv: result=[${_arr[*]}] (${#_arr[@]} items)"
}

# Ensure FORMATS includes markdown when add-to-summary requests markdown output.
ensure_markdown_format() {
  gh_debug "ensure_markdown_format: INPUT_ADD_TO_SUMMARY=[$INPUT_ADD_TO_SUMMARY] FORMATS=[${FORMATS[*]}]"
  [[ -z "${INPUT_ADD_TO_SUMMARY}" ]] && gh_debug "ensure_markdown_format: INPUT_ADD_TO_SUMMARY is empty, skipping." && return
  [[ "${INPUT_ADD_TO_SUMMARY,,}" != *markdown* && "${INPUT_ADD_TO_SUMMARY,,}" != *\.md* ]] && gh_debug "ensure_markdown_format: no markdown/md alias found in INPUT_ADD_TO_SUMMARY, skipping." && return

  if [ ${#FORMATS[@]} -eq 0 ] ; then
    gh_debug "ensure_markdown_format: FORMATS is empty; defaulting to [plain html markdown]."
    FORMATS=("plain" "html" "markdown")
  else
    for fmt in "${FORMATS[@]}"; do
      if [[ "${fmt,,}" == "markdown" ]]; then
        gh_debug "ensure_markdown_format: markdown already present in FORMATS, skipping."
        return
      fi
    done
    gh_debug "ensure_markdown_format: appending markdown to FORMATS."
    FORMATS+=("markdown")
  fi
  gh_debug "ensure_markdown_format: FORMATS after=[${FORMATS[*]}]"
}

# Build the -verification-reports-formats CLI argument string from the FORMATS array.
build_formats_arg() {
  VERIFICATION_REPORTS_FORMATS_ARGS=""
  if [ ${#FORMATS[@]} -eq 0 ]; then
    gh_debug "build_formats_arg: FORMATS is empty; no -verification-reports-formats arg will be added."
    return
  fi
  local csv
  csv=$(IFS=','; echo "${FORMATS[*]}")
  VERIFICATION_REPORTS_FORMATS_ARGS="-verification-reports-formats ${csv}"
  gh_debug "build_formats_arg: VERIFICATION_REPORTS_FORMATS_ARGS=[$VERIFICATION_REPORTS_FORMATS_ARGS]"
}

# Resolve summary aliases (markdown, plain) into file glob patterns.
resolve_summary_patterns() {
  local input="$1"
  local -n _pats="$2"
  local -a items
  gh_debug "resolve_summary_patterns: input=[$input]"
  parse_csv "$input" items
  _pats=()
  for item in "${items[@]}"; do
    case "$item" in
      markdown) _pats+=("*.md")  ; gh_debug "resolve_summary_patterns: alias 'markdown' -> '*.md'" ;;
      plain)    _pats+=("*.txt") ; gh_debug "resolve_summary_patterns: alias 'plain' -> '*.txt'" ;;
      *)        _pats+=("$item") ; gh_debug "resolve_summary_patterns: literal pattern -> '$item'" ;;
    esac
  done
  gh_debug "resolve_summary_patterns: resolved patterns=[${_pats[*]}] (${#_pats[@]} patterns)"
}

# Find the report directory for a given IDE version string (from build.txt, e.g. "IU-261.23567.138").
# The verifier names report dirs identically to the build.txt content.
find_report_dir_for_ide() {
  local ide_version="$1"
  local -n _dir="$2"
  _dir="$VERIFICATION_REPORTS_DIR/$ide_version"
  if [ -d "$_dir" ]; then
    gh_debug "find_report_dir_for_ide: found report dir [$_dir] for IDE version [$ide_version]"
  else
    gh_debug "find_report_dir_for_ide: no report dir found at [$_dir] for IDE version [$ide_version]"
    _dir=""
  fi
}

# Maximum size (in bytes) for GITHUB_STEP_SUMMARY content.
# GitHub enforces a 1024KB limit; we use 1000KB to leave headroom for closing tags and truncation message.
TMP_GITHUB_STEP_SUMMARY=$(mktemp)
SUMMARY_MAX_BYTES=$((1000 * 1024))
SUMMARY_TRUNCATED=false

# Safely append a file's content to GITHUB_STEP_SUMMARY, respecting the size limit.
# If the file would push us over, only the bytes that fit are written and SUMMARY_TRUNCATED is set.
safe_append_to_summary() {
  local file="$1"
  local current_size
  current_size=$(wc -c < "$TMP_GITHUB_STEP_SUMMARY")
  local remaining=$((SUMMARY_MAX_BYTES - current_size))

  gh_debug "safe_append_to_summary: file=[$file] current_size=[$current_size] remaining=[$remaining]"

  if [ "$remaining" -le 0 ]; then
    gh_debug "safe_append_to_summary: no space remaining; setting SUMMARY_TRUNCATED=true."
    SUMMARY_TRUNCATED=true
    return
  fi

  local file_size
  file_size=$(wc -c < "$file")
  gh_debug "safe_append_to_summary: file_size=[$file_size]"

  if [ "$file_size" -le "$remaining" ]; then
    gh_debug "safe_append_to_summary: appending full file [$file]."
    cat "$file" >> "$TMP_GITHUB_STEP_SUMMARY"
  else
    gh_debug "safe_append_to_summary: file exceeds remaining space; truncating to [$remaining] bytes and setting SUMMARY_TRUNCATED=true."
    head -c "$remaining" "$file" >> "$TMP_GITHUB_STEP_SUMMARY"
    SUMMARY_TRUNCATED=true
  fi
}

# Append a single report file to TMP_GITHUB_STEP_SUMMARY with appropriate formatting.
# .md files are rendered raw; .txt >3 lines collapsed; .txt <=3 lines inline code block.
# Uses safe_append_to_summary for the file content so tags are always properly closed.
append_file_to_summary() {
  [ "$SUMMARY_TRUNCATED" = true ] && gh_debug "append_file_to_summary: SUMMARY_TRUNCATED is true; skipping [$1]." && return

  local file="$1"
  local total_files="${2:-2}"
  local filename line_count
  filename=$(basename "$file")
  line_count=$(wc -l < "$file")

  gh_debug "append_file_to_summary: file=[$file] filename=[$filename] line_count=[$line_count] total_files=[$total_files]"

  if [[ "${filename,,}" == *.md ]] ; then
    if [ "$total_files" -gt 1 ] ; then
      gh_debug "append_file_to_summary: rendering [$filename] as collapsed <details> markdown block."
      echo "<details>" >> "$TMP_GITHUB_STEP_SUMMARY"
      echo "<summary><strong>$filename</strong> ($line_count lines)</summary>" >> "$TMP_GITHUB_STEP_SUMMARY"
      echo "" >> "$TMP_GITHUB_STEP_SUMMARY"
      safe_append_to_summary "$file"
      echo "" >> "$TMP_GITHUB_STEP_SUMMARY"
      echo "</details>" >> "$TMP_GITHUB_STEP_SUMMARY"
    else
      gh_debug "append_file_to_summary: rendering [$filename] as expanded markdown (only file)."
      safe_append_to_summary "$file"
      echo "" >> "$TMP_GITHUB_STEP_SUMMARY"
    fi
  elif [ "$line_count" -gt 3 ] ; then
    gh_debug "append_file_to_summary: rendering [$filename] as collapsed <details> code block ($line_count lines > 3)."
    echo "<details>" >> "$TMP_GITHUB_STEP_SUMMARY"
    echo "<summary><strong>$filename</strong> ($line_count lines)</summary>" >> "$TMP_GITHUB_STEP_SUMMARY"
    echo "" >> "$TMP_GITHUB_STEP_SUMMARY"
    echo '```' >> "$TMP_GITHUB_STEP_SUMMARY"
    safe_append_to_summary "$file"
    echo '```' >> "$TMP_GITHUB_STEP_SUMMARY"
    echo "" >> "$TMP_GITHUB_STEP_SUMMARY"
    echo "</details>" >> "$TMP_GITHUB_STEP_SUMMARY"
  else
    gh_debug "append_file_to_summary: rendering [$filename] as inline code block ($line_count lines <= 3)."
    echo "**$filename**" >> "$TMP_GITHUB_STEP_SUMMARY"
    echo '```' >> "$TMP_GITHUB_STEP_SUMMARY"
    safe_append_to_summary "$file"
    echo '```' >> "$TMP_GITHUB_STEP_SUMMARY"
    echo "" >> "$TMP_GITHUB_STEP_SUMMARY"
  fi

  # If we hit the limit, append the warning now that tags are closed
  if [ "$SUMMARY_TRUNCATED" = true ]; then
    gh_debug "append_file_to_summary: SUMMARY_TRUNCATED detected after writing [$filename]; appending truncation warning."
    printf '\n---\n\n> **Warning:** Job summary truncated to stay within GitHub'\''s 1024KB size limit. See the verification output log for full details.\n' >> "$TMP_GITHUB_STEP_SUMMARY"
  fi
}

# Write the job summary section for a single IDE version.
write_summary_for_ide() {
  local ide_version="$1"
  shift
  local patterns=("$@")

  gh_debug "write_summary_for_ide: ide_version=[$ide_version] patterns=[${patterns[*]}]"
  echo "## $ide_version" >> "$TMP_GITHUB_STEP_SUMMARY"
  echo "" >> "$TMP_GITHUB_STEP_SUMMARY"

  local ide_dir
  find_report_dir_for_ide "$ide_version" ide_dir
  if [ -z "$ide_dir" ] || [ ! -d "$ide_dir" ] ; then
    gh_debug "write_summary_for_ide: no report dir found for [$ide_version]; writing NO REPORTS FOUND."
    echo "**NO REPORTS FOUND**" >> "$TMP_GITHUB_STEP_SUMMARY"
    echo "" >> "$TMP_GITHUB_STEP_SUMMARY"
    return
  fi

  local reports_realpath
  reports_realpath="$(realpath "$VERIFICATION_REPORTS_DIR")"
  gh_debug "write_summary_for_ide: scanning [$ide_dir] (reports_realpath=[$reports_realpath])"

  # Collect all matching files into an array in a single pass
  local -a matched_files=()
  for pattern in "${patterns[@]}"; do
    [[ "$pattern" == *..* ]] && gh_debug "Skipping pattern with path traversal: $pattern" && continue
    while IFS= read -r -d '' file; do
      case "$(realpath "$file")" in
        "${reports_realpath}"*) ;;
        *) gh_debug "Skipping file outside reports dir: $file"; continue ;;
      esac
      [ -f "$file" ] || continue
      gh_debug "write_summary_for_ide: matched file [$file] for pattern [$pattern]"
      matched_files+=("$file")
    done < <(find "$ide_dir" -name "$pattern" -print0 | sort -z)
  done

  if [ ${#matched_files[@]} -eq 0 ] ; then
    gh_debug "write_summary_for_ide: no matching files found for [$ide_version]; writing NO REPORTS FOUND."
    echo "**NO REPORTS FOUND**" >> "$TMP_GITHUB_STEP_SUMMARY"
    echo "" >> "$TMP_GITHUB_STEP_SUMMARY"
  else
    local total_files=${#matched_files[@]}
    gh_debug "write_summary_for_ide: appending $total_files file(s) to summary for [$ide_version]."
    for file in "${matched_files[@]}"; do
      append_file_to_summary "$file" "$total_files"
    done
  fi
}

# Write the full job summary across all verified IDEs.
write_job_summary() {
  echo "::group::Writing to job summary..."
  gh_debug ""
  if [ -z "$VERIFICATION_REPORTS_DIR" ]; then
      echo "No verification report dir found"
  fi
  gh_debug "write_job_summary: INPUT_ADD_TO_SUMMARY=[$INPUT_ADD_TO_SUMMARY]"
  gh_debug "write_job_summary: VERIFICATION_REPORTS_DIR=[$VERIFICATION_REPORTS_DIR]"
  gh_debug "write_job_summary: IDE_DIRECTORIES=[$IDE_DIRECTORIES]"
  local -a patterns
  resolve_summary_patterns "$INPUT_ADD_TO_SUMMARY" patterns
  gh_debug "write_job_summary: resolved patterns=[${patterns[*]}]"

  # shellcheck disable=SC2086
  for ide_dir in $IDE_DIRECTORIES; do
    if [ "$SUMMARY_TRUNCATED" = true ]; then
      echo "write_job_summary: SUMMARY_TRUNCATED is true; stopping iteration."
      break
    fi
    [ -d "$ide_dir" ] || { echo "write_job_summary: [$ide_dir] is not a directory, skipping."; continue; }
    local ide_version
    ide_version=$(<"$ide_dir/build.txt")
    [ -z "$ide_version" ] && echo "write_job_summary: build.txt in [$ide_dir] is empty, skipping." && continue
    echo "write_job_summary: processing IDE version [$ide_version] from dir [$ide_dir]"
    write_summary_for_ide "$ide_version" "${patterns[@]}"
  done
  local tmp_size
  tmp_size=$(wc -c < "$TMP_GITHUB_STEP_SUMMARY")
  local bytes_to_write=$(( tmp_size < SUMMARY_MAX_BYTES ? tmp_size : SUMMARY_MAX_BYTES ))
  echo "write_job_summary: flushing TMP_GITHUB_STEP_SUMMARY to GITHUB_STEP_SUMMARY (writing $bytes_to_write of $tmp_size bytes; max $SUMMARY_MAX_BYTES bytes)."
  head -c "$SUMMARY_MAX_BYTES" "$TMP_GITHUB_STEP_SUMMARY" >> "$GITHUB_STEP_SUMMARY"

  echo "::endgroup::" # END "Writing to job summary..." block.
}

release_type_for() {
  # release_type_for "2019.3-EAP-SNAPSHOT" -> 'snapshots'
  # release_type_for "2019.3-SNAPSHOT" -> 'nightly'
  # release_type_for "2019.3" -> 'releases'
  case $1 in
  *-EAP-SNAPSHOT | *-EAP-CANDIDATE-SNAPSHOT | *-CUSTOM-SNAPSHOT)
    echo "snapshots"
    return
    ;;
  # Per a JetBrains Platform Slack thread in #general, response from Jakub C. -> "Nightly channel isn't available publicly."
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

debug_ide_base_extract_location_size () {
  gh_debug "==================== PRINT SPACE OF [${IDE_BASE_EXTRACT_LOCATION}] ===================="
  gh_debug "----------------------------------------------------------------------------"
  gh_debug ""
  gh_debug "$ df -h /"
  gh_debug ""
  df -h / | gh_debug
  gh_debug "----------------------------------------------------------------------------"
  gh_debug ""
  gh_debug "$ du --human-readable --max-depth=1 --total ${IDE_BASE_EXTRACT_LOCATION}"
  gh_debug ""
  du --human-readable --max-depth=1 --total "${IDE_BASE_EXTRACT_LOCATION}" | gh_debug
  gh_debug "----------------------------------------------------------------------------"
  gh_debug "==================== END PRINT SPACE OF [${IDE_BASE_EXTRACT_LOCATION}] ===================="
}

##
# Setup
##

echo "Downloading plugin verifier [version '$INPUT_VERIFIER_VERSION'] from [$VERIFIER_DOWNLOAD_URL] to [$VERIFIER_JAR_LOCATION]..."
curl_with_retry "$VERIFIER_JAR_LOCATION" "$VERIFIER_DOWNLOAD_URL" "application/octet-stream" 71

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

debug_ide_base_extract_location_size

echo "Preparing all IDE versions specified..."
echo "$INPUT_IDE_VERSIONS" | while read -r IDE_VERSION; do
  if [ -z "$IDE_VERSION" ]; then
    continue
  fi
  echo "::group::Preparing [$IDE_VERSION]..."

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

  # the content-type headers returned by the platform download calls
  PLATFORM_RESPONSE_ACCEPTED_CONTENT_TYPES="application/octet-stream application/x-zip-compressed application/zip"
  curl_with_retry "$ZIP_FILE_PATH" "$DOWNLOAD_URL" "$PLATFORM_RESPONSE_ACCEPTED_CONTENT_TYPES" 65

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

  IDE_EXTRACT_LOCATION="${IDE_BASE_EXTRACT_LOCATION}/$IDE-$VERSION"
  echo "Extracting [$ZIP_FILE_PATH] into [$IDE_EXTRACT_LOCATION]..."
  mkdir -p "$IDE_EXTRACT_LOCATION"
  unzip -q -d "$IDE_EXTRACT_LOCATION" "$ZIP_FILE_PATH"

  debug_ide_base_extract_location_size

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

MUTE_ARGS=""

if [ "${INPUT_MUTE_PLUGIN_PROBLEMS}" ] ; then
  MUTE_ARGS="-mute ${INPUT_MUTE_PLUGIN_PROBLEMS}"
fi

EXTERNAL_PREFIX_ARGS=""

if [ "${INPUT_EXTERNAL_PREFIXES}" ] ; then
  EXTERNAL_PREFIX_ARGS="-external-prefixes ${INPUT_EXTERNAL_PREFIXES}"
fi

# Build verification report format arguments
echo "::group::Building verification report format arguments..."
parse_csv "$INPUT_VERIFICATION_REPORTS_FORMATS" FORMATS
gh_debug "FORMATS after parse_csv => [${FORMATS[*]}] (${#FORMATS[@]} items)"
ensure_markdown_format
gh_debug "FORMATS after ensure_markdown_format => [${FORMATS[*]}] (${#FORMATS[@]} items)"
build_formats_arg
gh_debug "VERIFICATION_REPORTS_FORMATS_ARGS => [$VERIFICATION_REPORTS_FORMATS_ARGS]"
echo "::endgroup::" # END "Building verification report format arguments..." block.

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

gh_debug "RUNNING COMMAND: java -jar \"$VERIFIER_JAR_LOCATION\" check-plugin $PLUGIN_LOCATION $IDE_DIRECTORIES $MUTE_ARGS $EXTERNAL_PREFIX_ARGS $VERIFICATION_REPORTS_FORMATS_ARGS"

# We don't wrap $IDE_DIRECTORIES or $MUTE_ARGS in quotes at the end of this to
# allow the single string of args (ie, `"a b c"`) be broken into multiple
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
java -jar "$VERIFIER_JAR_LOCATION" check-plugin $PLUGIN_LOCATION $IDE_DIRECTORIES $MUTE_ARGS $EXTERNAL_PREFIX_ARGS $VERIFICATION_REPORTS_FORMATS_ARGS 2>&1 | tee "$VERIFICATION_OUTPUT_LOG"
# We use `${PIPESTATUS[0]}` here instead of `$?` as the later returns the status code for the `tee` call, and we want the status code of the `java` invocation of the verifier, which `${PIPESTATUS[0]}` provides.
VERIFICATION_SUCCESSFUL=${PIPESTATUS[0]}

# Restore 'exit on error', as the test is over.
set -o errexit

echo "::endgroup::" # END "Running verification on $PLUGIN_LOCATION for $IDE_DIRECTORIES..." block.

echo "verification-output-log-filename=$VERIFICATION_OUTPUT_LOG" >> $GITHUB_OUTPUT

# Parse the verification reports directory from the verifier's stdout
VERIFICATION_REPORTS_DIR=$(sed -n 's/^Verification reports directory: //p' "$VERIFICATION_OUTPUT_LOG" || echo "")
echo "verification-reports-dir=$VERIFICATION_REPORTS_DIR" >> $GITHUB_OUTPUT
gh_debug "VERIFICATION_REPORTS_DIR => $VERIFICATION_REPORTS_DIR"

# Append report to GitHub Actions Job Summary if requested
[ -z "${INPUT_ADD_TO_SUMMARY}" ] || write_job_summary

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
# Link: https://github.com/JetBrains/intellij-platform-gradle-plugin/blob/main/src/main/kotlin/org/jetbrains/intellij/platform/gradle/tasks/VerifyPluginTask.kt#L526-L574

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

# SCHEDULED_FOR_REMOVAL_API_USAGES("scheduled for removal API"),
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "SCHEDULED_FOR_REMOVAL_API_USAGES" "scheduled for removal API"; then
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

# NOT_DYNAMIC("Plugin probably cannot be enabled or disabled without IDE restart");
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "NOT_DYNAMIC" "Plugin cannot be loaded/unloaded without IDE restart"; then
  error_wall
elif isFailureLevelSet "$VERIFICATION_OUTPUT_LOG" "NOT_DYNAMIC" "Plugin probably cannot be enabled or disabled without IDE restart"; then
  error_wall

elif [ "$VERIFICATION_SUCCESSFUL" -ne 0 ]; then
  # We end the block here, as only `isFailureLevelSet` sets the endgroup for us.
  echo "::endgroup::" # END "Running validations against output..." block.

  echo "::error::======================================================="
  echo "::error::======================================================="
  echo "::error::===                                                 ==="
  echo "::error::===    UNKNOWN FAILURE DURING VERIFICATION CHECK    ==="
  echo "::error::===                                                 ==="
  echo "::error::===   NOTICE!  NOTICE!  NOTICE!  NOTICE!  NOTICE!   ==="
  echo "::error::===                                                 ==="
  echo "::error::===   The verifier exited with a status code of $VERIFICATION_SUCCESSFUL   ==="
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
