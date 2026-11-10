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
    local new_interval="$1"
    local current_interval

    current_interval=$(grep '^OnUnitActiveSec=' "$TIMER_PATH" | cut -d= -f2-)

    if [[ "$current_interval" == "$new_interval" ]]; then
        echo "Timer interval already set to $new_interval"
        return
    fi

    echo "Updating timer interval: ${current_interval:-<unset>} -> $new_interval"

    if grep -q '^OnUnitActiveSec=' "$TIMER_PATH"; then
        sudo sed -i "s/^OnUnitActiveSec=.*/OnUnitActiveSec=$new_interval/" "$TIMER_PATH"
    else
        echo "OnUnitActiveSec=$new_interval" | sudo tee -a "$TIMER_PATH" > /dev/null
    fi

    sudo systemctl daemon-reload
    sudo systemctl restart simplevm-metadata-synchronizer.timer
}

extend_interval() {
    # Calculate the new interval
    new_interval=$((current_interval + 5))
    # Ensure we do not exceed the max interval
    if (( new_interval > MAX_INTERVAL )); then
        echo "Timer already got extended to max"
        return
    fi
    log_message "Extending timer interval to ${new_interval} minutes"
    set_new_interval "${new_interval}min"
}

reset_interval() {
    log_message "Resetting timer interval to default: $DEFAULT_INTERVAL"
    set_new_interval "${DEFAULT_INTERVAL}min"
}

/etc/simplevm/utils/rotate_logs.sh
/etc/simplevm/utils/update_compatibilities.sh



source /etc/simplevm/metadata_config.env

