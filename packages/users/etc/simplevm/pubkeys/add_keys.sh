#!/bin/bash

# Path to the log file
LOG_FILE="/var/log/metadata.log"

/etc/simplevm/utils/rotate_logs.sh

# Script version and affected keys from the metadata-response
SCRIPT_VERSION="1.0.0"
SCRIPT_DATA=("userdata")

# Function to log messages with timestamps
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Set default user to 'ubuntu' if not provided
USER_TO_SET="${USER_TO_SET:-ubuntu}"
USER_HOME=/home/${USER_TO_SET}

# Read metadata from JSON file
METADATA_FILE="/etc/simplevm/metadata.json"
METADATA_AUTHORIZED_KEYS_FILE="$USER_HOME/.ssh/metadata_authorized_keys"
if [ ! -f "$METADATA_FILE" ]; then
  log_message "Metadata file $METADATA_FILE not found. Exiting."
  exit 1
fi

response=$(cat "$METADATA_FILE")

# Log the JSON response for debugging purposes
log_message "Response from metadata file: $response"

# Check if the response is valid JSON
if ! echo "$response" | jq . >/dev/null 2>&1; then
  log_message "Invalid JSON response. Exiting."
  exit 1
fi

# Extract the VERSION from the JSON response
metadata_version=$(echo "$response" | jq -r '.userdata.VERSION')

# Log the extracted VERSION
log_message "Metadata version for userdata: $metadata_version"

# Check if the metadata versions are compatible
for key in "${SCRIPT_DATA[@]}"; do
  # Check if the key exists in the JSON response
  if ! echo "$response" | jq -e ".${key}" >/dev/null 2>&1; then
    log_message "Needed data $key missing in metadata response. Exiting."
    exit 1
  fi

  # Extract the VERSION for the given key from the JSON response
  metadata_version=$(echo "$response" | jq -r ".${key}.VERSION")

  # Log the extracted VERSION
  log_message "$key version: $metadata_version"

  # Check if the metadata version is compatible
  if ! /etc/simplevm/utils/check_version.sh "$key" "$SCRIPT_VERSION" "$metadata_version"; then
    log_message "$key version $metadata_version is not compatible. Exiting."
    exit 1
  fi
done

# Extract public_keys from the nested JSON structure
public_keys=$(echo "$response" | jq -r '.userdata.data[] | .public_keys[]?')

# Check if public_keys is empty
if [ -z "$public_keys" ]; then
  log_message "No public keys found. metadata_authorized_keys file not updated."
  exit 0
fi

# Ensure the .ssh directory and metadata_authorized_keys file exist
mkdir -p "$USER_HOME/.ssh"
touch "$METADATA_AUTHORIZED_KEYS_FILE"

# Set the correct permissions for the .ssh directory and its contents
chown -R $USER_TO_SET:$USER_TO_SET "$USER_HOME/.ssh"

# Temp file to store the new keys list
temp_file=$(mktemp)

# Write the new public keys to the temp file
while IFS= read -r key; do
  echo "$key"
done <<< "$public_keys" > "$temp_file"

# Compare old keys with new keys and update `metadata_authorized_keys`
mv "$temp_file" "$METADATA_AUTHORIZED_KEYS_FILE"

# Set the correct permissions for the metadata_authorized_keys file
chown $USER_TO_SET:$USER_TO_SET "$METADATA_AUTHORIZED_KEYS_FILE"

# Log the update operation
log_message "Updated metadata_authorized_keys with the latest public keys from metadata"

# Confirmation of new keys added (or removed)
log_message "Script execution completed"