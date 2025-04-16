#!/bin/bash

LOG_FILE="/var/log/metadata.log"
METADATA_OUTPUT_FILE="/etc/simplevm/metadata.json"

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

TIMER_PATH="/etc/systemd/system/simplevm-metadata-synchronizer.timer"

DEFAULT_INTERVAL=5
MAX_INTERVAL=15

current_interval=$(grep '^OnUnitActiveSec=' $TIMER_PATH | cut -d= -f2 | sed 's/min//')
log_message "This is my interval: ${current_interval}"


set_new_interval() {
    # Update the timer file
    echo "Running: sed -i 's/^OnUnitActiveSec=.*/OnUnitActiveSec=$1/' $TIMER_PATH"
    sudo sed -i "s/^OnUnitActiveSec=.*/OnUnitActiveSec=$1/" $TIMER_PATH
    # Reload systemd to apply changes
    sudo systemctl daemon-reload
    # Restart the timer with the new interval
    sudo systemctl restart simplevm-metadata-synchronizer.timer
}

extend_interval() {
    # Calculate the new interval
    new_interval=$((current_interval + 5))
    # Ensure we do not exceed the max interval
    if (( new_interval > MAX_INTERVAL )); then
        echo "Timer already got extended to max"
    fi
    log_message "Extending timer interval to ${new_interval} minutes"
    set_new_interval "${new_interval}min"
}

reset_interval() {
    log_message "Resetting timer interval to default: $DEFAULT_INTERVAL"
    set_new_interval "${DEFAULT_INTERVAL}min"
}

/etc/simplevm/utils/rotate_logs.sh
#/etc/simplevm/utils/update_compatibilities.sh



source /etc/simplevm/metadata_config.env


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
    reset_interval
    exit 1  
  fi

  # Validate the JSON response
  if ! jq -e '.metadata_endpoint' <<< "${info_response}" &> /dev/null; then
    log_message "Error: Invalid JSON response from metadata endpoint"
    reset_interval
    exit 1
  fi

  # Extract the actual metadata endpoint from the response
  REAL_METADATA_ENDPOINT=$(jq -r '.metadata_endpoint' <<< "${info_response}")

  # Save real metadata endpoint to config
  echo "REAL_METADATA_ENDPOINT=${REAL_METADATA_ENDPOINT}" >> "/etc/simplevm/metadata_config.env"
fi

# Fetch the actual metadata from the extracted endpoint

LOCAL_IP=$(hostname -I | awk '{print $1}')
full_response=$(curl -s -o - -w "%{http_code}" -X GET "${REAL_METADATA_ENDPOINT}/metadata/${LOCAL_IP}" -H "${AUTH_HEADER}")

response_status="${full_response: -3}"
metadata_response="${full_response%???}"
metadata_response=$(curl -s -X GET "${REAL_METADATA_ENDPOINT}/metadata/${LOCAL_IP}" -H "${AUTH_HEADER}")

if [ $? -ne 0 ]; then
  log_message "Error: Failed to fetch metadata"
  reset_interval
  exit 1
fi



# Check the status code and act accordingly
if [ "$response_status" -eq 200 ]; then
  # Successful response; proceed to any further processing if needed
  # Write the metadata to a temporary file
  TMP_FILE="${METADATA_OUTPUT_FILE}.tmp"
  echo "${metadata_response}"| jq > "${TMP_FILE}"

  # Rename the temporary file to the original filename
  if mv -f "${TMP_FILE}" "${METADATA_OUTPUT_FILE}"; then
    log_message "Metadata saved to ${METADATA_OUTPUT_FILE}"
    reset_interval
    exit 0

  else
    log_message "Error: Failed to save metadata to ${METADATA_OUTPUT_FILE}"
    reset_interval
    exit 1
  fi

elif [ "$response_status" -eq 400 ] || [ "$response_status" -eq 403 ]; then
    echo "Error: Too many requests sent to the server. Extending interval..."
    extend_interval
    exit 1

elif [ "$response_status" -eq 404 ]; then
    echo "Key not found in the response."
    reset_interval
    exit 1

elif [ "$response_status" -eq 503 ] || [ "$response_status" -eq 504 ]; then
    echo "Service unavailable or gateway timeout. Extending interval..."
    extend_interval
    exit 1

elif [ "$response_status" -eq 500 ]; then
    echo "Internal server error. Resetting interval..."
    reset_interval
    exit 1

else
    echo "Unexpected error or server condition. HTTP Status: $response_status"
    reset_interval
    exit 1
fi



