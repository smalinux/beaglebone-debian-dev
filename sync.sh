#!/bin/bash

# =============================================================================
# BeagleBone Rsync Script - Sync Specific Files
# =============================================================================
#
# DESCRIPTION:
#   Efficiently sync specific files from BeagleBone using rsync instead of
#   mounting the entire filesystem or manual copying.
#
# PREREQUISITES:
#   1. SSH key authentication set up:
#      ssh-keygen -t rsa -b 4096
#      ssh-copy-id debian@192.168.0.98
#
#   2. Test SSH connection:
#      ssh debian@192.168.0.98
#
# USAGE:
#   ./beaglebone_sync.sh [pull|push|status]
#
# =============================================================================

# Configuration
REMOTE_USER="root"
REMOTE_HOST="192.168.0.98"
LOCAL_BASE="./target"

# File list - Add/remove files as needed
FILES_TO_SYNC=(
    "boot/uEnv.txt"
    "src/"
    "opt/source/dtb-5.10-ti/src/arm/am335x-boneblack.dts"
    "/proc/config.gz"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check SSH connection
check_connection() {
    print_status "Testing SSH connection to $REMOTE_USER@$REMOTE_HOST..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" exit 2>/dev/null; then
        print_success "SSH connection OK"
        return 0
    else
        print_error "Cannot connect to $REMOTE_USER@$REMOTE_HOST"
        echo "Please check:"
        echo "  1. BeagleBone is powered on and connected"
        echo "  2. SSH keys are set up: ssh-copy-id $REMOTE_USER@$REMOTE_HOST"
        echo "  3. IP address is correct: $REMOTE_HOST"
        return 1
    fi
}

# Pull files from BeagleBone to local
pull_files() {
    print_status "Pulling files from BeagleBone..."

    # Create local target directory
    mkdir -p "$LOCAL_BASE"

    local success_count=0
    local total_count=${#FILES_TO_SYNC[@]}

    for file_path in "${FILES_TO_SYNC[@]}"; do
        print_status "Syncing: $file_path"

        # Create local directory structure
        local_dir="$LOCAL_BASE/$(dirname "$file_path")"
        mkdir -p "$local_dir"

        # Sync with rsync
        if rsync -avz --progress \
            "$REMOTE_USER@$REMOTE_HOST:/$file_path" \
            "$LOCAL_BASE/$file_path" 2>/dev/null; then
            print_success "✓ $file_path"
            ((success_count++))
        else
            print_warning "✗ Failed to sync $file_path (file may not exist)"
        fi
    done

    echo
    print_success "Sync complete: $success_count/$total_count files synced"
}

# Push files from local to BeagleBone
push_files() {
    print_status "Pushing files to BeagleBone..."

    local success_count=0
    local total_count=0

    for file_path in "${FILES_TO_SYNC[@]}"; do
        local_file="$LOCAL_BASE/$file_path"

        if [[ -e "$local_file" ]]; then
            ((total_count++))
            print_status "Pushing: $file_path"

            # Create remote directory structure
            remote_dir="/$(dirname "$file_path")"
            ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p '$remote_dir'" 2>/dev/null

            # Sync with rsync
            if rsync -avz --progress \
                "$local_file" \
                "$REMOTE_USER@$REMOTE_HOST:/$file_path"; then
                print_success "✓ $file_path"
                ((success_count++))
            else
                print_error "✗ Failed to push $file_path"
            fi
        fi
    done

    echo
    if [[ $total_count -gt 0 ]]; then
        print_success "Push complete: $success_count/$total_count files pushed"
    else
        print_warning "No local files found to push"
    fi
}

# Show sync status
show_status() {
    print_status "Sync Status Report"
    echo "=================="

    echo "Configuration:"
    echo "  Remote: $REMOTE_USER@$REMOTE_HOST"
    echo "  Local:  $LOCAL_BASE"
    echo

    echo "Files being tracked:"
    for file_path in "${FILES_TO_SYNC[@]}"; do
        local_file="$LOCAL_BASE/$file_path"
        remote_status="?"
        local_status="✗"

        # Check local file
        if [[ -e "$local_file" ]]; then
            local_status="✓"
            local_info=$(ls -lh "$local_file" 2>/dev/null | awk '{print $5, $6, $7, $8}')
        else
            local_info="Not found"
        fi

        # Check remote file (if connection works)
        if ssh -o ConnectTimeout=2 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" \
            "test -e '/$file_path'" 2>/dev/null; then
            remote_status="✓"
        else
            remote_status="✗"
        fi

        printf "  %-50s Local: %s %s Remote: %s\n" \
            "$file_path" "$local_status" "$local_info" "$remote_status"
    done
}

# Dry run - show what would be synced
dry_run() {
    print_status "Dry run - showing what would be synced:"

    for file_path in "${FILES_TO_SYNC[@]}"; do
        rsync -avz --dry-run --progress \
            "$REMOTE_USER@$REMOTE_HOST:/$file_path" \
            "$LOCAL_BASE/$file_path" 2>/dev/null || \
            print_warning "Would skip: $file_path (not found on remote)"
    done
}

# Main script
case "${1:-pull}" in
    pull)
        check_connection || exit 1
        pull_files
        ;;
    push)
        check_connection || exit 1
        push_files
        ;;
    status)
        show_status
        ;;
    dry-run|dry)
        check_connection || exit 1
        dry_run
        ;;
    *)
        echo "Usage: $0 [pull|push|status|dry-run]"
        echo
        echo "Commands:"
        echo "  pull     - Pull files from BeagleBone to local (default)"
        echo "  push     - Push files from local to BeagleBone"
        echo "  status   - Show sync status of all tracked files"
        echo "  dry-run  - Show what would be synced without doing it"
        echo
        echo "Configuration:"
        echo "  Remote: $REMOTE_USER@$REMOTE_HOST"
        echo "  Files:  ${#FILES_TO_SYNC[@]} files/directories tracked"
        exit 1
        ;;
esac
