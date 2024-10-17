#!/bin/bash

# Define the location of the config file
CONFIG_FILE="/etc/simplevm/metadata_config.env"

# Define GitHub API information
REPO_OWNER="deNBI"
REPO_NAME="metadata-service-roles"

# Fetch the latest release tag using GitHub API
latest_tag=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" | jq -r .tag_name)

# Check if latest_tag was successfully retrieved
if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
  echo "Failed to retrieve the latest release tag from GitHub."
  exit 1
fi

# Construct the URL
base_url="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/refs/tags"
compatibility_json_url="$base_url/$latest_tag/files/compatibility.json"

# Function to update or append the compatibility endpoint
update_or_add_compatibility_endpoint() {
  local config_file=$1
  local new_entry="COMPATIBILITY_JSON_ENDPOINT=$compatibility_json_url"

  # If the file exists, check if the key is present
  if grep -q '^COMPATIBILITY_JSON_ENDPOINT=' "$config_file"; then
    # Update the existing entry
    sed -i "s|^COMPATIBILITY_JSON_ENDPOINT=.*|$new_entry|" "$config_file"
  else
    # Append as a new entry
    echo "$new_entry" >> "$config_file"
  fi
}

# Ensure the config directory exists
mkdir -p "$(dirname "$CONFIG_FILE")"

# Update the metadata_config.env file while preserving existing variables
update_or_add_compatibility_endpoint "$CONFIG_FILE"

echo "Configuration updated successfully with URL: $compatibility_json_url"