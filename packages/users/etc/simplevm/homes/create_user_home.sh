#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/user_setup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <username> [public_key ...]" >&2
    exit 1
fi
SCRIPT_VERSION="1.0.0"
USERNAME="$1"
shift

HOME_DIR="/home/$USERNAME"
SSH_DIR="$HOME_DIR/.ssh"
METADATA_AUTH_KEYS="$SSH_DIR/metadata_authorized_keys"
USER_AUTH_KEYS="$SSH_DIR/authorized_keys"

# Validate username: no 'root', alphanumeric + _ - , max 31 chars
if [[ "$USERNAME" == "root" ]] || [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]; then
    log "Invalid username '$USERNAME'. Exiting."
    exit 1
fi

USER_EXISTS=false
if id "$USERNAME" &>/dev/null; then
    USER_EXISTS=true
    log "User '$USERNAME' already exists."
    log "Reactivating user '$USERNAME' (if disabled)..."

    # unlock account
    usermod -U "$USERNAME" 2>/dev/null || true

    # restore shell
    usermod -s /bin/bash "$USERNAME"
else
    log "Creating user '$USERNAME'..."
    useradd -m -s /bin/bash -U "$USERNAME" || {
        log "Failed to create user '$USERNAME'"
        exit 1
    }
fi

# Ensure home directory exists with correct ownership
if [[ ! -d "$HOME_DIR" ]]; then
    log "Creating missing home directory '$HOME_DIR'..."
    mkdir -p "$HOME_DIR"
    chown "$USERNAME:$USERNAME" "$HOME_DIR"
    chmod 700 "$HOME_DIR"
fi

# Ensure .ssh directory exists with correct ownership
if [[ ! -d "$SSH_DIR" ]]; then
    log "Creating .ssh directory for '$USERNAME'..."
    mkdir -p "$SSH_DIR"
    chown "$USERNAME:$USERNAME" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi

# Create/update metadata_authorized_keys (always updated, even for existing users)
touch "$METADATA_AUTH_KEYS"
chown "$USERNAME:$USERNAME" "$METADATA_AUTH_KEYS"
chmod 600 "$METADATA_AUTH_KEYS"


if [[ $# -gt 0 ]]; then
    log "Setting authorized_keys for '$USERNAME' (create or update)"

    # overwrite with provided keys (source of truth = arguments)
    printf "%s\n" "$@" > "$METADATA_AUTH_KEYS"

else
    log "No keys provided for '$USERNAME' → leaving authorized_keys empty"

    # ensure file is empty but valid
    : > "$METADATA_AUTH_KEYS"
fi
touch "$USER_AUTH_KEYS"

chown "$USERNAME:$USERNAME" "$USER_AUTH_KEYS"
chmod 600 "$USER_AUTH_KEYS"

# Remove user from sudo/wheel/admin groups (prevent privilege escalation)
for grp in sudo wheel admin; do
    if groups "$USERNAME" | grep -qw "$grp"; then
        log "Removing user '$USERNAME' from group '$grp'..."
        gpasswd -d "$USERNAME" "$grp" 2>/dev/null || true
    fi
done

log "User setup completed for '$USERNAME'."
exit 0