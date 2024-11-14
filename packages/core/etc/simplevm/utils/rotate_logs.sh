#!/bin/bash

# Define the log file path
LOG_FILE="/var/log/metadata.log"


# Check if the file exists
if [[ -e "$LOG_FILE" ]]; then
    # Get the file size in bytes
    FILE_SIZE=$(stat -c%s "$LOG_FILE")

    # Convert 10 MB to bytes for comparison
    MAX_SIZE=$((10 * 1024 * 1024))
    # Check if the file size exceeds 10 MB
    if (( FILE_SIZE > MAX_SIZE )); then
        # Remove the top 100 lines from the file
        # and overwrite the file with the result
        tail -n +101 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi

fi
