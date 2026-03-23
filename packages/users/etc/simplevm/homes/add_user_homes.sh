#!/bin/bash
# Path to the log file
LOG_FILE="/var/log/metadata_home_users.log"
/etc/simplevm/utils/rotate_logs.sh

# Script version and affected keys
SCRIPT_VERSION="1.0.0"
SCRIPT_DATA=("home_users")

# Function to log messages with timestamps
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Read metadata from JSON file
METADATA_FILE="/etc/simplevm/metadata.json"
if [ ! -f "$METADATA_FILE" ]; then
  log_message "Metadata file $METADATA_FILE not found. Exiting."
  exit 0
fi

response=$(cat "$METADATA_FILE")
log_message "Response from metadata file: $response"

# Validate JSON
if ! echo "$response" | jq . >/dev/null 2>&1; then
  log_message "Invalid JSON response. Exiting."
  exit 0
fi

# Extract versions
metadata_version=$(echo "$response" | jq -r '.metadata_version')
home_users_version=$(echo "$response" | jq -r '.home_user_version')

log_message "Metadata version: $metadata_version"
log_message "Home users version: $home_users_version"

# Check version compatibility
if ! /etc/simplevm/utils/check_version.sh "metadata_version" "$SCRIPT_VERSION" "$metadata_version"; then
  log_message "metadata_version $metadata_version incompatible. Exiting."
  exit 1
fi

if ! /etc/simplevm/utils/check_version.sh "home_users" "$SCRIPT_VERSION" "$home_users_version"; then
  log_message "home_users version $home_users_version incompatible. Exiting."
  exit 1
fi

# Check if home_users exists
if ! echo "$response" | jq -e ".home_users" >/dev/null 2>&1; then
  log_message "No 'home_users' in metadata. Skipping."
  exit 0
fi

# Count users
user_count=$(echo "$response" | jq -r '.home_users | length')
log_message "Found $user_count home_users"

# Process each user
for ((i=0; i<user_count; i++)); do
  username=$(echo "$response" | jq -r ".home_users[$i].unix_name")
  # Skip if username is empty
  if [ -z "$username" ] || [ "$username" = "null" ]; then
    log_message "Warning: Missing or null 'name' for home_user #$i. Skipping."
    continue
  fi

  # Extract public keys as separate args (preserving multi-line keys if needed)
  keys_json=".home_users[$i].public_keys[]?"
  public_keys=$(echo "$response" | jq -r "$keys_json")

  # If no keys, skip this user (create_user_home.sh may handle it, but let's be explicit)
  if [ -z "$public_keys" ]; then
    log_message "No public keys for user '$username'. Skipping."
    continue
  fi

  log_message "Processing user '$username' with $(echo "$public_keys" | wc -l) key(s)"

  # Prepare keys as arguments: quote each key to handle multiline/whitespace
  key_args=()
  while IFS= read -r key; do
    [ -n "$key" ] && key_args+=("$key")
  done <<< "$public_keys"

  # Call the creation script (passing keys as separate args)
  /etc/simplevm/homes/create_user_home.sh "$username" "${key_args[@]}"
  result=$?

  if [ $result -ne 0 ]; then
    log_message "ERROR: create_user_home.sh failed for '$username' (exit code $result)"
  else
    log_message "Successfully created/updated home for user '$username'"
  fi
done

log_message "Home users update completed"