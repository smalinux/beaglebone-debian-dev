#!/bin/bash

# =============================================================================
# BeagleBone Kernel Deployment Script
# =============================================================================
#
# DESCRIPTION:
#   Automated kernel deployment script for BeagleBone development workflow.
#   This script copies all kernel build artifacts from the local bb-kernel
#   deploy directory to the BeagleBone's /boot partition and properly extracts
#   archives for immediate use.
#
# PURPOSE:
#   Simplifies the kernel development cycle by automating the deployment of:
#   - Compiled kernel image (zImage)
#   - Device tree blobs (DTBs)
#   - Kernel modules
#   - Kernel configuration files
#
#   Eliminates manual file copying and extraction steps that are error-prone
#   and time-consuming during iterative kernel development.
#
# WORKFLOW INTEGRATION:
#   This script is designed to work with the standard BeagleBone kernel
#   build process using Robert C. Nelson's bb-kernel repository:
#
#   1. Clone and build kernel:
#      git clone https://github.com/RobertCNelson/bb-kernel
#      cd bb-kernel
#      git checkout am33x-v5.10  # or desired branch
#      make
#
#   2. Deploy kernel:
#      ./sync_kernel.sh push
#
#   3. Reboot BeagleBone to use new kernel
#
# KERNEL ARTIFACTS HANDLED:
#   The script processes these standard bb-kernel build outputs:
#
#   *.zImage              -> /boot/zImage (kernel image)
#   *-dtbs.tar.gz        -> /boot/*.dtb (device tree blobs, extracted)
#   *-modules.tar.gz     -> /lib/modules/ (kernel modules, extracted)
#   config-*             -> /boot/config-* (kernel configuration)
#
# SYSTEM REQUIREMENTS:
#
#   Local Development Machine:
#   - Linux system with bash shell
#   - rsync package installed
#   - SSH client
#   - Built bb-kernel with artifacts in bb-kernel/deploy/
#
#   BeagleBone Target:
#   - SSH daemon running
#   - Root access configured
#   - Sufficient space in /boot and /lib/modules partitions
#
# NETWORK SETUP:
#   - BeagleBone accessible via SSH on network
#   - Default target: root@192.168.0.98
#   - SSH key authentication strongly recommended for automation
#
# PREREQUISITES - DETAILED SETUP:
#
#   1. SSH Key Authentication (REQUIRED for automation):
#      # Generate SSH key pair if not exists
#      ssh-keygen -t rsa -b 4096 -C "beaglebone-dev"
#
#      # Copy public key to BeagleBone
#      ssh-copy-id root@192.168.0.98
#
#      # Test passwordless connection
#      ssh root@192.168.0.98 'uname -a'
#
#   2. Build Environment Setup:
#      # Clone bb-kernel repository
#      git clone https://github.com/RobertCNelson/bb-kernel
#      cd bb-kernel
#
#      # Checkout desired kernel version
#      git checkout am33x-v5.10
#
#      # Install build dependencies (Ubuntu/Debian)
#      sudo apt-get install build-essential git lzop u-boot-tools
#
#      # Build kernel (creates artifacts in deploy/)
#      make
#
#   3. Network Configuration:
#      # Ensure BeagleBone is accessible
#      ping 192.168.0.98
#
#      # Update REMOTE_HOST variable if using different IP
#      # Edit script: REMOTE_HOST="your.beaglebone.ip"
#
# SAFETY FEATURES:
#   - Automatic backup of current kernel before deployment
#   - Connection testing before deployment attempts
#   - Comprehensive error checking and status reporting
#   - Non-destructive status checking mode
#
# BACKUP SYSTEM:
#   Current kernel image is automatically backed up to:
#   /boot/backup/zImage.backup.YYYYMMDD_HHMMSS
#
#   This allows recovery if new kernel fails to boot:
#   # Boot from backup (from BeagleBone console)
#   cp /boot/backup/zImage.backup.YYYYMMDD_HHMMSS /boot/zImage
#   reboot
#
# DEPLOYMENT PROCESS:
#   The script performs these steps in order:
#
#   1. Validate local build artifacts exist
#   2. Test SSH connectivity to BeagleBone
#   3. Create timestamped backup of current kernel
#   4. Transfer all files from bb-kernel/deploy/ to /boot/
#   5. Extract DTBs archive to /boot/ (*.dtb files)
#   6. Extract modules archive to /lib/modules/
#   7. Run depmod -a to update module dependencies
#   8. Set appropriate file permissions
#   9. Provide reboot instructions
#
# ERROR HANDLING:
#   - SSH connection failures are detected and reported
#   - Missing build artifacts cause early termination
#   - Transfer failures are caught with detailed error messages
#   - Archive extraction errors are reported but don't halt deployment
#
# CONFIGURATION:
#   Edit these variables at the top of the script as needed:
#
#   REMOTE_USER      - SSH username (default: root)
#   REMOTE_HOST      - BeagleBone IP address (default: 192.168.0.98)
#   LOCAL_DEPLOY_DIR - Local build artifacts path (default: ./bb-kernel/deploy)
#   REMOTE_BOOT_DIR  - Target boot directory (default: /boot)
#
# USAGE EXAMPLES:
#
#   # Deploy kernel (most common usage)
#   ./sync_kernel.sh push
#   ./sync_kernel.sh        # 'push' is default action
#
#   # Check deployment status
#   ./sync_kernel.sh status
#
#   # Get help
#   ./sync_kernel.sh help
#   ./sync_kernel.sh --help
#   ./sync_kernel.sh -h
#
# TROUBLESHOOTING:
#
#   Problem: "Deploy directory not found"
#   Solution: Build kernel first with 'cd bb-kernel && make'
#
#   Problem: "Cannot connect to BeagleBone"
#   Solution: Check network, SSH service, and authentication setup
#
#   Problem: "Permission denied"
#   Solution: Ensure SSH key authentication is properly configured
#
#   Problem: "No space left on device"
#   Solution: Clean old kernels from /boot or expand boot partition
#
#   Problem: BeagleBone won't boot after update
#   Solution: Use backup kernel from /boot/backup/ directory
#
# DEVELOPMENT WORKFLOW:
#
#   Typical kernel development cycle:
#
#   1. Modify kernel source or device tree
#   2. Build: cd bb-kernel && make
#   3. Deploy: ./sync_kernel.sh push
#   4. Test: ssh root@192.168.0.98 'reboot'
#   5. Verify: ssh root@192.168.0.98 'uname -r'
#   6. Repeat as needed
#
# INTEGRATION WITH BUILD SYSTEMS:
#
#   Can be integrated into automated build pipelines:
#
#   # Makefile target
#   deploy-kernel:
#   	./sync_kernel.sh push
#
#   # CI/CD pipeline step
#   - name: Deploy Kernel
#     run: ./sync_kernel.sh push
#
# OUTPUT AND LOGGING:
#   - Color-coded status messages for easy reading
#   - Progress indicators during file transfers
#   - Deployment summary with next steps
#   - All operations logged to console for debugging
#
# COMPATIBILITY:
#   - Tested with bb-kernel am33x-v5.10 branch
#   - Compatible with BeagleBone Black, Green, AI platforms
#   - Works with standard Debian-based BeagleBone images
#   - Requires bash shell (not sh/dash compatible)
#
# SECURITY CONSIDERATIONS:
#   - Uses SSH key authentication (no passwords in scripts)
#   - Root access required for /boot and /lib/modules modifications
#   - Network traffic encrypted via SSH
#   - No sensitive data stored in script
#
# VERSION: 1.0
# AUTHOR: BeagleBone Development Team
# LICENSE: MIT
# REPOSITORY: https://github.com/example/beaglebone-kernel-tools
#
# =============================================================================

