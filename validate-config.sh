#!/bin/bash

# HTTP Boot Infrastructure - Configuration Validation Script
# ===========================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global validation status
VALIDATION_PASSED=true
VALIDATION_ERRORS=()
VALIDATION_WARNINGS=()

# Load configuration
load_config() {
    if [[ ! -f .env ]]; then
        echo -e "${RED}❌ Configuration file .env not found${NC}"
        echo "Run this script from the project root directory or create .env from .env.example"
        exit 1
    fi
    
    # Load environment variables
    export $(grep -v '^#' .env | grep -v '^$' | xargs)
    echo -e "${BLUE}📋 Configuration loaded from .env${NC}"
}

# Add validation error
add_error() {
    VALIDATION_ERRORS+=("$1")
    VALIDATION_PASSED=false
}

# Add validation warning
add_warning() {
    VALIDATION_WARNINGS+=("$1")
}

# Validate IP address format
validate_ip() {
    local ip="$1"
    local name="$2"
    
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        add_error "$name: Invalid IP address format: $ip"
        return 1
    fi
    
    IFS='.' read -ra ADDR <<< "$ip"
    for i in "${ADDR[@]}"; do
        if [[ $i -lt 0 || $i -gt 255 ]]; then
            add_error "$name: Invalid IP address octets: $ip"
            return 1
        fi
    done
    
    return 0
}

