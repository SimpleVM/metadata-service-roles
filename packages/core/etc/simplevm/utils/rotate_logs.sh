#!/bin/bash

# Define the log file path, maximum size (default: 10 MB), and cut size (default: 5 MB)
METADATA_LOG_FILE_PATH="/var/log/metadata.log"
MAX_SIZE=${MAX_SIZE:-$((10 * 1024 * 1024))} # Max size in bytes
CUT_SIZE=${CUT_SIZE:-$((5 * 1024 * 1024))}  # Target size in bytes

# Check if the file exists and is a regular file
if [[ -f "$METADATA_LOG_FILE_PATH" ]]; then
    # Get the file size in bytes
    FILE_SIZE=$(stat -c%s "$METADATA_LOG_FILE_PATH")

    # Check if the file size exceeds the maximum size
    if (( FILE_SIZE > MAX_SIZE )); then
        # Use a temporary file and safely handle rotation
        TEMP_FILE="${METADATA_LOG_FILE_PATH}.tmp"

        # Calculate the number of bytes to retain (equal to CUT_SIZE)
        BYTES_TO_RETAIN=$CUT_SIZE

        # Retain only the last BYTES_TO_RETAIN bytes and overwrite the original file
        tail -c "$BYTES_TO_RETAIN" "$METADATA_LOG_FILE_PATH" > "$TEMP_FILE" &&
            mv "$TEMP_FILE" "$METADATA_LOG_FILE_PATH"

        # Log a message to indicate that the file was truncated
        echo "$(date '+%Y-%m-%d %H:%M:%S') - File $METADATA_LOG_FILE_PATH exceeded maximum size ($MAX_SIZE bytes). Truncated to $CUT_SIZE bytes." >> /var/log/metadata_cleanup.log
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - File $METADATA_LOG_FILE_PATH does not exist or is not a regular file." >> /var/log/metadata_cleanup.log
fi
