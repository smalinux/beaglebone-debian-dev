#!/bin/bash

# =============================================================================
# SSHFS Mount Script - Real-time File Access for BeagleBone Development
# =============================================================================
#
# DESCRIPTION:
#   This script provides real-time access to BeagleBone files by mounting
#   the remote filesystem locally using SSHFS. Any changes made to files
#   are immediately reflected on the BeagleBone.
#
# PREREQUISITES:
#   1. Install SSHFS:
#      Ubuntu/Debian: sudo apt-get install sshfs
#      Fedora/RHEL:   sudo dnf install sshfs
#      Arch:          sudo pacman -S sshfs
#
#   2. Set up SSH key authentication (REQUIRED):
#      ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
#      ssh-copy-id debian@192.168.0.98
#
#   3. Test SSH connection:
#      ssh debian@192.168.0.98
#
#   4. Add user to fuse group (may be required):
#      sudo usermod -a -G fuse $USER
#      # Log out and back in for changes to take effect
#
# CONFIGURATION:
#   Edit the variables below to match your setup:
#   - REMOTE_USER: SSH username on BeagleBone
#   - REMOTE_HOST: IP address or hostname of BeagleBone
#   - MOUNT_POINT: Local directory where files will be accessible
#   - REMOTE_PATH: Directory on BeagleBone to mount (/ for full filesystem)
#
# USAGE:
#   ./sshfs_mount.sh [command]
#
#   Commands:
#     mount    - Mount BeagleBone filesystem (default action)
#     unmount  - Unmount BeagleBone filesystem
#     status   - Check if filesystem is currently mounted
#     remount  - Unmount and mount again (useful for connection issues)
#
# EXAMPLES:
#   # Basic usage - mount the filesystem
#   ./sshfs_mount.sh
#   ./sshfs_mount.sh mount
#
#   # Check if mounted
#   ./sshfs_mount.sh status
#
#   # Access files after mounting
#   cd /home/smalinux/repos/beaglebone-debian-dev/target
#   ls -la                    # List BeagleBone files
#   nano some_file.c          # Edit files directly on BeagleBone
#   mkdir new_directory       # Create directories on BeagleBone
#   cp file.txt ~/local.txt   # Copy files to local system
#
#   # Unmount when done
#   ./sshfs_mount.sh unmount
#
# DEVELOPMENT WORKFLOW:
#   1. Mount BeagleBone filesystem:
#      ./sshfs_mount.sh mount
#
#   2. Navigate to your project:
#      cd /home/smalinux/repos/beaglebone-debian-dev/target/your_project
#
#   3. Edit files with any editor (changes are real-time):
#      code .              # VS Code
#      vim main.c          # Vim
#      nano config.h       # Nano
#
#   4. Compile on BeagleBone via SSH:
#      ssh debian@192.168.0.98 "cd your_project && make"
#
#   5. Or copy and cross-compile locally:
#      cp -r your_project/ ~/local_build/
#      cd ~/local_build && make CROSS_COMPILE=arm-linux-gnueabihf-
#
# AUTO-MOUNT OPTIONS:
#
#   Option 1 - Add to /etc/fstab for boot-time mounting:
#   debian@192.168.0.98:/home/debian /home/smalinux/repos/beaglebone-debian-dev/target fuse.sshfs defaults,_netdev,users,idmap=user,reconnect 0 0
#
#   Option 2 - Create systemd service:
#   sudo nano /etc/systemd/system/beaglebone-mount.service
#   [Unit]
#   Description=Mount BeagleBone via SSHFS
#   After=network.target
#   [Service]
#   Type=forking
#   User=smalinux
#   ExecStart=/path/to/sshfs_mount.sh mount
#   ExecStop=/path/to/sshfs_mount.sh unmount
#   RemainAfterExit=yes
#   [Install]
#   WantedBy=multi-user.target
#
#   Then: sudo systemctl enable beaglebone-mount.service
#
# TROUBLESHOOTING:
#
#   Problem: "Permission denied" or "fuse: unknown option"
#   Solution: sudo usermod -a -G fuse $USER && logout/login
#
#   Problem: "Connection refused"
#   Solution: Test SSH: ssh debian@192.168.0.98
#
#   Problem: "Mount point busy" or "Transport endpoint not connected"
#   Solution: ./sshfs_mount.sh remount
#            or: sudo fusermount -u /mount/point && ./sshfs_mount.sh mount
#
#   Problem: Network interruption causes mount to become unresponsive
#   Solution: ./sshfs_mount.sh remount
#
#   Problem: Slow performance
#   Solution: Edit script to add more performance options or use faster network
#
# SECURITY NOTES:
#   - SSH key authentication is REQUIRED (no password prompts in scripts)
#   - Files are transferred over encrypted SSH connection
#   - File permissions are mapped between systems
#   - Use firewall rules to restrict SSH access if needed
#
# VERSION: 1.0
# AUTHOR: Generated for BeagleBone development
# =============================================================================

# Configuration - EDIT THESE VALUES FOR YOUR SETUP
REMOTE_USER="debian"
REMOTE_HOST="192.168.0.98"
MOUNT_POINT="/src/beaglebone-debian-dev/target"
REMOTE_PATH="/"  # Change to "/" for full filesystem access

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if sshfs is installed
check_sshfs() {
    if ! command -v sshfs &> /dev/null; then
        print_error "sshfs not installed. Install with:"
        echo "  sudo apt-get install sshfs"
        exit 1
    fi
}

# Mount remote filesystem
mount_sshfs() {
    mkdir -p "$MOUNT_POINT"

    # Check if already mounted
    if mountpoint -q "$MOUNT_POINT"; then
        print_status "Already mounted at $MOUNT_POINT"
        return 0
    fi

    print_status "Mounting $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH to $MOUNT_POINT"

    # Mount with options for better performance and reliability
    if sshfs "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH" "$MOUNT_POINT" \
        -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,cache=yes,compression=yes; then
        print_success "Mounted successfully"
    else
        print_error "Failed to mount"
        return 1
    fi
}

# Unmount
unmount_sshfs() {
    if mountpoint -q "$MOUNT_POINT"; then
        print_status "Unmounting $MOUNT_POINT"
        if fusermount -u "$MOUNT_POINT"; then
            print_success "Unmounted successfully"
        else
            print_error "Failed to unmount"
            return 1
        fi
    else
        print_status "Not mounted"
    fi
}

# Status check
check_status() {
    if mountpoint -q "$MOUNT_POINT"; then
        print_success "Mounted at $MOUNT_POINT"
        echo "Available files:"
        ls -la "$MOUNT_POINT" | head -10
    else
        print_status "Not mounted"
    fi
}

# Main function
case "${1:-mount}" in
    mount)
        check_sshfs
        mount_sshfs
        ;;
    unmount|umount)
        unmount_sshfs
        ;;
    status)
        check_status
        ;;
    remount)
        unmount_sshfs
        sleep 1
        mount_sshfs
        ;;
    *)
        echo "Usage: $0 [mount|unmount|status|remount]"
        echo
        echo "  mount    - Mount remote filesystem (default)"
        echo "  unmount  - Unmount remote filesystem"
        echo "  status   - Check mount status"
        echo "  remount  - Unmount and mount again"
        exit 1
        ;;
esac