# Validate CIDR notation
validate_cidr() {
    local cidr="$1"
    local name="$2"
    
    if [[ ! $cidr =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        add_error "$name: Invalid CIDR format: $cidr"
        return 1
    fi
    
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"
    
    validate_ip "$ip" "$name (network part)" || return 1
    
    if [[ $prefix -lt 8 || $prefix -gt 30 ]]; then
        add_error "$name: Invalid CIDR prefix: /$prefix (must be between /8 and /30)"
        return 1
    fi
    
    return 0
}

# Check if IP is in subnet
ip_in_subnet() {
    local ip="$1"
    local subnet="$2"
    
    local subnet_ip="${subnet%/*}"
    local prefix="${subnet#*/}"
    
    # Convert IP addresses to integers for comparison
    ip_to_int() {
        local ip="$1"
        local a b c d
        IFS='.' read -r a b c d <<< "$ip"
        echo $((a * 256**3 + b * 256**2 + c * 256 + d))
    }
    
    local ip_int=$(ip_to_int "$ip")
    local subnet_int=$(ip_to_int "$subnet_ip")
    local mask_int=$(( 0xffffffff << (32 - prefix) ))
    
    [[ $((ip_int & mask_int)) -eq $((subnet_int & mask_int)) ]]
}

# Validate network configuration
validate_network_config() {
    echo -e "${BLUE}🔍 Validating Network Configuration...${NC}"
    
    # Validate subnet
    if [[ -z "${NETWORK_SUBNET:-}" ]]; then
        add_error "NETWORK_SUBNET is not set"
    else
        validate_cidr "$NETWORK_SUBNET" "NETWORK_SUBNET"
    fi
    
    # Validate host IP
    if [[ -z "${HOST_IP:-}" ]]; then
        add_error "HOST_IP is not set"
    else
        validate_ip "$HOST_IP" "HOST_IP"
        if [[ -n "${NETWORK_SUBNET:-}" ]] && validate_cidr "$NETWORK_SUBNET" "temp" &>/dev/null; then
            if ! ip_in_subnet "$HOST_IP" "$NETWORK_SUBNET"; then
                add_error "HOST_IP ($HOST_IP) is not within NETWORK_SUBNET ($NETWORK_SUBNET)"
            fi
        fi
    fi
    
    # Validate gateway IP
    if [[ -z "${GATEWAY_IP:-}" ]]; then
        add_error "GATEWAY_IP is not set"
    else
        validate_ip "$GATEWAY_IP" "GATEWAY_IP"
    fi
    
    # Validate DNS servers
    if [[ -z "${DNS_PRIMARY:-}" ]]; then
        add_error "DNS_PRIMARY is not set"
    else
        validate_ip "$DNS_PRIMARY" "DNS_PRIMARY"
    fi
    
    if [[ -n "${DNS_SECONDARY:-}" ]]; then
        validate_ip "$DNS_SECONDARY" "DNS_SECONDARY"
    fi
    
    # Validate DHCP range
    if [[ -z "${DHCP_RANGE_START:-}" ]]; then
        add_error "DHCP_RANGE_START is not set"
    else
        validate_ip "$DHCP_RANGE_START" "DHCP_RANGE_START"
    fi
    
    if [[ -z "${DHCP_RANGE_END:-}" ]]; then
        add_error "DHCP_RANGE_END is not set"
    else
        validate_ip "$DHCP_RANGE_END" "DHCP_RANGE_END"
    fi
    
    # Validate DHCP range is within subnet
    if [[ -n "${NETWORK_SUBNET:-}" && -n "${DHCP_RANGE_START:-}" && -n "${DHCP_RANGE_END:-}" ]]; then
        if validate_cidr "$NETWORK_SUBNET" "temp" &>/dev/null && \
           validate_ip "$DHCP_RANGE_START" "temp" &>/dev/null && \
           validate_ip "$DHCP_RANGE_END" "temp" &>/dev/null; then
            
            if ! ip_in_subnet "$DHCP_RANGE_START" "$NETWORK_SUBNET"; then
                add_error "DHCP_RANGE_START ($DHCP_RANGE_START) is not within NETWORK_SUBNET ($NETWORK_SUBNET)"
            fi
            
            if ! ip_in_subnet "$DHCP_RANGE_END" "$NETWORK_SUBNET"; then
                add_error "DHCP_RANGE_END ($DHCP_RANGE_END) is not within NETWORK_SUBNET ($NETWORK_SUBNET)"
            fi
        fi
    fi
    
    # Check if HOST_IP is in DHCP range
    if [[ -n "${HOST_IP:-}" && -n "${DHCP_RANGE_START:-}" && -n "${DHCP_RANGE_END:-}" ]]; then
        local host_int=$(ip_to_int() { local a b c d; IFS='.' read -r a b c d <<< "$1"; echo $((a * 256**3 + b * 256**2 + c * 256 + d)); }; ip_to_int "$HOST_IP")
        local start_int=$(ip_to_int() { local a b c d; IFS='.' read -r a b c d <<< "$1"; echo $((a * 256**3 + b * 256**2 + c * 256 + d)); }; ip_to_int "$DHCP_RANGE_START")
        local end_int=$(ip_to_int() { local a b c d; IFS='.' read -r a b c d <<< "$1"; echo $((a * 256**3 + b * 256**2 + c * 256 + d)); }; ip_to_int "$DHCP_RANGE_END")
        
        if [[ $host_int -ge $start_int && $host_int -le $end_int ]]; then
            add_error "HOST_IP ($HOST_IP) conflicts with DHCP range ($DHCP_RANGE_START - $DHCP_RANGE_END)"
        fi
    fi
    
    # Validate ports
    if [[ -z "${HTTP_PORT:-}" ]]; then
        add_error "HTTP_PORT is not set"
    elif [[ ! "${HTTP_PORT}" =~ ^[0-9]+$ ]] || [[ "${HTTP_PORT}" -lt 1 || "${HTTP_PORT}" -gt 65535 ]]; then
        add_error "HTTP_PORT must be a number between 1-65535"
    elif [[ "${HTTP_PORT}" -lt 1024 ]] && [[ $EUID -ne 0 ]]; then
        add_warning "HTTP_PORT ${HTTP_PORT} requires root privileges"
    fi
    
    if [[ -z "${TFTP_PORT:-}" ]]; then
        add_error "TFTP_PORT is not set"
    elif [[ ! "${TFTP_PORT}" =~ ^[0-9]+$ ]] || [[ "${TFTP_PORT}" -lt 1 || "${TFTP_PORT}" -gt 65535 ]]; then
        add_error "TFTP_PORT must be a number between 1-65535"
    elif [[ "${TFTP_PORT}" -lt 1024 ]] && [[ $EUID -ne 0 ]]; then
        add_warning "TFTP_PORT ${TFTP_PORT} requires root privileges"
    fi
}

# Check port availability
check_port_availability() {
    echo -e "${BLUE}🔍 Checking Port Availability...${NC}"
    
    local ports=("${HTTP_PORT:-8080}" "${TFTP_PORT:-69}")
    
    for port in "${ports[@]}"; do
        if command -v ss >/dev/null 2>&1; then
            if ss -tulpn | grep -q ":${port} "; then
                add_warning "Port $port appears to be in use"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tulpn 2>/dev/null | grep -q ":${port} "; then
                add_warning "Port $port appears to be in use"
            fi
        else
            add_warning "Cannot check port availability (ss/netstat not found)"
        fi
    done
}

# Validate system requirements
validate_system_requirements() {
    echo -e "${BLUE}🔍 Validating System Requirements...${NC}"
    
    # Check Podman installation
    if ! command -v podman >/dev/null 2>&1; then
        add_error "Podman is not installed or not in PATH"
    else
        local podman_version=$(podman --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        echo "  ✓ Podman version: $podman_version"
        
        # Check if version is >= 3.0.0
        local min_version="3.0.0"
        if ! printf '%s\n%s\n' "$min_version" "$podman_version" | sort -V | head -1 | grep -q "^$min_version$"; then
            add_warning "Podman version $podman_version may be too old (recommended: >= 3.0.0)"
        fi
    fi
    
    # Check internet connectivity
    echo "  🌐 Testing internet connectivity..."
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        add_error "No internet connectivity detected"
    else
        echo "  ✓ Internet connectivity confirmed"
    fi
    
    # Check write permissions for data directory
    local data_dir="${DATA_DIRECTORY:-./data}"
    local data_dir_parent=$(dirname "$data_dir")
    
    if [[ ! -d "$data_dir_parent" ]]; then
        add_error "Parent directory for DATA_DIRECTORY does not exist: $data_dir_parent"
    elif [[ ! -w "$data_dir_parent" ]]; then
        add_error "No write permission for DATA_DIRECTORY parent: $data_dir_parent"
    else
        echo "  ✓ Write permissions confirmed for data directory"
    fi
    
    # Check available disk space
    local available_space=$(df -BG "$data_dir_parent" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -lt 2 ]]; then
        add_error "Insufficient disk space. Available: ${available_space}GB, Required: 2GB minimum"
    else
        echo "  ✓ Sufficient disk space: ${available_space}GB available"
    fi
    
    # Check SELinux/AppArmor compatibility
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status=$(getenforce 2>/dev/null || echo "Unknown")
        if [[ "$selinux_status" == "Enforcing" ]]; then
            add_warning "SELinux is enforcing - container may need additional permissions"
        fi
        echo "  ✓ SELinux status: $selinux_status"
    fi
    
    if command -v aa-status >/dev/null 2>&1; then
        if aa-status --enabled 2>/dev/null; then
            add_warning "AppArmor is active - container may need additional permissions"
            echo "  ✓ AppArmor is active"
        fi
    fi
}

# Validate configuration completeness
validate_configuration() {
    echo -e "${BLUE}🔍 Validating Configuration Completeness...${NC}"
    
    # Required variables
    local required_vars=(
        "NETWORK_SUBNET"
        "DHCP_RANGE_START"
        "DHCP_RANGE_END"
        "GATEWAY_IP"
        "DNS_PRIMARY"
        "HOST_IP"
        "HTTP_PORT"
        "TFTP_PORT"
        "PRIMARY_DISTRO"
        "ARCHITECTURE"
        "BOOT_METHOD"
        "CONTAINER_NAME"
        "DATA_DIRECTORY"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            add_error "Required variable $var is not set"
        fi
    done
    
    # Validate distribution settings
    local valid_distros=("debian" "ubuntu" "centos" "fedora")
    if [[ -n "${PRIMARY_DISTRO:-}" ]]; then
        if [[ ! " ${valid_distros[*]} " =~ " ${PRIMARY_DISTRO} " ]]; then
            add_error "Invalid PRIMARY_DISTRO: ${PRIMARY_DISTRO}. Valid options: ${valid_distros[*]}"
        fi
    fi
    
    # Validate architecture
    local valid_archs=("amd64" "arm64" "i386")
    if [[ -n "${ARCHITECTURE:-}" ]]; then
        if [[ ! " ${valid_archs[*]} " =~ " ${ARCHITECTURE} " ]]; then
            add_error "Invalid ARCHITECTURE: ${ARCHITECTURE}. Valid options: ${valid_archs[*]}"
        fi
    fi
    
    # Validate boot method
    local valid_boot_methods=("bios" "uefi" "both")
    if [[ -n "${BOOT_METHOD:-}" ]]; then
        if [[ ! " ${valid_boot_methods[*]} " =~ " ${BOOT_METHOD} " ]]; then
            add_error "Invalid BOOT_METHOD: ${BOOT_METHOD}. Valid options: ${valid_boot_methods[*]}"
        fi
    fi
    
    # Validate boolean values
    local boolean_vars=(
        "ENABLE_SECURE_BOOT"
        "ENABLE_HTTP_AUTH"
        "ENABLE_SSL"
        "ENABLE_DHCP_RELAY"
        "ENABLE_ACCESS_LOG"
        "ENABLE_AUTO_BACKUP"
        "ENABLE_FIREWALL_RULES"
    )
    
    for var in "${boolean_vars[@]}"; do
        if [[ -n "${!var:-}" && ! "${!var}" =~ ^(true|false)$ ]]; then
            add_error "$var must be 'true' or 'false', got: ${!var}"
        fi
    done
    
    # Validate timeout values
    if [[ -n "${BOOT_TIMEOUT:-}" && ! "${BOOT_TIMEOUT}" =~ ^[0-9]+$ ]]; then
        add_error "BOOT_TIMEOUT must be a number"
    fi
    
    # Validate HTTP authentication settings
    if [[ "${ENABLE_HTTP_AUTH:-false}" == "true" ]]; then
        if [[ -z "${HTTP_USERNAME:-}" ]]; then
            add_error "HTTP_USERNAME is required when ENABLE_HTTP_AUTH=true"
        fi
        if [[ -z "${HTTP_PASSWORD:-}" || "${HTTP_PASSWORD}" == "changeme" ]]; then
            add_warning "Using default HTTP_PASSWORD - change for production use"
        fi
    fi
    
    # Validate SSL settings
    if [[ "${ENABLE_SSL:-false}" == "true" ]]; then
        if [[ -z "${SSL_CERT_PATH:-}" ]]; then
            add_error "SSL_CERT_PATH is required when ENABLE_SSL=true"
        elif [[ ! -f "${SSL_CERT_PATH}" ]]; then
            add_error "SSL certificate file not found: ${SSL_CERT_PATH}"
        fi
        
        if [[ -z "${SSL_KEY_PATH:-}" ]]; then
            add_error "SSL_KEY_PATH is required when ENABLE_SSL=true"
        elif [[ ! -f "${SSL_KEY_PATH}" ]]; then
            add_error "SSL key file not found: ${SSL_KEY_PATH}"
        fi
    fi
}

# Test repository connectivity
test_repository_connectivity() {
    echo -e "${BLUE}🔍 Testing Repository Connectivity...${NC}"
    
    local test_urls=()
    
    case "${PRIMARY_DISTRO:-debian}" in
        "debian")
            test_urls+=("${DEBIAN_MIRROR:-http://deb.debian.org/debian}/dists/${DEBIAN_RELEASE:-bookworm}/Release")
            ;;
        "ubuntu")
            test_urls+=("${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}/dists/${UBUNTU_RELEASE:-jammy}/Release")
            ;;
        "centos")
            test_urls+=("${CENTOS_MIRROR:-http://mirror.centos.org/centos}/")
            ;;
        "fedora")
            test_urls+=("${FEDORA_MIRROR:-http://download.fedoraproject.org/pub/fedora/linux}/")
            ;;
    esac
    
    for url in "${test_urls[@]}"; do
        echo "  🌐 Testing: $url"
        if command -v curl >/dev/null 2>&1; then
            if curl -s --head --connect-timeout 10 "$url" | head -1 | grep -q "200 OK"; then
                echo "  ✓ Repository accessible"
            else
                add_warning "Repository may not be accessible: $url"
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget --spider --timeout=10 "$url" 2>/dev/null; then
                echo "  ✓ Repository accessible"
            else
                add_warning "Repository may not be accessible: $url"
            fi
        else
            add_warning "Cannot test repository connectivity (curl/wget not found)"
        fi
    done
}

