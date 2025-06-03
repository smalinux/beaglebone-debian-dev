#!/bin/bash
#
# Enhanced Kernel Sync Script - Debian Package Method
# Uses official 'make bindeb-pkg' to create professional .deb packages
# Based on BeagleBoard.org CI/CD pipeline approach
#
# Usage:
#   ./sync_kernel.sh [options]
#
# Options:
#   build-only    - Only build packages, don't deploy
#   deploy-only   - Only deploy existing packages
#   clean-build   - Clean before building packages
#   no-debug      - Build without debug packages (faster)
#   help          - Show this help
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_KERNEL_DIR="$SCRIPT_DIR/bb-kernel"
KERNEL_DIR="$BB_KERNEL_DIR/KERNEL"
DEPLOY_DIR="$BB_KERNEL_DIR/deploy"

# Remote configuration
REMOTE_HOST="${REMOTE_HOST:-192.168.0.98}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_TMP_DIR="/tmp/kernel-packages"

# Build configuration
CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabihf-}"
ARCH="${ARCH:-arm}"
CORES=$(nproc)

# Package configuration
KDEB_SOURCENAME="linux-beaglebone"
KDEB_PKGVERSION="1.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

show_help() {
    cat << EOF
Enhanced Kernel Sync Script - Debian Package Method

This script builds professional .deb packages using 'make bindeb-pkg'
and deploys them to your BeagleBone device.

Usage: $0 [options]

Options:
  build-only     Build packages only, don't deploy
  deploy-only    Deploy existing packages only
  clean-build    Clean kernel build before creating packages
  no-debug       Disable debug packages for faster builds
  help           Show this help message

Environment Variables:
  REMOTE_HOST    Target device IP (default: 192.168.0.98)
  REMOTE_USER    SSH user (default: root)
  CROSS_COMPILE  Cross compiler prefix (default: arm-linux-gnueabihf-)

Examples:
  $0                    # Build and deploy packages
  $0 build-only         # Only build packages
  $0 deploy-only        # Only deploy existing packages
  $0 clean-build        # Clean build then deploy
  $0 no-debug           # Build without debug packages

The script creates these packages:
  - linux-image-VERSION.deb         (kernel image)
  - linux-headers-VERSION.deb       (development headers)
  - linux-firmware-image-VERSION.deb (firmware, if any)
  - linux-image-VERSION-dbg.deb     (debug symbols, optional)
  - linux-libc-dev.deb             (userspace headers)

EOF
}

check_dependencies() {
    print_status "Checking build dependencies..."

    local missing_deps=()
    local required_deps=(
        "build-essential" "bc" "kmod" "cpio" "flex"
        "libncurses5-dev" "libelf-dev" "libssl-dev"
        "dwarves" "bison" "fakeroot" "rsync"
    )

    for dep in "${required_deps[@]}"; do
        if ! dpkg -l "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        echo "Install with: sudo apt install ${missing_deps[*]}"
        exit 1
    fi

    print_success "All dependencies satisfied"
}

detect_kernel_version() {
    if [[ ! -f "$BB_KERNEL_DIR/kernel_version" ]]; then
        print_error "Cannot find kernel_version file in $BB_KERNEL_DIR"
    fi

    KERNEL_VERSION=$(cat "$BB_KERNEL_DIR/kernel_version")
    print_status "Detected kernel version: $KERNEL_VERSION"
}

prepare_kernel_config() {
    print_status "Preparing kernel configuration..."

    cd "$KERNEL_DIR"

    # Disable debug info if requested (speeds up build significantly)
    if [[ "$1" == "no-debug" ]]; then
        print_status "Disabling debug info for faster build..."
        scripts/config --disable DEBUG_INFO
        scripts/config --disable DEBUG_INFO_SPLIT
        scripts/config --disable DEBUG_INFO_REDUCED
        scripts/config --disable DEBUG_INFO_COMPRESSED
        scripts/config --set-val DEBUG_INFO_NONE y
        make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
    fi

    # Ensure we have a valid configuration
    if [[ ! -f .config ]]; then
        print_status "No .config found, using bb.org_defconfig..."
        make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" bb.org_defconfig
    fi

    print_success "Kernel configuration ready"
}

