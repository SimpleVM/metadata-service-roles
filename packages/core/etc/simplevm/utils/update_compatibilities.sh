#!/bin/bash
source /etc/simplevm/metadata_config.env
# Define the location of the config file
CONFIG_FILE="/etc/simplevm/metadata_config.env"

# Define GitHub repository information
REPO_OWNER="simplevm"
REPO_NAME="metadata-service-roles"

# Function to retrieve the tag from the redirect URL
get_latest_tag_from_redirect() {
  local redirect_url="https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest"
  local final_url

  # Follow the redirect to get the final URL and extract the tag
  final_url=$(curl -s -o /dev/null -w "%{url_effective}" -L "$redirect_url")
  local prefix="https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/"
  echo "${final_url#$prefix}"
}

# Fetch the latest release tag using GitHub API
latest_tag=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" | jq -r .tag_name)

# Check if latest_tag was successfully retrieved
if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
  echo "Failed to retrieve the latest release tag from GitHub API. Using redirect method."
  # Fallback to retrieving the tag using the redirect method
  latest_tag=$(get_latest_tag_from_redirect)
  # Check if the fallback also failed
  if [ -z "$latest_tag" ]; then
    echo "Failed to retrieve the latest release tag from redirect. Exiting."
    exit 1
  fi
fi

# Construct the URL
base_url="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME"
compatibility_json_url="$base_url/$latest_tag/files/compatibility.json"

# Update or add the COMPATIBILITY_JSON_ENDPOINT in the metadata_config.env file
if grep -q "^COMPATIBILITY_JSON_ENDPOINT=" "$CONFIG_FILE"; then
  # If the entry exists, update it
  sed -i "s|^COMPATIBILITY_JSON_ENDPOINT=.*|COMPATIBILITY_JSON_ENDPOINT=$compatibility_json_url|" "$CONFIG_FILE"
else
  # If the entry does not exist, append it
  echo "COMPATIBILITY_JSON_ENDPOINT=$compatibility_json_url" >> "$CONFIG_FILE"
fi

echo "Configuration updated successfully with URL: $compatibility_json_url"