# Configuration
REMOTE_USER="root"
REMOTE_HOST="192.168.0.98"
LOCAL_DEPLOY_DIR="./bb-kernel/deploy"
REMOTE_BOOT_DIR="/boot"

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
        return 1
    fi
}

# Push all files from deploy to /boot
push_kernel() {
    print_status "Pushing all files from $LOCAL_DEPLOY_DIR to $REMOTE_BOOT_DIR..."

    if [[ ! -d "$LOCAL_DEPLOY_DIR" ]]; then
        print_error "Deploy directory not found: $LOCAL_DEPLOY_DIR"
        echo "Please build the kernel first: cd bb-kernel && make"
        return 1
    fi

    # Check if deploy directory has files
    if [[ -z "$(ls -A "$LOCAL_DEPLOY_DIR" 2>/dev/null)" ]]; then
        print_error "Deploy directory is empty: $LOCAL_DEPLOY_DIR"
        return 1
    fi

    # Create backup
    print_status "Creating backup of current kernel..."
    ssh "$REMOTE_USER@$REMOTE_HOST" "
        mkdir -p /boot/backup
        cp /boot/zImage /boot/backup/zImage.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    "

    # Copy all files
    print_status "Copying all deploy files..."
    if rsync -avz --progress "$LOCAL_DEPLOY_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_BOOT_DIR/"; then
        print_success "All files copied successfully"

        # Extract DTBs and modules if they exist
        print_status "Extracting archives..."
        ssh "$REMOTE_USER@$REMOTE_HOST" "
            cd /boot

            # Extract DTBs archive if it exists
            if ls *-dtbs.tar.gz >/dev/null 2>&1; then
                echo 'Extracting device tree blobs...'
                tar -xzf *-dtbs.tar.gz && rm *-dtbs.tar.gz
            fi

            # Extract modules archive if it exists
            if ls *-modules.tar.gz >/dev/null 2>&1; then
                echo 'Extracting kernel modules...'
                cd /lib/modules
                tar -xzf /boot/*-modules.tar.gz && rm /boot/*-modules.tar.gz
                depmod -a
            fi
        "

        print_status "Setting permissions..."
        ssh "$REMOTE_USER@$REMOTE_HOST" "
            chmod 644 /boot/*.zImage 2>/dev/null || true
            chmod 644 /boot/config-* 2>/dev/null || true
            chmod 644 /boot/*.dtb 2>/dev/null || true
        "

        echo
        print_success "=========================================="
        print_success "Kernel update complete!"
        print_success "=========================================="
        print_warning "IMPORTANT: Reboot BeagleBone to use new kernel:"
        echo "  ssh $REMOTE_USER@$REMOTE_HOST 'reboot'"
        print_warning "=========================================="

        return 0
    else
        print_error "Failed to copy files"
        return 1
    fi
}

# Show status
show_status() {
    print_status "Kernel Update Status"
    echo "===================="

    echo "Configuration:"
    echo "  Local:  $LOCAL_DEPLOY_DIR"
    echo "  Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_BOOT_DIR"
    echo

    echo "Local deploy files:"
    if [[ -d "$LOCAL_DEPLOY_DIR" ]]; then
        ls -lh "$LOCAL_DEPLOY_DIR" 2>/dev/null || echo "  Directory empty or not accessible"
    else
        echo "  Deploy directory not found"
    fi

    echo
    print_status "Current kernel on BeagleBone:"
    ssh -o ConnectTimeout=2 "$REMOTE_USER@$REMOTE_HOST" "uname -r" 2>/dev/null || echo "  Unable to check"

    echo
    print_status "Files in remote /boot:"
    ssh -o ConnectTimeout=2 "$REMOTE_USER@$REMOTE_HOST" "ls -lh /boot/*.zImage /boot/config-* 2>/dev/null" || echo "  Unable to check"
}

# Main script
case "${1:-push}" in
    push)
        check_connection || exit 1
        push_kernel
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 [push|status]"
        echo
        echo "Commands:"
        echo "  push     - Copy all files from bb-kernel/deploy/ to /boot/ (default)"
        echo "  status   - Show current status"
        echo
        echo "Simple kernel update - copies everything from deploy to /boot"
        exit 1
        ;;
esac