build_debian_packages() {
    local clean_build="$1"
    local no_debug="$2"

    print_status "Building Debian packages using bindeb-pkg..."

    cd "$KERNEL_DIR"

    # Clean if requested
    if [[ "$clean_build" == "clean" ]]; then
        print_status "Cleaning kernel build..."
        make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" clean
    fi

    # Prepare configuration
    prepare_kernel_config "$no_debug"

    # Extract LOCALVERSION from kernel_version
    # Format: 5.10.233-bone79 -> LOCALVERSION=-bone79
    local localversion=$(echo "$KERNEL_VERSION" | sed 's/^[0-9]\+\.[0-9]\+\.[0-9]\+//')

    print_status "Building with LOCALVERSION=$localversion"
    print_status "Using $CORES parallel jobs..."
    print_status "This may take 10-30 minutes depending on your system..."

    # Build packages using official Debian method
    # This is the same approach used in BeagleBoard.org CI pipeline
    time make -j"$CORES" \
        ARCH="$ARCH" \
        CROSS_COMPILE="$CROSS_COMPILE" \
        LOCALVERSION="$localversion" \
        KDEB_SOURCENAME="$KDEB_SOURCENAME" \
        KDEB_PKGVERSION="$KDEB_PKGVERSION" \
        KDEB_COMPRESS=xz \
        bindeb-pkg

    # Move packages to deploy directory for organization
    mkdir -p "$DEPLOY_DIR/packages"
    mv ../*.deb "$DEPLOY_DIR/packages/" 2>/dev/null || true

    print_success "Debian packages built successfully!"

    # List created packages
    print_status "Created packages:"
    ls -la "$DEPLOY_DIR/packages/"*.deb
}

validate_packages() {
    print_status "Validating created packages..."

    local package_dir="$DEPLOY_DIR/packages"
    local required_packages=("linux-image" "linux-headers")
    local missing_packages=()

    for pkg in "${required_packages[@]}"; do
        if ! ls "$package_dir"/${pkg}-*.deb >/dev/null 2>&1; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        print_error "Missing required packages: ${missing_packages[*]}"
    fi

    # Check package integrity
    for deb in "$package_dir"/*.deb; do
        if ! dpkg-deb --info "$deb" >/dev/null 2>&1; then
            print_error "Corrupt package: $(basename "$deb")"
        fi
    done

    print_success "All packages validated successfully"
}

deploy_packages() {
    print_status "Deploying packages to $REMOTE_HOST..."

    local package_dir="$DEPLOY_DIR/packages"

    # Test SSH connection
    if ! ssh -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" 'echo "SSH OK"' >/dev/null 2>&1; then
        print_error "Cannot connect to $REMOTE_HOST via SSH"
    fi

    # Create remote directory
    ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_TMP_DIR"

    # Transfer packages
    print_status "Transferring packages..."
    rsync -avz --progress "$package_dir"/*.deb "$REMOTE_USER@$REMOTE_HOST:$REMOTE_TMP_DIR/"

    print_success "Packages transferred successfully"

    # Show package information on remote
    print_status "Package information on target device:"
    ssh "$REMOTE_USER@$REMOTE_HOST" "
        cd $REMOTE_TMP_DIR
        echo 'Available packages:'
        ls -la *.deb
        echo
        echo 'Package details:'
        for deb in *.deb; do
            echo \"=== \$deb ===\"
            dpkg-deb --info \"\$deb\" | grep -E '(Package|Version|Architecture|Description)'
            echo
        done
    "
}

install_packages() {
    print_status "Installing packages on target device..."

    # Create installation script
    local install_script=$(cat << 'EOF'
#!/bin/bash
set -e

cd /tmp/kernel-packages

echo "=== Current kernel ==="
uname -r

echo "=== Available disk space ==="
df -h /

echo "=== Installing packages ==="
# Install in correct order: headers first, then image
if ls linux-headers-*.deb >/dev/null 2>&1; then
    echo "Installing headers..."
    dpkg -i linux-headers-*.deb
fi

if ls linux-image-[0-9]*.deb >/dev/null 2>&1; then
    echo "Installing kernel image..."
    dpkg -i linux-image-[0-9]*.deb
fi

if ls linux-firmware-*.deb >/dev/null 2>&1; then
    echo "Installing firmware..."
    dpkg -i linux-firmware-*.deb
fi

echo "=== Installation complete ==="
echo "Installed packages:"
dpkg -l | grep linux-image
dpkg -l | grep linux-headers

echo "=== Boot configuration ==="
if [[ -f /boot/uEnv.txt ]]; then
    echo "Current uEnv.txt:"
    grep uname_r /boot/uEnv.txt || echo "No uname_r found"
fi

echo "=== Ready to reboot ==="
echo "New kernel will be active after reboot"
echo "Run 'reboot' when ready"
EOF
)

    # Execute installation on remote device
    ssh "$REMOTE_USER@$REMOTE_HOST" "$install_script"

    print_success "Packages installed successfully!"
    print_warning "Reboot the device to use the new kernel"

    # Ask if user wants to reboot now
    echo
    read -p "Reboot device now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Rebooting device..."
        ssh "$REMOTE_USER@$REMOTE_HOST" "reboot" || true
        print_success "Reboot initiated"
    else
        print_status "Manual reboot required: ssh $REMOTE_USER@$REMOTE_HOST 'reboot'"
    fi
}

cleanup_old_packages() {
    print_status "Cleaning up old packages..."

    # Clean local packages older than 7 days
    find "$DEPLOY_DIR/packages" -name "*.deb" -mtime +7 -delete 2>/dev/null || true

    # Clean remote packages
    ssh "$REMOTE_USER@$REMOTE_HOST" "
        # Keep only the 3 most recent package sets
        cd $REMOTE_TMP_DIR 2>/dev/null || exit 0
        ls -t linux-image-*.deb 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null || true
        ls -t linux-headers-*.deb 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null || true
    " 2>/dev/null || true

    print_success "Cleanup completed"
}

main() {
    local action="full"
    local clean_build=""
    local no_debug=""

    # Parse arguments
    for arg in "$@"; do
        case $arg in
            build-only)
                action="build"
                ;;
            deploy-only)
                action="deploy"
                ;;
            clean-build)
                clean_build="clean"
                ;;
            no-debug)
                no_debug="no-debug"
                ;;
            help|--help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $arg (use 'help' for usage)"
                ;;
        esac
    done

    print_status "Enhanced Kernel Sync Script - Debian Package Method"
    print_status "============================================"

    # Validate environment
    if [[ ! -d "$BB_KERNEL_DIR" ]]; then
        print_error "bb-kernel directory not found: $BB_KERNEL_DIR"
    fi

    if [[ ! -d "$KERNEL_DIR" ]]; then
        print_error "KERNEL directory not found: $KERNEL_DIR"
    fi

    # Detect kernel version
    detect_kernel_version

    # Execute based on action
    case $action in
        "build")
            check_dependencies
            build_debian_packages "$clean_build" "$no_debug"
            validate_packages
            print_success "Build completed. Use 'deploy-only' to deploy packages."
            ;;
        "deploy")
            if [[ ! -d "$DEPLOY_DIR/packages" ]] || [[ -z "$(ls -A "$DEPLOY_DIR/packages"/*.deb 2>/dev/null)" ]]; then
                print_error "No packages found. Run 'build-only' first."
            fi
            deploy_packages
            install_packages
            cleanup_old_packages
            ;;
        "full")
            check_dependencies
            build_debian_packages "$clean_build" "$no_debug"
            validate_packages
            deploy_packages
            install_packages
            cleanup_old_packages
            print_success "Complete kernel deployment finished!"
            ;;
    esac

    print_success "Script completed successfully!"
}

# Run main function with all arguments
main "$@"
