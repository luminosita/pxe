#!/bin/bash

# HTTP Boot Infrastructure - Distribution Image Download Script
# =============================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration with defaults
PRIMARY_DISTRO="${PRIMARY_DISTRO:-debian}"
ARCHITECTURE="${ARCHITECTURE:-amd64}"
DEBIAN_RELEASE="${DEBIAN_RELEASE:-stable}"
UBUNTU_RELEASE="${UBUNTU_RELEASE:-noble}"
CENTOS_RELEASE="${CENTOS_RELEASE:-9-stream}"
FEDORA_RELEASE="${FEDORA_RELEASE:-39}"
DATA_DIRECTORY="${DATA_DIRECTORY:-./data}"

# Mirror URLs
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
UBUNTU_MIRROR="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
CENTOS_MIRROR="${CENTOS_MIRROR:-http://mirror.centos.org/centos}"
FEDORA_MIRROR="${FEDORA_MIRROR:-http://download.fedoraproject.org/pub/fedora/linux}"

# Paths
TFTP_DIR="$DATA_DIRECTORY/tftp"
HTTP_DIR="$DATA_DIRECTORY/http"
IMAGES_DIR="$DATA_DIRECTORY/images"

print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Create directory structure
create_directories() {
    local dirs=(
        "$TFTP_DIR"
        "$HTTP_DIR"
        "$IMAGES_DIR"
        "$TFTP_DIR/pxelinux.cfg"
        "$HTTP_DIR/boot"
        "$HTTP_DIR/images"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            print_status "$GREEN" "✅ Created directory: $dir"
        fi
    done
}

# Download with progress and retry
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts="${3:-3}"
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        print_status "$BLUE" "🔄 Attempt $attempt/$max_attempts: $(basename "$output")"
        
        if curl -L --progress-bar \
               --connect-timeout 30 \
               --max-time 300 \
               --retry 0 \
               -C - \
               -o "$output" \
               "$url"; then
            print_status "$GREEN" "✅ Downloaded: $(basename "$output")"
            return 0
        else
            print_status "$YELLOW" "⚠️  Attempt $attempt failed"
            if [[ $attempt -lt $max_attempts ]]; then
                sleep $((attempt * 2))
            fi
        fi
        ((attempt++))
    done
    
    print_status "$RED" "❌ Failed to download: $url"
    return 1
}

