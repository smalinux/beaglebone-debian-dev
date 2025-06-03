#!/bin/bash
#
# sync_uEnv.sh - Line-by-Line uEnv.txt Update
#
# Updates only specific lines from your local uEnv.txt to remote:
# - Preserves ALL existing content on remote
# - Updates only lines that exist in your local file
# - Adds missing lines from local file
# - Preserves comments and formatting
# - Never touches uname_r= (preserves kernel version)
#

set -e

# Configuration
LOCAL_UENV="./uEnv.txt"
REMOTE_HOST="${REMOTE_HOST:-192.168.0.98}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_UENV="/boot/uEnv.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

show_help() {
    cat << EOF
sync_uEnv.sh - Line-by-Line uEnv.txt Update

Updates individual lines from local uEnv.txt to remote device:
- Preserves ALL existing remote content
- Updates only lines that exist in local file
- Adds missing lines from local file
- Never touches uname_r= (preserves kernel version)

Usage: $0 [command]

Commands:
  update      Update lines from local to remote (default)
  preview     Show what lines would be updated
  backup      Create backup only
  restore     Restore from most recent backup
  show        Show current remote uEnv.txt
  help        Show this help

Environment Variables:
  REMOTE_HOST    Target device IP (default: 192.168.0.98)
  REMOTE_USER    SSH user (default: root)

Local file: $LOCAL_UENV
Remote file: $REMOTE_UENV
EOF
}

check_files() {
    # Check local file exists
    [[ -f "$LOCAL_UENV" ]] || print_error "Local uEnv.txt not found: $LOCAL_UENV"

    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" exit 2>/dev/null; then
        print_error "Cannot connect to $REMOTE_USER@$REMOTE_HOST via SSH"
    fi

    # Check remote file exists
    if ! ssh "$REMOTE_USER@$REMOTE_HOST" "[[ -f $REMOTE_UENV ]]"; then
        print_error "Remote uEnv.txt not found: $REMOTE_UENV"
    fi

    print_success "Files and connectivity OK"
}

create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="/boot/uEnv.txt.backup.$timestamp"

    print_status "Creating backup: $backup_file"

    ssh "$REMOTE_USER@$REMOTE_HOST" "
        cp $REMOTE_UENV $backup_file
        echo 'Backup created: $backup_file'

        # Keep only last 10 backups
        ls -1t /boot/uEnv.txt.backup.* 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
    "

    print_success "Backup completed"
}

get_variable_name() {
    local line="$1"
    # Extract variable name (handle commented lines)
    echo "$line" | sed 's/^[[:space:]]*#*//' | cut -d'=' -f1 | xargs
}