# Main validation function
main() {
    echo -e "${BLUE}🔍 HTTP Boot Setup - Configuration Validation${NC}"
    echo "════════════════════════════════════════════════════════"
    
    load_config
    
    validate_network_config
    check_port_availability
    validate_system_requirements
    validate_configuration
    test_repository_connectivity
    
    echo ""
    echo "════════════════════════════════════════════════════════"
    
    # Display warnings
    if [[ ${#VALIDATION_WARNINGS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Validation Warnings:${NC}"
        for warning in "${VALIDATION_WARNINGS[@]}"; do
            echo -e "${YELLOW}   • $warning${NC}"
        done
        echo ""
    fi
    
    # Display errors
    if [[ ${#VALIDATION_ERRORS[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Validation Errors:${NC}"
        for error in "${VALIDATION_ERRORS[@]}"; do
            echo -e "${RED}   • $error${NC}"
        done
        echo ""
        echo -e "${RED}❌ Validation FAILED. Please fix the above errors before proceeding.${NC}"
        exit 1
    fi
    
    if [[ $VALIDATION_PASSED == true ]]; then
        echo -e "${GREEN}✅ All validations passed successfully!${NC}"
        echo -e "${GREEN}🎯 Configuration is ready for deployment.${NC}"
        
        if [[ ${#VALIDATION_WARNINGS[@]} -gt 0 ]]; then
            echo -e "${YELLOW}⚠️  Note: There are warnings above that should be reviewed.${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}📋 Configuration Summary:${NC}"
        echo "   Network: ${NETWORK_SUBNET}"
        echo "   Host IP: ${HOST_IP}"
        echo "   DHCP Range: ${DHCP_RANGE_START} - ${DHCP_RANGE_END}"
        echo "   HTTP Port: ${HTTP_PORT}"
        echo "   TFTP Port: ${TFTP_PORT}"
        echo "   Distribution: ${PRIMARY_DISTRO} (${ARCHITECTURE})"
        echo "   Boot Method: ${BOOT_METHOD}"
        echo "   Container: ${CONTAINER_NAME}"
        echo ""
        echo -e "${GREEN}✅ Ready to proceed with setup.sh${NC}"
        exit 0
    fi
}

# Run validation
main "$@"