# Download Debian netboot files
download_debian() {
    print_header "📦 Downloading Debian $DEBIAN_RELEASE ($ARCHITECTURE) Netboot Files"
    
    local netboot_url="$DEBIAN_MIRROR/dists/$DEBIAN_RELEASE/main/installer-$ARCHITECTURE/current/images/netboot/netboot.tar.gz"
    local netboot_file="$IMAGES_DIR/debian-$DEBIAN_RELEASE-netboot.tar.gz"
    
    print_status "$BLUE" "🌐 Source: $netboot_url"
    
    # Download netboot archive
    if download_with_retry "$netboot_url" "$netboot_file"; then
        print_status "$BLUE" "📦 Extracting netboot files..."
        
        # Extract to TFTP directory
        if tar -xzf "$netboot_file" -C "$TFTP_DIR"; then
            print_status "$GREEN" "✅ Debian netboot files extracted successfully"
            
            # Create symlinks in HTTP directory for web access
            cd "$HTTP_DIR/boot" && ln -sf ../../tftp/* . 2>/dev/null || true
            
            # Download additional components
            download_debian_extras
        else
            print_status "$RED" "❌ Failed to extract netboot archive"
            return 1
        fi
    else
        return 1
    fi
}

# Download additional Debian components
download_debian_extras() {
    print_status "$BLUE" "📦 Downloading additional Debian components..."
    
    local base_url="$DEBIAN_MIRROR/dists/$DEBIAN_RELEASE/main/installer-$ARCHITECTURE/current/images"
    local components=(
        "$base_url/hd-media/initrd.gz:debian-hd-initrd.gz"
        "$base_url/hd-media/vmlinuz:debian-hd-vmlinuz"
    )
    
    for component in "${components[@]}"; do
        local url="${component%:*}"
        local filename="${component#*:}"
        local output="$IMAGES_DIR/$filename"
        
        if download_with_retry "$url" "$output"; then
            ln -sf "$output" "$HTTP_DIR/images/" 2>/dev/null || true
        fi
    done
}

# Download Ubuntu netboot files
download_ubuntu() {
    print_header "📦 Downloading Ubuntu $UBUNTU_RELEASE ($ARCHITECTURE) Netboot Files"
    
    local netboot_url="$UBUNTU_MIRROR/dists/$UBUNTU_RELEASE/main/installer-$ARCHITECTURE/current/legacy-images/netboot/netboot.tar.gz"
    local netboot_file="$IMAGES_DIR/ubuntu-$UBUNTU_RELEASE-netboot.tar.gz"
    
    print_status "$BLUE" "🌐 Source: $netboot_url"
    
    # Download netboot archive
    if download_with_retry "$netboot_url" "$netboot_file"; then
        print_status "$BLUE" "📦 Extracting netboot files..."
        
        # Extract to TFTP directory (preserve existing files)
        if tar -xzf "$netboot_file" -C "$TFTP_DIR"; then
            print_status "$GREEN" "✅ Ubuntu netboot files extracted successfully"
            
            # Create symlinks in HTTP directory for web access
            cd "$HTTP_DIR/boot" && ln -sf ../../tftp/* . 2>/dev/null || true
            
            # Download additional components
            download_ubuntu_extras
        else
            print_status "$RED" "❌ Failed to extract netboot archive"
            return 1
        fi
    else
        return 1
    fi
}

# Download additional Ubuntu components
download_ubuntu_extras() {
    print_status "$BLUE" "📦 Downloading additional Ubuntu components..."
    
    local base_url="$UBUNTU_MIRROR/dists/$UBUNTU_RELEASE/main/installer-$ARCHITECTURE/current/legacy-images"
    local components=(
        "$base_url/hd-media/initrd.gz:ubuntu-hd-initrd.gz"
        "$base_url/hd-media/vmlinuz:ubuntu-hd-vmlinuz"
    )
    
    for component in "${components[@]}"; do
        local url="${component%:*}"
        local filename="${component#*:}"
        local output="$IMAGES_DIR/$filename"
        
        if download_with_retry "$url" "$output"; then
            ln -sf "$output" "$HTTP_DIR/images/" 2>/dev/null || true
        fi
    done
}

# Download CentOS Stream boot files
download_centos() {
    print_header "📦 Downloading CentOS Stream $CENTOS_RELEASE ($ARCHITECTURE) Boot Files"
    
    local arch_dir
    case "$ARCHITECTURE" in
        "amd64"|"x86_64") arch_dir="x86_64" ;;
        "arm64"|"aarch64") arch_dir="aarch64" ;;
        *) 
            print_status "$RED" "❌ Unsupported architecture for CentOS: $ARCHITECTURE"
            return 1
            ;;
    esac
    
    local base_url="$CENTOS_MIRROR/$CENTOS_RELEASE/BaseOS/$arch_dir/os"
    local boot_files=(
        "$base_url/images/pxeboot/vmlinuz:centos-vmlinuz"
        "$base_url/images/pxeboot/initrd.img:centos-initrd.img"
    )
    
    print_status "$BLUE" "🌐 Source: $base_url"
    
    for boot_file in "${boot_files[@]}"; do
        local url="${boot_file%:*}"
        local filename="${boot_file#*:}"
        local output="$IMAGES_DIR/$filename"
        
        if download_with_retry "$url" "$output"; then
            ln -sf "$output" "$HTTP_DIR/images/" 2>/dev/null || true
            ln -sf "$output" "$TFTP_DIR/" 2>/dev/null || true
        fi
    done
    
    # Create CentOS-specific PXE configuration
    create_centos_pxe_config
}

# Create CentOS PXE configuration
create_centos_pxe_config() {
    local config_file="$TFTP_DIR/pxelinux.cfg/centos"
    
    cat > "$config_file" << 'EOF'
DEFAULT centos-install

LABEL centos-install
    MENU LABEL CentOS Stream Installation
    KERNEL centos-vmlinuz
    APPEND initrd=centos-initrd.img inst.repo=http://mirror.centos.org/centos/9-stream/BaseOS/x86_64/os/ inst.stage2=http://mirror.centos.org/centos/9-stream/BaseOS/x86_64/os/
EOF
    
    print_status "$GREEN" "✅ Created CentOS PXE configuration"
}

# Download Fedora boot files
download_fedora() {
    print_header "📦 Downloading Fedora $FEDORA_RELEASE ($ARCHITECTURE) Boot Files"
    
    local arch_dir
    case "$ARCHITECTURE" in
        "amd64"|"x86_64") arch_dir="x86_64" ;;
        "arm64"|"aarch64") arch_dir="aarch64" ;;
        *) 
            print_status "$RED" "❌ Unsupported architecture for Fedora: $ARCHITECTURE"
            return 1
            ;;
    esac
    
    local base_url="$FEDORA_MIRROR/releases/$FEDORA_RELEASE/Everything/$arch_dir/os"
    local boot_files=(
        "$base_url/images/pxeboot/vmlinuz:fedora-vmlinuz"
        "$base_url/images/pxeboot/initrd.img:fedora-initrd.img"
    )
    
    print_status "$BLUE" "🌐 Source: $base_url"
    
    for boot_file in "${boot_files[@]}"; do
        local url="${boot_file%:*}"
        local filename="${boot_file#*:}"
        local output="$IMAGES_DIR/$filename"
        
        if download_with_retry "$url" "$output"; then
            ln -sf "$output" "$HTTP_DIR/images/" 2>/dev/null || true
            ln -sf "$output" "$TFTP_DIR/" 2>/dev/null || true
        fi
    done
    
    # Create Fedora-specific PXE configuration
    create_fedora_pxe_config
}

# Create Fedora PXE configuration
create_fedora_pxe_config() {
    local config_file="$TFTP_DIR/pxelinux.cfg/fedora"
    
    cat > "$config_file" << EOF
DEFAULT fedora-install

LABEL fedora-install
    MENU LABEL Fedora $FEDORA_RELEASE Installation
    KERNEL fedora-vmlinuz
    APPEND initrd=fedora-initrd.img inst.repo=http://download.fedoraproject.org/pub/fedora/linux/releases/$FEDORA_RELEASE/Everything/x86_64/os/ inst.stage2=http://download.fedoraproject.org/pub/fedora/linux/releases/$FEDORA_RELEASE/Everything/x86_64/os/
EOF
    
    print_status "$GREEN" "✅ Created Fedora PXE configuration"
}

# Create unified PXE boot menu
create_boot_menu() {
    print_header "📋 Creating Boot Menu Configuration"
    
    local default_config="$TFTP_DIR/pxelinux.cfg/default"
    
    cat > "$default_config" << EOF
DEFAULT menu.c32
PROMPT 0
TIMEOUT ${BOOT_TIMEOUT:-30}0
MENU TITLE HTTP Boot Infrastructure

LABEL local
    MENU LABEL Boot from local disk
    MENU DEFAULT
    LOCALBOOT 0

EOF
    
    # Add distribution-specific entries
    case "$PRIMARY_DISTRO" in
        "debian")
            cat >> "$default_config" << EOF
LABEL debian-install
    MENU LABEL Debian $DEBIAN_RELEASE Installation
    KERNEL debian-installer/$ARCHITECTURE/linux
    APPEND initrd=debian-installer/$ARCHITECTURE/initrd.gz

LABEL debian-rescue
    MENU LABEL Debian $DEBIAN_RELEASE Rescue Mode
    KERNEL debian-installer/$ARCHITECTURE/linux
    APPEND initrd=debian-installer/$ARCHITECTURE/initrd.gz rescue/enable=true

EOF
            ;;
        
        "ubuntu")
            cat >> "$default_config" << EOF
LABEL ubuntu-install
    MENU LABEL Ubuntu $UBUNTU_RELEASE Installation
    KERNEL ubuntu-installer/$ARCHITECTURE/linux
    APPEND initrd=ubuntu-installer/$ARCHITECTURE/initrd.gz

LABEL ubuntu-rescue
    MENU LABEL Ubuntu $UBUNTU_RELEASE Rescue Mode
    KERNEL ubuntu-installer/$ARCHITECTURE/linux
    APPEND initrd=ubuntu-installer/$ARCHITECTURE/initrd.gz rescue/enable=true

EOF
            ;;
    esac
    
    # Add custom entries if available
    if [[ -f "$TFTP_DIR/pxelinux.cfg/centos" ]]; then
        cat >> "$default_config" << EOF
LABEL centos
    MENU LABEL CentOS Stream Installation
    CONFIG pxelinux.cfg/centos

EOF
    fi
    
    if [[ -f "$TFTP_DIR/pxelinux.cfg/fedora" ]]; then
        cat >> "$default_config" << EOF
LABEL fedora
    MENU LABEL Fedora Installation
    CONFIG pxelinux.cfg/fedora

EOF
    fi
    
    print_status "$GREEN" "✅ Created unified boot menu"
}

# Verify downloaded files
verify_downloads() {
    print_header "🔍 Verifying Downloaded Files"
    
    local required_files=()
    local missing_files=()
    
    case "$PRIMARY_DISTRO" in
        "debian")
            required_files=(
                "$TFTP_DIR/pxelinux.0"
                "$TFTP_DIR/debian-installer"
                "$TFTP_DIR/pxelinux.cfg/default"
            )
            ;;
        "ubuntu")
            required_files=(
                "$TFTP_DIR/pxelinux.0"
                "$TFTP_DIR/ubuntu-installer"
                "$TFTP_DIR/pxelinux.cfg/default"
            )
            ;;
    esac
    
    for file in "${required_files[@]}"; do
        if [[ ! -e "$file" ]]; then
            missing_files+=("$file")
        else
            print_status "$GREEN" "✅ Found: $(basename "$file")"
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_status "$RED" "❌ Missing required files:"
        for file in "${missing_files[@]}"; do
            print_status "$RED" "   - $file"
        done
        return 1
    else
        print_status "$GREEN" "✅ All required files present"
        return 0
    fi
}

# Validate HTTP and TFTP access
validate_services() {
    print_header "🧪 Validating HTTP and TFTP Access"
    
    local http_port="${HTTP_PORT:-8080}"
    local tftp_port="${TFTP_PORT:-6969}"
    local host_ip="${HOST_IP:-127.0.0.1}"
    local container_name="${CONTAINER_NAME:-httpboot-server}"
    
    # Check if container is running
    if ! podman ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
        print_status "$YELLOW" "⚠️  Container $container_name is not running"
        print_status "$BLUE" "📋 Attempting to start container for validation..."
        
        # Try to start the container if it exists but stopped
        if podman ps -a --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
            podman start "$container_name" >/dev/null 2>&1 || true
            sleep 8
        else
            print_status "$YELLOW" "⚠️  Container not found - validation will be skipped"
            print_status "$BLUE" "💡 Run './setup.sh' to deploy the container first"
            return 0
        fi
    fi
    
    # Ensure logs directory exists
    mkdir -p "./data/logs" 2>/dev/null || true
    
    # Wait for services to be ready
    print_status "$BLUE" "⏳ Waiting for services to initialize..."
    sleep 5
    
    # Test HTTP Service
    print_status "$BLUE" "🌐 Testing HTTP service on port $http_port..."
    
    local http_success=false
    local max_attempts=5
    
    for ((i=1; i<=max_attempts; i++)); do
        if curl -sf "http://localhost:$http_port/health" >/dev/null 2>&1; then
            print_status "$GREEN" "✅ HTTP service health check passed"
            http_success=true
            break
        else
            if [[ $i -eq $max_attempts ]]; then
                print_status "$RED" "❌ HTTP service health check failed after $max_attempts attempts"
            else
                print_status "$YELLOW" "⏳ HTTP service attempt $i/$max_attempts..."
                sleep 2
            fi
        fi
    done
    
    # Test HTTP boot file access
    if [[ "$http_success" == "true" ]]; then
        local test_files=(
            "/boot/pxelinux.0"
            "/boot/debian-installer/amd64/linux"
            "/boot/debian-installer/amd64/initrd.gz"
        )
        
        for test_file in "${test_files[@]}"; do
            if curl -sf "http://localhost:$http_port$test_file" -o /dev/null 2>/dev/null; then
                print_status "$GREEN" "✅ HTTP access verified: $test_file"
            else
                print_status "$YELLOW" "⚠️  HTTP file not accessible: $test_file"
            fi
        done
    fi
    
    # Test TFTP Service  
    print_status "$BLUE" "📁 Testing TFTP service on port $tftp_port..."
    
    # Check if TFTP port is accessible
    local tftp_accessible=false
    if command -v nc >/dev/null 2>&1; then
        if timeout 3 nc -u -z localhost "$tftp_port" 2>/dev/null; then
            tftp_accessible=true
            print_status "$GREEN" "✅ TFTP port $tftp_port is accessible"
        else
            print_status "$YELLOW" "⚠️  TFTP port $tftp_port connectivity test failed"
        fi
    else
        print_status "$YELLOW" "⚠️  netcat not available, skipping TFTP port test"
    fi
    
    # Advanced TFTP testing if tftp client is available
    if command -v tftp >/dev/null 2>&1 && [[ "$tftp_accessible" == "true" ]]; then
        print_status "$BLUE" "🔧 Testing TFTP file operations..."
        
        # Create a unique test file
        local test_content="tftp-validation-$(date +%s)"
        local test_file="/tmp/tftp-validation-test.txt"
        echo "$test_content" > "$test_file"
        
        # Test TFTP get operation with timeout
        local tftp_get_success=false
        if timeout 10 bash -c "echo 'get pxelinux.0 /tmp/tftp-pxelinux-test.0' | tftp localhost $tftp_port" 2>/dev/null; then
            if [[ -f "/tmp/tftp-pxelinux-test.0" ]] && [[ -s "/tmp/tftp-pxelinux-test.0" ]]; then
                print_status "$GREEN" "✅ TFTP get operation successful"
                tftp_get_success=true
                rm -f "/tmp/tftp-pxelinux-test.0" 2>/dev/null
            fi
        fi
        
        if [[ "$tftp_get_success" != "true" ]]; then
            print_status "$YELLOW" "⚠️  TFTP get operation test inconclusive"
        fi
        
        # Cleanup test files
        rm -f "$test_file" 2>/dev/null
    else
        if [[ "$tftp_accessible" == "true" ]]; then
            print_status "$GREEN" "✅ TFTP service appears to be running"
        fi
    fi
    
    # Container status summary
    print_status "$BLUE" "📊 Container status summary:"
    if podman ps --filter "name=$container_name" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -v "^NAMES"; then
        print_status "$GREEN" "✅ Container is running with correct port mappings"
    else
        print_status "$RED" "❌ Container status check failed"
    fi
}

# Generate download summary
generate_summary() {
    print_header "📊 Download Summary"
    
    local tftp_size=$(du -sh "$TFTP_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    local http_size=$(du -sh "$HTTP_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    local images_size=$(du -sh "$IMAGES_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    
    cat << EOF
📁 Directory Sizes:
   TFTP Root: $tftp_size ($TFTP_DIR)
   HTTP Root: $http_size ($HTTP_DIR)
   Images: $images_size ($IMAGES_DIR)

📦 Primary Distribution: $PRIMARY_DISTRO
🏗️ Architecture: $ARCHITECTURE
🔧 Boot Method: ${BOOT_METHOD:-both}

🌐 Available Boot Options:
EOF
    
    if [[ -f "$TFTP_DIR/pxelinux.cfg/default" ]]; then
        echo "   - Network boot menu available"
        grep "MENU LABEL" "$TFTP_DIR/pxelinux.cfg/default" | sed 's/.*MENU LABEL/   -/' || true
    fi
    
    echo ""
    print_status "$GREEN" "🎉 Image download completed successfully!"
}

# Main function
main() {
    local download_all=false
    local force_download=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                download_all=true
                shift
                ;;
            --force)
                force_download=true
                shift
                ;;
            --distro)
                PRIMARY_DISTRO="$2"
                shift 2
                ;;
            --arch)
                ARCHITECTURE="$2"
                shift 2
                ;;
            --help|-h)
                cat << EOF
Distribution Image Download Script

Usage: $0 [OPTIONS]

Options:
    --all                Download all supported distributions
    --force              Force re-download even if files exist
    --distro DISTRO      Set primary distribution (debian, ubuntu, centos, fedora)
    --arch ARCH          Set architecture (amd64, arm64, i386)
    --help, -h           Show this help message

Environment Variables:
    PRIMARY_DISTRO       Primary distribution to download
    ARCHITECTURE         Target architecture
    DATA_DIRECTORY       Base directory for downloads
    DEBIAN_RELEASE       Debian release name
    UBUNTU_RELEASE       Ubuntu release name
    CENTOS_RELEASE       CentOS release version
    FEDORA_RELEASE       Fedora release version

Examples:
    $0                         # Download primary distribution
    $0 --all                   # Download all distributions
    $0 --distro ubuntu --arch arm64
    $0 --force                 # Force re-download

EOF
                exit 0
                ;;
            *)
                print_status "$RED" "❌ Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    print_header "📦 HTTP Boot Infrastructure - Image Download"
    print_status "$BLUE" "🎯 Primary Distribution: $PRIMARY_DISTRO"
    print_status "$BLUE" "🏗️ Architecture: $ARCHITECTURE"
    print_status "$BLUE" "📁 Data Directory: $DATA_DIRECTORY"
    
    # Create directories
    create_directories
    
    # Download based on configuration
    local success=true
    
    if [[ "$download_all" == "true" ]]; then
        print_status "$BLUE" "📦 Downloading all supported distributions..."
        
        for distro in debian ubuntu centos fedora; do
            case "$distro" in
                "debian") download_debian || success=false ;;
                "ubuntu") download_ubuntu || success=false ;;
                "centos") download_centos || success=false ;;
                "fedora") download_fedora || success=false ;;
            esac
        done
    else
        print_status "$BLUE" "📦 Downloading primary distribution: $PRIMARY_DISTRO..."
        
        case "$PRIMARY_DISTRO" in
            "debian") download_debian || success=false ;;
            "ubuntu") download_ubuntu || success=false ;;
            "centos") download_centos || success=false ;;
            "fedora") download_fedora || success=false ;;
            *)
                print_status "$RED" "❌ Unsupported distribution: $PRIMARY_DISTRO"
                success=false
                ;;
        esac
    fi
    
    # Create boot menu
    if [[ "$success" == "true" ]]; then
        create_boot_menu
        
        # Verify downloads
        if verify_downloads; then
            generate_summary

            # Validate HTTP and TFTP services
            validate_services
        else
            print_status "$RED" "❌ Download verification failed"
            exit 1
        fi
    else
        print_status "$RED" "❌ Some downloads failed"
        exit 1
    fi
}

# Run main function
main "$@"