OPENSTACK_ID=$(curl -s http://169.254.169.254/openstack/latest/meta_data.json | jq -r '.uuid')
# Construct the URL with openstack_id query param
INFO_ENDPOINT_URL="${METADATA_INFO_ENDPOINT}?openstack_id=${OPENSTACK_ID}"

# Define the auth header with the token
AUTH_HEADER="auth_token: ${METADATA_ACCESS_TOKEN}"

# Get real metadata endpoint from config (with TTL so a changed endpoint is picked up)
CONFIG_FILE="/etc/simplevm/metadata_config.env"
ENDPOINT_TTL_SECONDS=43200  # 12 hours

REAL_METADATA_ENDPOINT=$(grep '^REAL_METADATA_ENDPOINT=' "${CONFIG_FILE}" | head -n1 | cut -d '=' -f 2-)
REAL_METADATA_ENDPOINT_TTL=$(grep '^REAL_METADATA_ENDPOINT_TTL=' "${CONFIG_FILE}" | head -n1 | cut -d '=' -f 2-)

now=$(date +%s)
endpoint_age=$(( now - ${REAL_METADATA_ENDPOINT_TTL:-0} ))

# Refresh REAL_METADATA_ENDPOINT from the info endpoint and update the cache.
# Returns 0 on success (REAL_METADATA_ENDPOINT is then set), 1 if the info
# endpoint is unreachable or returns an invalid response.
refresh_metadata_endpoint() {
  local info_response now_ts
  info_response=$(curl -s --connect-timeout 5 --max-time 20 -X GET "${INFO_ENDPOINT_URL}" -H "${AUTH_HEADER}")

  if [ $? -ne 0 ] || ! jq -e '.metadata_endpoint' <<< "${info_response}" &> /dev/null; then
    return 1
  fi

  REAL_METADATA_ENDPOINT=$(jq -r '.metadata_endpoint' <<< "${info_response}")
  now_ts=$(date +%s)

  # Update the cached endpoint + TTL (dedup: replace existing lines instead of appending)
  if grep -q '^REAL_METADATA_ENDPOINT=' "${CONFIG_FILE}"; then
    sed -i "s|^REAL_METADATA_ENDPOINT=.*|REAL_METADATA_ENDPOINT=${REAL_METADATA_ENDPOINT}|" "${CONFIG_FILE}"
  else
    echo "REAL_METADATA_ENDPOINT=${REAL_METADATA_ENDPOINT}" >> "${CONFIG_FILE}"
  fi
  if grep -q '^REAL_METADATA_ENDPOINT_TTL=' "${CONFIG_FILE}"; then
    sed -i "s|^REAL_METADATA_ENDPOINT_TTL=.*|REAL_METADATA_ENDPOINT_TTL=${now_ts}|" "${CONFIG_FILE}"
  else
    echo "REAL_METADATA_ENDPOINT_TTL=${now_ts}" >> "${CONFIG_FILE}"
  fi
  return 0
}

# Cache is missing or stale -> refresh from the info endpoint
if [ -z "${REAL_METADATA_ENDPOINT}" ] || (( endpoint_age > ENDPOINT_TTL_SECONDS )); then
  if ! refresh_metadata_endpoint; then
    if [ -n "${REAL_METADATA_ENDPOINT}" ]; then
      # Stale cache: keep using it rather than failing the whole sync
      log_message "WARN: Failed to refresh metadata endpoint, using cached endpoint (age ${endpoint_age}s)"
    else
      log_message "Error: No metadata endpoint available (no cache, info endpoint unreachable)"
      reset_interval
      exit 1
    fi
  fi
fi

# Fetch the actual metadata from the extracted endpoint

LOCAL_IP=$(hostname -I | awk '{print $1}')
full_response=$(curl -s --connect-timeout 5 --max-time 20 -o - -w "%{http_code}" -X GET "${REAL_METADATA_ENDPOINT}/metadata/${LOCAL_IP}" -H "${AUTH_HEADER}")

response_status="${full_response: -3}"
metadata_response="${full_response%???}"

if [ $? -ne 0 ]; then
  log_message "Error: Failed to fetch metadata"
  reset_interval
  exit 1
fi



# Check the status code and act accordingly
if [ "$response_status" = "000" ]; then
  # No HTTP response at all: endpoint unreachable (DNS/connection refused/timeout).
  # The pinned endpoint is likely gone -> drop the cache and immediately try
  # to fetch a fresh endpoint from the info endpoint.
  echo "Error: Metadata endpoint unreachable (no HTTP response). Invalidating cached endpoint..."
  sed -i 's|^REAL_METADATA_ENDPOINT=.*|REAL_METADATA_ENDPOINT=|' "${CONFIG_FILE}"
  sed -i 's|^REAL_METADATA_ENDPOINT_TTL=.*|REAL_METADATA_ENDPOINT_TTL=|' "${CONFIG_FILE}"
  REAL_METADATA_ENDPOINT=""
  log_message "Invalidated cached metadata endpoint: endpoint unreachable"

  if refresh_metadata_endpoint; then
    log_message "Recovered: fetched fresh metadata endpoint from info endpoint"
  else
    log_message "Failed to fetch fresh metadata endpoint, will retry on next run"
    extend_interval
    exit 1
  fi

  # Retry the metadata fetch against the recovered endpoint
  full_response=$(curl -s --connect-timeout 5 --max-time 20 -o - -w "%{http_code}" -X GET "${REAL_METADATA_ENDPOINT}/metadata/${LOCAL_IP}" -H "${AUTH_HEADER}")
  response_status="${full_response: -3}"
  metadata_response="${full_response%???}"
  # Fall through to the status handling below

elif [ "$response_status" -eq 200 ]; then
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

elif [ "$response_status" -eq 400 ]; then
  echo "Error: Bad request sent to the server. Extending interval..."
  extend_interval
  exit 1

elif [ "$response_status" -eq 403 ]; then
  echo "Error: Forbidden request. Not allowed to access this resource. Extending interval..."
  extend_interval
  exit 1
    

elif [ "$response_status" -eq 404 ]; then
  # A 404 from the pinned endpoint usually means it was renamed/removed.
  # Drop the cached endpoint and immediately try to fetch a fresh one from
  # the info endpoint.
  echo "Error: 404 from metadata endpoint, invalidating cached endpoint. Resetting interval..."
  sed -i 's|^REAL_METADATA_ENDPOINT=.*|REAL_METADATA_ENDPOINT=|' "${CONFIG_FILE}"
  sed -i 's|^REAL_METADATA_ENDPOINT_TTL=.*|REAL_METADATA_ENDPOINT_TTL=|' "${CONFIG_FILE}"
  REAL_METADATA_ENDPOINT=""
  log_message "Invalidated cached metadata endpoint after 404"

  if refresh_metadata_endpoint; then
    log_message "Recovered: fetched fresh metadata endpoint from info endpoint"
  else
    log_message "Failed to fetch fresh metadata endpoint, will retry on next run"
    reset_interval
    exit 1
  fi

  # Retry the metadata fetch against the recovered endpoint
  full_response=$(curl -s --connect-timeout 5 --max-time 20 -o - -w "%{http_code}" -X GET "${REAL_METADATA_ENDPOINT}/metadata/${LOCAL_IP}" -H "${AUTH_HEADER}")
  response_status="${full_response: -3}"
  metadata_response="${full_response%???}"
  # Fall through to the status handling below

elif [ "$response_status" -eq 429 ]; then
  echo "Error: Too many requests received from this client. Extending interval..."
  extend_interval
  exit 1

elif [ "$response_status" -eq 503 ] || [ "$response_status" -eq 504 ]; then
  echo "Error: Service unavailable or gateway timeout. Extending interval..."
  extend_interval
  exit 1

elif [ "$response_status" -eq 500 ]; then
  echo "Internal server error. Resetting interval..."
  reset_interval
  exit 1

else
  echo "Unexpected error or server condition. HTTP Status: $response_status. Resetting interval..."
  reset_interval
  exit 1
fi



