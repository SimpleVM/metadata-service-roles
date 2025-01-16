#!/bin/bash

LOG_FILE="/var/log/metadata.log"
METADATA_OUTPUT_FILE="/etc/simplevm/metadata.json"

/etc/simplevm/utils/rotate_logs.sh
/etc/simplevm/utils/update_compatibilities.sh

source /etc/simplevm/metadata_config.env

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Construct the URL with hostname query param
INFO_ENDPOINT_URL="${METADATA_INFO_ENDPOINT}?hostname=$(hostname)"

# Define the auth header with the token
AUTH_HEADER="auth_token: ${METADATA_ACCESS_TOKEN}"

# Get real metadata endpoint from config if available
REAL_METADATA_ENDPOINT=$(grep '^REAL_METADATA_ENDPOINT=' "/etc/simplevm/metadata_config.env" | cut -d '=' -f 2-)

if [ -z "${REAL_METADATA_ENDPOINT}" ]; then
  # Fetch the JSON response from the info endpoint to get real metadata endpoint
  info_response=$(curl -s -X GET "${INFO_ENDPOINT_URL}" -H "${AUTH_HEADER}")

  if [ $? -ne 0 ]; then
    log_message "Error: Failed to fetch metadata endpoint"
    exit 1
  fi

  # Validate the JSON response
  if ! jq -e '.metadata_endpoint' <<< "${info_response}" &> /dev/null; then
    log_message "Error: Invalid JSON response from metadata endpoint"
    exit 1
  fi

  # Extract the actual metadata endpoint from the response
  REAL_METADATA_ENDPOINT=$(jq -r '.metadata_endpoint' <<< "${info_response}")

  # Save real metadata endpoint to config
  echo "REAL_METADATA_ENDPOINT=${REAL_METADATA_ENDPOINT}" >> "/etc/simplevm/metadata_config.env"
fi

# Fetch the actual metadata from the extracted endpoint
LOCAL_IP=$(hostname -I | awk '{print $1}')
metadata_response=$(curl -s -X GET "${REAL_METADATA_ENDPOINT}/metadata/${LOCAL_IP}" -H "${AUTH_HEADER}")

if [ $? -ne 0 ]; then
  log_message "Error: Failed to fetch metadata"
  exit 1
fi

# Write the metadata to a temporary file
TMP_FILE="${METADATA_OUTPUT_FILE}.tmp"
echo "${metadata_response}"| jq > "${TMP_FILE}"

# Rename the temporary file to the original filename
if mv -f "${TMP_FILE}" "${METADATA_OUTPUT_FILE}"; then
  log_message "Metadata saved to ${METADATA_OUTPUT_FILE}"
else
  log_message "Error: Failed to save metadata to ${METADATA_OUTPUT_FILE}"
fi

### we need to add a service that pulls the data automatically