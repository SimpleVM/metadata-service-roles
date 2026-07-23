#!/bin/bash
LOG_FILE="/var/log/metadata.log"

# Ensure arguments are provided
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 FUNCTION_KEY SCRIPT_VERSION METADATA_VERSION"
  exit 1
fi

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}


FUNCTION_KEY="$1"
SCRIPT_VERSION="$2"
METADATA_VERSION="$3"

# Retrieve the COMPATIBILITY_JSON_ENDPOINT from the configuration file
COMPATIBILITY_JSON_ENDPOINT=$(grep '^COMPATIBILITY_JSON_ENDPOINT=' "/etc/simplevm/metadata_config.env" | cut -d '=' -f 2-)

# Check if the endpoint was not found or is empty
if [ -z "$COMPATIBILITY_JSON_ENDPOINT" ]; then
  log_message "COMPATIBILITY_JSON_ENDPOINT is not set in /etc/simplevm/metadata_config.env"
  exit 1
fi

# Function to check version compatibility
check_version() {
  local function_key=$1
  local script_version=$2
  local metadata_version=$3

  log_message "Version check: function_key=$function_key script_version=$script_version metadata_version=$metadata_version"

  # Fetch the JSON from the specified URL
  local json_data
  json_data=$(curl -s "$COMPATIBILITY_JSON_ENDPOINT")
  log_message "Compatibility JSON received: $json_data"
  # Ensure the JSON data is valid
  if ! echo "$json_data" | jq empty; then
    log_message "Invalid JSON data retrieved from $COMPATIBILITY_JSON_ENDPOINT"
    exit 1
  fi

  # Extract compatible versions
  local compatible_versions
  compatible_versions=$(echo "$json_data" | jq -r \
    --arg function_key "$function_key" \
    --arg script_version "$script_version" \
    'if .[$function_key][$script_version] then .[$function_key][$script_version][] else empty end')

  log_message "Compatible metadata versions from endpoint: $(echo "$compatible_versions" | tr '\n' ' ')"

  # Check if a null result occurred
  if [ -z "$compatible_versions" ]; then
    log_message "No compatible versions found for function_key=$function_key script_version=$script_version"
    return 1
  fi

  # Check if metadata version is compatible
  for version in $compatible_versions; do
    if [[ "$version" == "$metadata_version" ]]; then
      log_message "Match found: metadata_version $metadata_version is compatible"
      return 0
    fi
  done

  log_message "No match: metadata_version $metadata_version is NOT in compatible list"
  return 1
}

# Check and perform the version check
if check_version "$FUNCTION_KEY" "$SCRIPT_VERSION" "$METADATA_VERSION"; then
  log_message "Versions are compatible (script=$SCRIPT_VERSION metadata=$METADATA_VERSION)."
else
  log_message "Versions are NOT compatible (script=$SCRIPT_VERSION metadata=$METADATA_VERSION)."
fi