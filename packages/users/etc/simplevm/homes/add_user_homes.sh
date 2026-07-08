#!/bin/bash

set -euo pipefail

LOG_FILE="/var/log/metadata_home_users.log"
METADATA_FILE="/etc/simplevm/metadata.json"
SCRIPT_VERSION="1.0.0"

# Function to log messages with timestamps
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

/etc/simplevm/utils/rotate_logs.sh 2>/dev/null || true

if [ ! -f "$METADATA_FILE" ]; then
  log_message "Metadata file $METADATA_FILE not found. Exiting."
  exit 0
fi

response=$(cat "$METADATA_FILE")
log_message "Metadata loaded"

# Validate JSON
if ! echo "$response" | jq . >/dev/null 2>&1; then
  log_message "Invalid JSON response. Exiting."
  exit 0
fi

# Check version compatibility
if ! /etc/simplevm/utils/check_version.sh "metadata_version" "$SCRIPT_VERSION" "$(echo "$response" | jq -r '.metadata_version')"; then
  log_message "metadata_version $(echo "$response" | jq -r '.metadata_version') incompatible. Exiting."
  exit 1
fi

if ! /etc/simplevm/utils/check_version.sh "home_users" "$SCRIPT_VERSION" "$(echo "$response" | jq -r '.home_user_version')"; then
  log_message "home_users version $(echo "$response" | jq -r '.home_user_version') incompatible. Exiting."
  exit 1
fi

# Check if home_users exists
if ! echo "$response" | jq -e ".home_users" >/dev/null 2>&1; then
  log_message "No 'home_users' in metadata. Skipping."
  exit 0
fi

# Iterate over all home_users
user_count=$(echo "$response" | jq '.home_users | length')
for (( idx=0; idx<user_count; idx++ )); do
  username=$(echo "$response" | jq -r ".home_users[$idx].unix_name")

  if [ -z "$username" ] || [ "$username" = "null" ]; then
    log_message "Skipping entry $idx: no unix_name"
    continue
  fi

  # Extract public keys for this user
  public_keys=$(echo "$response" | jq -r ".home_users[$idx].public_keys[]?" 2>/dev/null)

  # Build key arguments
  key_args=()
  if [ -n "$public_keys" ]; then
    while IFS= read -r key; do
      [ -n "$key" ] && key_args+=("$key")
    done <<< "$public_keys"
    log_message "Processing user '$username' with ${#key_args[@]} key(s)"
  else
    log_message "Processing user '$username' with no public keys"
  fi

  # Call the creation script
  if [ ${#key_args[@]} -gt 0 ]; then
    /etc/simplevm/homes/create_user_home.sh "$username" "${key_args[@]}"
  else
    /etc/simplevm/homes/create_user_home.sh "$username"
  fi
  result=$?

  if [ $result -ne 0 ]; then
    log_message "ERROR: create_user_home.sh failed for '$username' (exit code $result)"
  else
    log_message "Successfully created/updated home for user '$username'"
  fi
done

log_message "Home users update completed"
