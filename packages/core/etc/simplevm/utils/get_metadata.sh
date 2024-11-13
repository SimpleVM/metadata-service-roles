#!/bin/bash

/etc/simplevm/utils/update_compatibilities.sh

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
        echo "Error: Failed to fetch metadata endpoint"
        exit 1
    fi

    # Validate the JSON response
    if ! jq -e '.metadata_endpoint' <<< "${info_response}" &> /dev/null; then
        echo "Error: Invalid JSON response from metadata endpoint"
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
    echo "Error: Failed to fetch metadata"
    exit 1
fi

echo "${metadata_response}"