is_variable_line() {
    local line="$1"
    # Check if line contains a variable (var=value format)
    [[ "$line" =~ ^[[:space:]]*#?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*= ]]
}

is_commented() {
    local line="$1"
    [[ "$line" =~ ^[[:space:]]*# ]]
}

preview_changes() {
    print_status "Analyzing what would change..."

    # Download remote file for analysis
    scp "$REMOTE_USER@$REMOTE_HOST:$REMOTE_UENV" "/tmp/remote_uEnv.txt" 2>/dev/null

    echo "=== Changes that would be made ==="
    echo

    local changes_found=false

    # Process each line in local file
    while IFS= read -r local_line; do
        # Skip empty lines
        [[ -n "$local_line" ]] || continue

        if is_variable_line "$local_line"; then
            local var_name=$(get_variable_name "$local_line")

            # Skip uname_r - never touch it
            if [[ "$var_name" == "uname_r" ]]; then
                echo "⏭️  SKIP: $local_line (preserving remote kernel version)"
                continue
            fi

            # Find corresponding line in remote file
            local remote_line=""
            local line_found=false

            while IFS= read -r remote_line_check; do
                if is_variable_line "$remote_line_check"; then
                    local remote_var_name=$(get_variable_name "$remote_line_check")
                    if [[ "$remote_var_name" == "$var_name" ]]; then
                        remote_line="$remote_line_check"
                        line_found=true
                        break
                    fi
                fi
            done < "/tmp/remote_uEnv.txt"

            if [[ "$line_found" == true ]]; then
                if [[ "$local_line" != "$remote_line" ]]; then
                    echo "🔄 UPDATE: $var_name"
                    echo "    FROM: $remote_line"
                    echo "    TO:   $local_line"
                    changes_found=true
                else
                    echo "✅ SAME: $local_line"
                fi
            else
                echo "➕ ADD: $local_line (new variable)"
                changes_found=true
            fi
        else
            echo "📝 COMMENT/OTHER: $local_line (will be added if not present)"
        fi
    done < "$LOCAL_UENV"

    echo
    if [[ "$changes_found" == false ]]; then
        echo "✅ No changes needed - files are in sync!"
    else
        echo "⚠️  Changes found above"
    fi

    rm -f "/tmp/remote_uEnv.txt"
}

update_lines() {
    print_status "Updating lines from local to remote..."

    # Create backup first
    create_backup

    # Show preview
    preview_changes

    echo
    read -p "Apply these updates? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Update cancelled by user"
        exit 0
    fi

    # Upload local file to analyze
    scp "$LOCAL_UENV" "$REMOTE_USER@$REMOTE_HOST:/tmp/local_uEnv.txt"

    # Create update script
    ssh "$REMOTE_USER@$REMOTE_HOST" "
        set -e

        # Function to get variable name
        get_var_name() {
            echo \"\$1\" | sed 's/^[[:space:]]*#*//' | cut -d'=' -f1 | xargs
        }

        # Function to check if line is a variable
        is_variable() {
            [[ \"\$1\" =~ ^[[:space:]]*#?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*= ]]
        }

        echo 'Starting line-by-line updates...'

        # Process each line in local file
        while IFS= read -r local_line; do
            # Skip empty lines
            [[ -n \"\$local_line\" ]] || continue

            if is_variable \"\$local_line\"; then
                var_name=\$(get_var_name \"\$local_line\")

                # Skip uname_r - never touch it
                if [[ \"\$var_name\" == \"uname_r\" ]]; then
                    echo \"SKIP: \$local_line (preserving kernel version)\"
                    continue
                fi

                # Check if variable exists in remote file
                if grep -q \"^[[:space:]]*#*\${var_name}[[:space:]]*=\" $REMOTE_UENV; then
                    # Update existing line
                    echo \"UPDATE: \$var_name\"
                    sed -i \"/^[[:space:]]*#*\${var_name}[[:space:]]*=/c\\\\\$local_line\" $REMOTE_UENV
                else
                    # Add new line at end
                    echo \"ADD: \$local_line\"
                    echo \"\$local_line\" >> $REMOTE_UENV
                fi
            else
                # Handle comments/other lines - add if not present
                if ! grep -Fxq \"\$local_line\" $REMOTE_UENV; then
                    echo \"ADD COMMENT: \$local_line\"
                    echo \"\$local_line\" >> $REMOTE_UENV
                fi
            fi
        done < /tmp/local_uEnv.txt

        # Clean up
        rm -f /tmp/local_uEnv.txt

        echo
        echo 'Updated uEnv.txt:'
        echo '=== START ==='
        cat $REMOTE_UENV
        echo '=== END ==='

        echo
        echo 'File info:'
        ls -la $REMOTE_UENV
    "

    print_success "Lines updated successfully!"
    print_warning "Reboot device to apply changes: ssh $REMOTE_USER@$REMOTE_HOST reboot"
}

restore_backup() {
    print_status "Restoring from most recent backup..."

    ssh "$REMOTE_USER@$REMOTE_HOST" "
        LATEST_BACKUP=\$(ls -1t /boot/uEnv.txt.backup.* 2>/dev/null | head -1)

        if [[ -n \"\$LATEST_BACKUP\" ]]; then
            echo \"Restoring from: \$LATEST_BACKUP\"
            cp \"\$LATEST_BACKUP\" $REMOTE_UENV
            echo \"Restored successfully\"
            echo
            echo \"Current uEnv.txt:\"
            cat $REMOTE_UENV
            echo
            ls -la $REMOTE_UENV
        else
            echo \"No backup files found\"
            exit 1
        fi
    "

    print_success "Backup restored successfully"
}

show_remote() {
    print_status "Current remote uEnv.txt:"

    ssh "$REMOTE_USER@$REMOTE_HOST" "
        echo 'File info:'
        ls -la $REMOTE_UENV
        echo
        echo 'Content:'
        cat $REMOTE_UENV
        echo
        echo 'Available backups:'
        ls -la /boot/uEnv.txt.backup.* 2>/dev/null || echo 'No backups found'
    "
}

main() {
    local command="${1:-update}"

    case "$command" in
        update)
            check_files
            update_lines
            ;;
        preview)
            check_files
            preview_changes
            ;;
        backup)
            check_files
            create_backup
            ;;
        restore)
            restore_backup
            ;;
        show)
            show_remote
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command (use 'help' for usage)"
            ;;
    esac
}

main "$@"
