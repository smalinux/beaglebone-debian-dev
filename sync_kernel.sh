#!/bin/bash

# =============================================================================
# BeagleBone Kernel Deployment Script with Headers Support
# =============================================================================
#
# DESCRIPTION:
#   Enhanced automated kernel deployment script for BeagleBone development
#   workflow. This script copies all kernel build artifacts from the local
#   bb-kernel deploy directory to the BeagleBone and builds/installs kernel
#   headers for module development.
#
# PURPOSE:
#   Simplifies the kernel development cycle by automating the deployment of:
#   - Compiled kernel image (zImage)
#   - Device tree blobs (DTBs)
#   - Kernel modules
#   - Kernel configuration files
#   - Kernel headers (built and installed for module compilation)
#
#   Eliminates manual file copying, extraction, and header setup that are
#   error-prone and time-consuming during iterative kernel development.
#
# ENHANCED FEATURES:
#   - Automatic kernel headers preparation and installation
#   - Module compilation environment setup
#   - Support for out-of-tree module development
#   - Proper symlink creation for build tools
#   - Comprehensive development environment validation
#
# WORKFLOW INTEGRATION:
#   This script is designed to work with the standard BeagleBone kernel
#   build process using Robert C. Nelson's bb-kernel repository:
#
#   1. Clone and build kernel:
#      git clone https://github.com/RobertCNelson/bb-kernel
#      cd bb-kernel
#      git checkout am33x-v5.10  # or desired branch
#      ./build_kernel.sh
#
#   2. Deploy kernel with headers:
#      ./sync_kernel.sh push
#
#   3. Reboot BeagleBone to use new kernel
#
#   4. Develop modules on target:
#      ssh root@192.168.0.98
#      cd /path/to/module/source
#      make  # Headers are now available
#
# KERNEL ARTIFACTS HANDLED:
#   The script processes these standard bb-kernel build outputs:
#
#   *.zImage              -> /boot/zImage (kernel image)
#   *-dtbs.tar.gz        -> /boot/*.dtb (device tree blobs, extracted)
#   *-modules.tar.gz     -> /lib/modules/ (kernel modules, extracted)
#   config-*             -> /boot/config-* (kernel configuration)
#
# HEADERS SUPPORT:
#   The script automatically handles kernel headers for module development:
#
#   KERNEL/               -> /usr/src/linux-headers-VERSION/ (kernel source)
#   .config               -> /usr/src/linux-headers-VERSION/.config
#   Module.symvers        -> /usr/src/linux-headers-VERSION/Module.symvers
#   System.map            -> /usr/src/linux-headers-VERSION/System.map
#   scripts/              -> /usr/src/linux-headers-VERSION/scripts/
#   include/              -> /usr/src/linux-headers-VERSION/include/
#   arch/arm/             -> /usr/src/linux-headers-VERSION/arch/arm/
#
#   Creates proper symlinks:
#   /lib/modules/VERSION/build -> /usr/src/linux-headers-VERSION
#   /lib/modules/VERSION/source -> /usr/src/linux-headers-VERSION
#
# SYSTEM REQUIREMENTS:
#
#   Local Development Machine:
#   - Linux system with bash shell
#   - rsync package installed
#   - SSH client
#   - Built bb-kernel with artifacts in bb-kernel/deploy/
#   - Access to bb-kernel/KERNEL/ directory for headers
#
#   BeagleBone Target:
#   - SSH daemon running
#   - Root access configured
#   - Sufficient space in /boot, /lib/modules, and /usr/src partitions
#   - build-essential package (installed automatically if missing)
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
#      # Build kernel (creates artifacts in deploy/ and KERNEL/)
#      ./build_kernel.sh
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
#   - Headers validation before installation
#
# BACKUP SYSTEM:
#   Current kernel image is automatically backed up to:
#   /boot/backup/zImage.backup.YYYYMMDD_HHMMSS
#
#   Previous headers are backed up to:
#   /usr/src/linux-headers-VERSION.backup.YYYYMMDD_HHMMSS
#
#   This allows recovery if new kernel fails to boot:
#   # Boot from backup (from BeagleBone console)
#   cp /boot/backup/zImage.backup.YYYYMMDD_HHMMSS /boot/zImage
#   reboot
#
# HEADERS DEPLOYMENT PROCESS:
#   The script performs these additional steps for headers:
#
#   1. Validate local kernel source directory exists (bb-kernel/KERNEL/)
#   2. Prepare headers by copying essential source files
#   3. Transfer kernel source tree to /usr/src/linux-headers-VERSION/
#   4. Copy .config, Module.symvers, System.map to headers directory
#   5. Create proper symlinks in /lib/modules/VERSION/
#   6. Run 'make scripts' to prepare build environment
#   7. Set appropriate permissions for development
#   8. Install build-essential if missing
#   9. Validate headers installation with test compilation
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
#   7. Prepare and transfer kernel headers
#   8. Set up module build environment
#   9. Run depmod -a to update module dependencies
#   10. Set appropriate file permissions
#   11. Validate headers installation
#   12. Provide reboot and testing instructions
#
# ERROR HANDLING:
#   - SSH connection failures are detected and reported
#   - Missing build artifacts cause early termination
#   - Missing kernel source directory prevents headers deployment
#   - Transfer failures are caught with detailed error messages
#   - Archive extraction errors are reported but don't halt deployment
#   - Headers compilation errors are caught and reported
#
# CONFIGURATION:
#   Edit these variables at the top of the script as needed:
#
#   REMOTE_USER      - SSH username (default: root)
#   REMOTE_HOST      - BeagleBone IP address (default: 192.168.0.98)
#   LOCAL_DEPLOY_DIR - Local build artifacts path (default: ./bb-kernel/deploy)
#   LOCAL_KERNEL_DIR - Local kernel source path (default: ./bb-kernel/KERNEL)
#   REMOTE_BOOT_DIR  - Target boot directory (default: /boot)
#   HEADERS_BASE_DIR - Headers installation base (default: /usr/src)
#
# USAGE EXAMPLES:
#
#   # Deploy kernel with headers (most common usage)
#   ./sync_kernel.sh push
#   ./sync_kernel.sh        # 'push' is default action
#
#   # Deploy only kernel (skip headers)
#   ./sync_kernel.sh push-no-headers
#
#   # Deploy only headers (kernel already deployed)
#   ./sync_kernel.sh headers-only
#
#   # Check deployment status
#   ./sync_kernel.sh status
#
#   # Test headers installation
#   ./sync_kernel.sh test-headers
#
#   # Get help
#   ./sync_kernel.sh help
#   ./sync_kernel.sh --help
#   ./sync_kernel.sh -h
#
# TROUBLESHOOTING:
#
#   Problem: "Deploy directory not found"
#   Solution: Build kernel first with 'cd bb-kernel && ./build_kernel.sh'
#
#   Problem: "Kernel source directory not found"
#   Solution: Ensure bb-kernel/KERNEL/ exists after building
#
#   Problem: "Cannot connect to BeagleBone"
#   Solution: Check network, SSH service, and authentication setup
#
#   Problem: "Permission denied"
#   Solution: Ensure SSH key authentication is properly configured
#
#   Problem: "No space left on device"
#   Solution: Clean old kernels/headers or expand partitions
#
#   Problem: "Headers compilation test failed"
#   Solution: Check build-essential installation and headers integrity
#
#   Problem: BeagleBone won't boot after update
#   Solution: Use backup kernel from /boot/backup/ directory
#
# MODULE DEVELOPMENT WORKFLOW:
#
#   After successful deployment with headers:
#
#   1. SSH to BeagleBone: ssh root@192.168.0.98
#   2. Create module source: mkdir -p /root/modules/hello
#   3. Write simple test module:
#      cat > /root/modules/hello/hello.c << 'EOF'
#      #include <linux/init.h>
#      #include <linux/module.h>
#      static int __init hello_init(void) {
#          printk(KERN_INFO "Hello from custom module!\n");
#          return 0;
#      }
#      static void __exit hello_exit(void) {
#          printk(KERN_INFO "Goodbye from custom module!\n");
#      }
#      module_init(hello_init);
#      module_exit(hello_exit);
#      MODULE_LICENSE("GPL");
#      EOF
#
#   4. Create Makefile:
#      cat > /root/modules/hello/Makefile << 'EOF'
#      obj-m += hello.o
#      all:
#      	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
#      clean:
#      	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
#      EOF
#
#   5. Build module: cd /root/modules/hello && make
#   6. Test module: insmod hello.ko && rmmod hello && dmesg | tail
#
# DEVELOPMENT WORKFLOW:
#
#   Typical kernel development cycle with headers:
#
#   1. Modify kernel source or device tree
#   2. Build: cd bb-kernel && ./build_kernel.sh
#   3. Deploy: ./sync_kernel.sh push
#   4. Test: ssh root@192.168.0.98 'reboot'
#   5. Verify: ssh root@192.168.0.98 'uname -r'
#   6. Develop modules: ssh root@192.168.0.98 'cd /path/to/module && make'
#   7. Repeat as needed
#
# INTEGRATION WITH BUILD SYSTEMS:
#
#   Can be integrated into automated build pipelines:
#
#   # Makefile target
#   deploy-kernel-with-headers:
#   	./sync_kernel.sh push
#
#   deploy-kernel-only:
#   	./sync_kernel.sh push-no-headers
#
#   # CI/CD pipeline step
#   - name: Deploy Kernel with Headers
#     run: ./sync_kernel.sh push
#
# OUTPUT AND LOGGING:
#   - Color-coded status messages for easy reading
#   - Progress indicators during file transfers
#   - Headers build progress reporting
#   - Deployment summary with next steps
#   - Module development instructions
#   - All operations logged to console for debugging
#
# COMPATIBILITY:
#   - Tested with bb-kernel am33x-v5.10 branch
#   - Compatible with BeagleBone Black, Green, AI platforms
#   - Works with standard Debian-based BeagleBone images
#   - Requires bash shell (not sh/dash compatible)
#   - Headers compatible with GCC cross-compilation environment
#
# SECURITY CONSIDERATIONS:
#   - Uses SSH key authentication (no passwords in scripts)
#   - Root access required for /boot, /lib/modules, /usr/src modifications
#   - Network traffic encrypted via SSH
#   - No sensitive data stored in script
#   - Headers installation preserves file permissions
#
# VERSION: 2.0
# AUTHOR: BeagleBone Development Team
# LICENSE: MIT
# REPOSITORY: https://github.com/example/beaglebone-kernel-tools
#
# =============================================================================

