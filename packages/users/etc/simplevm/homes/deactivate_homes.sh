#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

LOG_FILE="/var/log/metadata_home_users_cleanup.log"
METADATA_FILE="/etc/simplevm/metadata.json"
SCRIPT_VERSION="1.0.0"

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting home_users cleanup"

# Validate file
if [ ! -f "$METADATA_FILE" ]; then
  log_message "ERROR: metadata file missing"
  exit 1
fi

# ---------------------------------------------------
# 1. Load VALID users from JSON (deduplicated)
# ---------------------------------------------------
mapfile -t valid_users < <(
  jq -r '.home_users[]?.unix_name // empty' "$METADATA_FILE" \
  | sort -u
)

if [ "${#valid_users[@]}" -eq 0 ]; then
  log_message "WARNING: no valid home_users found in metadata, disabling all non-system /home users"
  valid_users=("__none__")
fi

log_message "Loaded ${#valid_users[@]} valid home_users"

# ---------------------------------------------------
# 2. Build lookup (fast exact match)
# ---------------------------------------------------
declare -A allowed
if [ "${valid_users[0]}" = "__none__" ]; then
  # No home_users in metadata — everyone is an orphan
  log_message "No valid home_users in metadata — all /home users will be disabled"
else
  for u in "${valid_users[@]}"; do
    allowed["$u"]=1
  done
fi

# ---------------------------------------------------
# 3. Scan system users
# ---------------------------------------------------
while IFS=: read -r user _ uid _ _ home _; do

  # only real users
  if [ "$uid" -lt 1000 ]; then
    continue
  fi

  # safety: ubuntu never touched
  if [ "$user" = "ubuntu" ]; then
    continue
  fi

  # only /home users
  if [[ "$home" != /home/* ]]; then
    continue
  fi

  # ---------------------------------------------------
  # 4. Check if user exists in metadata
  # ---------------------------------------------------
  if [[ -z "${allowed[$user]+x}" ]]; then
    log_message "ORPHAN USER: $user → disabling"

    # lock account
    usermod -L "$user" || log_message "failed locking $user"

    # disable shell login
    usermod -s /usr/sbin/nologin "$user" || true

    # optional SSH cleanup
    if [ -d "$home/.ssh" ]; then
      rm -f "$home/.ssh/metadata_authorized_keys"

      log_message "removed ssh keys for $user"
    fi
  fi

done < /etc/passwd

log_message "Home_users cleanup completed"