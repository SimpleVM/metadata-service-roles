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

# Update the metadata_config.env file
echo "COMPATIBILITY_JSON_ENDPOINT=$compatibility_json_url" > $CONFIG_FILE

echo "Configuration updated successfully with URL: $compatibility_json_url"
