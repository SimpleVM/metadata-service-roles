#!/bin/bash
chmod 751 /home
set -euo pipefail

LOG_FILE="/var/log/metadata_home_users.log"

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "=== homes-sync wrapper starting ==="

# First, deactivate users no longer in metadata
/etc/simplevm/homes/deactivate_homes.sh && log_message "deactivate_homes completed successfully" || log_message "deactivate_homes.sh returned non-zero, continuing"

# Then, create/update active users
/etc/simplevm/homes/add_user_homes.sh && log_message "add_user_homes completed successfully" || log_message "add_user_homes.sh returned non-zero, continuing"

log_message "=== homes-sync wrapper completed ==="