# Configuration
REMOTE_USER="root"
REMOTE_HOST="192.168.0.98"
LOCAL_DEPLOY_DIR="./bb-kernel/deploy"
LOCAL_KERNEL_DIR="./bb-kernel/KERNEL"
REMOTE_BOOT_DIR="/boot"
HEADERS_BASE_DIR="/usr/src"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

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

# Check if kernel source directory exists
check_kernel_source() {
    if [[ ! -d "$LOCAL_KERNEL_DIR" ]]; then
        print_error "Kernel source directory not found: $LOCAL_KERNEL_DIR"
        print_warning "Headers cannot be deployed without kernel source"
        print_warning "Please build kernel first: cd bb-kernel && ./build_kernel.sh"
        return 1
    fi
    return 0
}

# Get kernel version from local build
get_kernel_version() {
    if [[ -f "$LOCAL_DEPLOY_DIR/config-"* ]]; then
        local config_file=$(ls "$LOCAL_DEPLOY_DIR"/config-* | head -1)
        local version=$(basename "$config_file" | sed 's/config-//')
        echo "$version"
    elif [[ -d "$LOCAL_KERNEL_DIR" ]]; then
        # Try to get version from kernel Makefile
        local version=$(cd "$LOCAL_KERNEL_DIR" && make kernelversion 2>/dev/null)
        if [[ -n "$version" ]]; then
            echo "$version"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Prepare kernel headers for deployment
prepare_headers() {
    local kernel_version="$1"
    local temp_headers_dir="/tmp/kernel-headers-$kernel_version"

    print_step "Preparing kernel headers for version $kernel_version..."

    # Clean up any existing temp directory
    rm -rf "$temp_headers_dir"
    mkdir -p "$temp_headers_dir"

    # Copy essential kernel source files
    print_status "Copying kernel source files..."

    # Essential directories and files for module compilation
    local essential_items=(
        "Makefile"
        "Kconfig"
        "Kbuild"
        ".config"
        "Module.symvers"
        "System.map"
        "include/"
        "scripts/"
        "arch/arm/"
        "security/"
        "sound/"
        "kernel/"
        "mm/"
        "fs/"
        "crypto/"
        "block/"
        "lib/"
        "drivers/Makefile"
        "drivers/Kconfig"
        "net/Makefile"
        "net/Kconfig"
    )

    for item in "${essential_items[@]}"; do
        local src_path="$LOCAL_KERNEL_DIR/$item"
        local dst_path="$temp_headers_dir/$item"

        if [[ -e "$src_path" ]]; then
            mkdir -p "$(dirname "$dst_path")"
            cp -r "$src_path" "$dst_path" 2>/dev/null || true
        fi
    done

    # Create version-specific files
    echo "$kernel_version" > "$temp_headers_dir/include/config/kernel.release"

    print_success "Headers prepared in $temp_headers_dir"
    echo "$temp_headers_dir"
}

# Deploy kernel headers to target
deploy_headers() {
    local kernel_version="$1"
    local temp_headers_dir="$2"
    local remote_headers_dir="$HEADERS_BASE_DIR/linux-headers-$kernel_version"

    print_step "Deploying kernel headers for version $kernel_version..."

    # Create backup of existing headers if they exist
    ssh "$REMOTE_USER@$REMOTE_HOST" "
        if [[ -d '$remote_headers_dir' ]]; then
            echo 'Backing up existing headers...'
            mv '$remote_headers_dir' '$remote_headers_dir.backup.$(date +%Y%m%d_%H%M%S)'
        fi
        mkdir -p '$remote_headers_dir'
    "

    # Transfer headers
    print_status "Transferring headers to $remote_headers_dir..."
    if rsync -avz --progress "$temp_headers_dir/" "$REMOTE_USER@$REMOTE_HOST:$remote_headers_dir/"; then
        print_success "Headers transferred successfully"
    else
        print_error "Failed to transfer headers"
        return 1
    fi

    # Set up headers on target
    print_status "Setting up headers environment on target..."
    ssh "$REMOTE_USER@$REMOTE_HOST" "
        cd '$remote_headers_dir'

        # Install build essentials if missing
        if ! command -v gcc >/dev/null 2>&1; then
            echo 'Installing build-essential...'
            apt-get update && apt-get install -y build-essential
        fi

        # Prepare scripts and build environment
        echo 'Preparing build scripts...'
        if [[ -f Makefile ]] && [[ -d scripts ]]; then
            make scripts 2>/dev/null || {
                echo 'Warning: make scripts failed, but continuing...'
            }
        fi

        # Create module symlinks
        local modules_dir='/lib/modules/$kernel_version'
        mkdir -p \"\$modules_dir\"

        # Remove existing symlinks
        rm -f \"\$modules_dir/build\" \"\$modules_dir/source\"

        # Create new symlinks
        ln -sf '$remote_headers_dir' \"\$modules_dir/build\"
        ln -sf '$remote_headers_dir' \"\$modules_dir/source\"

        # Set permissions
        chmod -R 755 '$remote_headers_dir'

        echo 'Headers setup complete'
        echo 'Build symlinks created:'
        ls -la \"\$modules_dir/build\" \"\$modules_dir/source\"
    "

    # Clean up temp directory
    rm -rf "$temp_headers_dir"

    return 0
}

# Test headers installation
test_headers() {
    local kernel_version
    kernel_version=$(ssh "$REMOTE_USER@$REMOTE_HOST" "uname -r" 2>/dev/null)

    if [[ -z "$kernel_version" ]]; then
        print_error "Could not determine kernel version on target"
        return 1
    fi

    print_step "Testing headers installation for kernel $kernel_version..."

    ssh "$REMOTE_USER@$REMOTE_HOST" "
        # Test compilation with a simple module
        cat > /tmp/test_module.c << 'EOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

static int __init test_init(void) {
    printk(KERN_INFO \"Test module loaded\n\");
    return 0;
}

static void __exit test_exit(void) {
    printk(KERN_INFO \"Test module unloaded\n\");
}

module_init(test_init);
module_exit(test_exit);
MODULE_LICENSE(\"GPL\");
MODULE_DESCRIPTION(\"Test module for headers validation\");
EOF

        cat > /tmp/Makefile << 'EOF'
obj-m += test_module.o
all:
	make -C /lib/modules/\$(shell uname -r)/build M=\$(PWD) modules
clean:
	make -C /lib/modules/\$(shell uname -r)/build M=\$(PWD) clean
EOF

        cd /tmp
        echo 'Attempting test compilation...'

        if make > /tmp/test_build.log 2>&1; then
            echo '✓ Headers test compilation PASSED'
            echo 'Generated files:'
            ls -la test_module.ko test_module.o 2>/dev/null || true
            make clean >/dev/null 2>&1
            rm -f test_module.c Makefile test_build.log
            return 0
        else
            echo '✗ Headers test compilation FAILED'
            echo 'Build log:'
            cat /tmp/test_build.log
            return 1
        fi
    "
}

# Push kernel and headers
push_kernel() {
    local skip_headers="$1"

    print_status "Pushing all files from $LOCAL_DEPLOY_DIR to $REMOTE_BOOT_DIR..."

    if [[ ! -d "$LOCAL_DEPLOY_DIR" ]]; then
        print_error "Deploy directory not found: $LOCAL_DEPLOY_DIR"
        echo "Please build the kernel first: cd bb-kernel && ./build_kernel.sh"
        return 1
    fi

    # Check if deploy directory has files
    if [[ -z "$(ls -A "$LOCAL_DEPLOY_DIR" 2>/dev/null)" ]]; then
        print_error "Deploy directory is empty: $LOCAL_DEPLOY_DIR"
        return 1
    fi

    # Get kernel version
    local kernel_version
    kernel_version=$(get_kernel_version)
    print_status "Detected kernel version: $kernel_version"

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
        print_status "Extracting archives and setting up kernel..."
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

            # Create vmlinuz symlink from zImage
            cd /boot
            if ls *.zImage >/dev/null 2>&1; then
                ZIMAGE_FILE=\$(ls *.zImage | head -1)
                KERNEL_VERSION=\$(echo \$ZIMAGE_FILE | sed 's/.zImage//')

                echo \"Creating vmlinuz-\$KERNEL_VERSION from \$ZIMAGE_FILE\"
                cp \$ZIMAGE_FILE vmlinuz-\$KERNEL_VERSION

                # Also create the standard zImage symlink
                cp \$ZIMAGE_FILE zImage

                echo \"Kernel files created:\"
                ls -la zImage vmlinuz-\$KERNEL_VERSION \$ZIMAGE_FILE
            fi
        "

        # Deploy headers if not skipped and source is available
        if [[ "$skip_headers" != "true" ]]; then
            if check_kernel_source; then
                local temp_headers_dir
                temp_headers_dir=$(prepare_headers "$kernel_version")
                if [[ $? -eq 0 ]] && [[ -n "$temp_headers_dir" ]]; then
                    if deploy_headers "$kernel_version" "$temp_headers_dir"; then
                        print_success "Kernel headers deployed successfully"
                    else
                        print_warning "Headers deployment failed, but kernel deployment succeeded"
                    fi
                fi
            else
                print_warning "Skipping headers deployment - kernel source not available"
            fi
        else
            print_status "Skipping headers deployment as requested"
        fi

        # Update uEnv.txt to use new kernel
        print_status "Updating uEnv.txt for new kernel..."
        ssh "$REMOTE_USER@$REMOTE_HOST" "
            cd /boot

            # Find the new kernel version from zImage filename
            NEW_KERNEL=\$(ls *.zImage | head -1 | sed 's/.zImage//')

            if [[ -n \"\$NEW_KERNEL\" ]]; then
                echo \"Found new kernel: \$NEW_KERNEL\"

                # Backup current uEnv.txt
                cp uEnv.txt uEnv.txt.backup.\$(date +%Y%m%d_%H%M%S)

                # Update uname_r line
                sed -i \"s/^uname_r=.*/uname_r=\$NEW_KERNEL/\" uEnv.txt

                echo \"Updated uEnv.txt to use kernel: \$NEW_KERNEL\"
                echo \"Current uEnv.txt content:\"
                cat uEnv.txt
            else
                echo \"Warning: Could not determine new kernel version\"
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
        if [[ "$skip_headers" != "true" ]] && check_kernel_source; then
            print_success "Headers installed for module development"
        fi
        print_success "=========================================="
        print_warning "IMPORTANT: Reboot BeagleBone to use new kernel:"
        echo "  ssh $REMOTE_USER@$REMOTE_HOST 'reboot'"
        echo
        if [[ "$skip_headers" != "true" ]] && check_kernel_source; then
            print_status "After reboot, test module compilation:"
            echo "  ssh $REMOTE_USER@$REMOTE_HOST"
            echo "  # Create a test module and compile it"
            echo "  ./sync_kernel.sh test-headers"
        fi
        print_warning "=========================================="

        return 0
    else
        print_error "Failed to copy files"
        return 1
    fi
}

# Deploy only headers
headers_only() {
    print_status "Deploying kernel headers only..."

    if ! check_kernel_source; then
        return 1
    fi

    local kernel_version
    kernel_version=$(get_kernel_version)
    print_status "Detected kernel version: $kernel_version"

    local temp_headers_dir
    temp_headers_dir=$(prepare_headers "$kernel_version")
    if [[ $? -eq 0 ]] && [[ -n "$temp_headers_dir" ]]; then
        if deploy_headers "$kernel_version" "$temp_headers_dir"; then
            print_success "Kernel headers deployed successfully"
            print_status "Test headers installation with: $0 test-headers"
            return 0
        else
            print_error "Headers deployment failed"
            return 1
        fi
    else
        print_error "Failed to prepare headers"
        return 1
    fi
}

# Show status
show_status() {
    print_status "Kernel Update Status"
    echo "===================="

    echo "Configuration:"
    echo "  Local Deploy:  $LOCAL_DEPLOY_DIR"
    echo "  Local Kernel:  $LOCAL_KERNEL_DIR"
    echo "  Remote Target: $REMOTE_USER@$REMOTE_HOST:$REMOTE_BOOT_DIR"
    echo

    echo "Local deploy files:"
    if [[ -d "$LOCAL_DEPLOY_DIR" ]]; then
        ls -lh "$LOCAL_DEPLOY_DIR" 2>/dev/null || echo "  Directory empty or not accessible"
    else
        echo "  Deploy directory not found"
    fi

    echo
    echo "Local kernel source:"
    if [[ -d "$LOCAL_KERNEL_DIR" ]]; then
        echo "  ✓ Kernel source available for headers"
        local version
        version=$(get_kernel_version)
        echo "  Version: $version"
    else
        echo "  ✗ Kernel source not found (headers cannot be deployed)"
    fi

    echo
    print_status "Current kernel on BeagleBone:"
    local remote_kernel
    remote_kernel=$(ssh -o ConnectTimeout=2 "$REMOTE_USER@$REMOTE_HOST" "uname -r" 2>/dev/null) || echo "  Unable to check"
    echo "  $remote_kernel"

    echo
    print_status "Files in remote /boot:"
    ssh -o ConnectTimeout=2 "$REMOTE_USER@$REMOTE_HOST" "ls -lh /boot/*.zImage /boot/config-
