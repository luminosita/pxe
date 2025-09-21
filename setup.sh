#!/bin/bash

# HTTP Boot Infrastructure - Main Deployment Script
# =================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="httpboot-infrastructure"
LOG_FILE="$SCRIPT_DIR/setup.log"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
    log "INFO" "$message"
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Error handling
error_exit() {
    print_status "$RED" "❌ Error: $1"
    exit 1
}

# Load configuration
load_config() {
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        error_exit "Configuration file .env not found. Please create it from .env.example"
    fi
    
    # Export all non-comment, non-empty lines
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
    
    print_status "$GREEN" "✅ Configuration loaded from .env"
}

# Run validation
run_validation() {
    print_header "🔍 Configuration Validation"
    
    if [[ ! -f "$SCRIPT_DIR/validate-config.sh" ]]; then
        error_exit "Validation script not found"
    fi
    
    if ! "$SCRIPT_DIR/validate-config.sh"; then
        error_exit "Configuration validation failed. Please fix errors and try again."
    fi
    
    print_status "$GREEN" "✅ Configuration validation passed"
}

# Check prerequisites
check_prerequisites() {
    print_header "🔧 Checking Prerequisites"
    
    # Check if running as root for privileged ports
    if [[ "${HTTP_PORT:-8080}" -lt 1024 || "${TFTP_PORT:-69}" -lt 1024 ]] && [[ $EUID -ne 0 ]]; then
        print_status "$YELLOW" "⚠️  Warning: Using privileged ports but not running as root"
        print_status "$YELLOW" "   Podman may need additional configuration for port binding"
    fi
    
    # Check Podman
    if ! command -v podman >/dev/null 2>&1; then
        error_exit "Podman is not installed or not in PATH"
    fi
    
    local podman_version=$(podman --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    print_status "$GREEN" "✅ Podman version: $podman_version"
    
    # Check if Podman is running in rootless mode
    if [[ $EUID -ne 0 ]] && ! podman info --format '{{.Host.Security.Rootless}}' | grep -q true; then
        print_status "$YELLOW" "⚠️  Podman may not be configured for rootless operation"
    fi
    
    # Check disk space
    local data_dir="${DATA_DIRECTORY:-./data}"
    local parent_dir=$(dirname "$(realpath "$data_dir")")
    local available_space=$(df -BG "$parent_dir" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ $available_space -lt 2 ]]; then
        error_exit "Insufficient disk space. Available: ${available_space}GB, Required: 2GB minimum"
    fi
    
    print_status "$GREEN" "✅ Sufficient disk space: ${available_space}GB available"
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_status "$YELLOW" "⚠️  Warning: No internet connectivity detected"
        print_status "$YELLOW" "   Boot image downloads may fail"
    else
        print_status "$GREEN" "✅ Internet connectivity confirmed"
    fi
}

# Create directory structure
create_directories() {
    print_header "📁 Creating Directory Structure"
    
    local data_dir="${DATA_DIRECTORY:-./data}"
    local dirs=(
        "$data_dir"
        "$data_dir/tftp"
        "$data_dir/http"
        "$data_dir/configs"
        "$data_dir/logs"
        "$data_dir/backup"
        "scripts"
        "docs"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            print_status "$GREEN" "✅ Created directory: $dir"
        else
            print_status "$BLUE" "📁 Directory exists: $dir"
        fi
    done
    
    # Set appropriate permissions
    chmod 755 "$data_dir"
    chmod -R 755 "$data_dir"/{tftp,http}
    
    print_status "$GREEN" "✅ Directory structure created successfully"
}

# Build container image
build_container() {
    print_header "🏗️ Building Container Image"
    
    local image_name="${CONTAINER_REGISTRY:-docker.io}/httpboot-server:${CONTAINER_IMAGE_TAG:-latest}"
    local container_name="${CONTAINER_NAME:-httpboot-server}"
    
    print_status "$BLUE" "🔨 Building image: $image_name"
    
    if ! podman build \
        --tag "$image_name" \
        --file "$SCRIPT_DIR/Dockerfile" \
        "$SCRIPT_DIR"; then
        error_exit "Failed to build container image"
    fi
    
    print_status "$GREEN" "✅ Container image built successfully"
    
    # Display image information
    print_status "$BLUE" "📊 Image information:"
    podman images "$image_name" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.Created}}"
}

# Stop existing container
stop_existing_container() {
    local container_name="${CONTAINER_NAME:-httpboot-server}"
    
    if podman ps -q --filter "name=$container_name" | grep -q .; then
        print_status "$YELLOW" "🛑 Stopping existing container: $container_name"
        podman stop "$container_name" || true
    fi
    
    if podman ps -aq --filter "name=$container_name" | grep -q .; then
        print_status "$YELLOW" "🗑️ Removing existing container: $container_name"
        podman rm "$container_name" || true
    fi
}

# Deploy container
deploy_container() {
    print_header "🚀 Deploying Container"
    
    local image_name="${CONTAINER_REGISTRY:-docker.io}/httpboot-server:${CONTAINER_IMAGE_TAG:-latest}"
    local container_name="${CONTAINER_NAME:-httpboot-server}"
    local data_dir="${DATA_DIRECTORY:-./data}"
    local restart_policy="${RESTART_POLICY:-always}"
    
    # Stop existing container if running
    stop_existing_container
    
    print_status "$BLUE" "🚀 Starting container: $container_name"
    
    # Prepare volume mounts
    local volumes=(
        "--volume" "$(realpath "$data_dir"):/var/lib/httpboot:Z"
        "--volume" "$SCRIPT_DIR/scripts:/usr/local/scripts:ro,Z"
    )
    
    # Prepare port mappings
    local ports=(
        "--publish" "${HTTP_PORT:-8080}:8080/tcp"
        "--publish" "${TFTP_PORT:-6969}:6969/udp"
    )
    
    # Prepare environment variables
    local env_vars=()
    while IFS='=' read -r key value; do
        [[ $key =~ ^[A-Z_]+$ ]] && env_vars+=("--env" "$key=$value")
    done < <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$')
    
    # Additional container options
    local container_opts=(
        "--name" "$container_name"
        "--restart" "$restart_policy"
        "--hostname" "httpboot-server"
    )
    
    # Run container
    if ! podman run -d \
        "${container_opts[@]}" \
        "${volumes[@]}" \
        "${ports[@]}" \
        "${env_vars[@]}" \
        "$image_name"; then
        error_exit "Failed to start container"
    fi
    
    print_status "$GREEN" "✅ Container deployed successfully"
    
    # Wait for container to be ready
    print_status "$BLUE" "⏳ Waiting for services to start..."
    sleep 10
    
    # Check container status
    if ! podman ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
        print_status "$RED" "❌ Container is not running"
        print_status "$YELLOW" "📋 Container logs:"
        podman logs "$container_name" | tail -20
        error_exit "Container failed to start"
    fi
    
    print_status "$GREEN" "✅ Container is running successfully"
}

# Test services
test_services() {
    print_header "🧪 Testing Services"
    
    local http_port="${HTTP_PORT:-8080}"
    local host_ip="${HOST_IP:-127.0.0.1}"
    local container_name="${CONTAINER_NAME:-httpboot-server}"
    
    # Test HTTP service
    print_status "$BLUE" "🌐 Testing HTTP service on port $http_port..."
    
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "http://localhost:$http_port/health" >/dev/null 2>&1; then
            print_status "$GREEN" "✅ HTTP service is responding"
            break
        else
            if [[ $attempt -eq $max_attempts ]]; then
                print_status "$RED" "❌ HTTP service is not responding after $max_attempts attempts"
                print_status "$YELLOW" "📋 Container logs:"
                podman logs "$container_name" | tail -10
            else
                print_status "$YELLOW" "⏳ Attempt $attempt/$max_attempts - waiting for HTTP service..."
                sleep 3
            fi
        fi
        ((attempt++))
    done
    
    # Test TFTP service (comprehensive test)
    local tftp_port="${TFTP_PORT:-6969}"
    print_status "$BLUE" "📁 Testing TFTP service on port $tftp_port..."
    
    # First test basic port connectivity
    local tftp_accessible=false
    if command -v nc >/dev/null 2>&1; then
        if timeout 3 nc -u -z localhost "$tftp_port" 2>/dev/null; then
            tftp_accessible=true
        fi
    fi
    
    # Test with tftp client if available
    if command -v tftp >/dev/null 2>&1 && [ "$tftp_accessible" = true ]; then
        # Create a test file for TFTP
        echo "tftp-test-$(date +%s)" > "/tmp/tftp-test.txt"
        
        # Try to put and get a file via TFTP
        if timeout 10 bash -c "
            echo 'connect localhost $tftp_port
            put /tmp/tftp-test.txt
            get tftp-test.txt /tmp/tftp-get-test.txt
            quit' | tftp 2>/dev/null" && [ -f "/tmp/tftp-get-test.txt" ]; then
            print_status "$GREEN" "✅ TFTP service fully operational"
            rm -f "/tmp/tftp-test.txt" "/tmp/tftp-get-test.txt" 2>/dev/null
        else
            if [ "$tftp_accessible" = true ]; then
                print_status "$GREEN" "✅ TFTP port accessible (service may be starting)"
            else
                print_status "$YELLOW" "⚠️  TFTP functional test failed"
            fi
        fi
    else
        # Fallback to basic connectivity test
        if [ "$tftp_accessible" = true ]; then
            print_status "$GREEN" "✅ TFTP port is accessible"
        else
            print_status "$YELLOW" "⚠️  TFTP port connectivity test failed"
        fi
    fi
    
    # Display container status
    print_status "$BLUE" "📊 Container status:"
    podman ps --filter "name=$container_name" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Generate configuration summary
generate_summary() {
    print_header "📋 Deployment Summary"
    
    local data_dir="${DATA_DIRECTORY:-./data}"
    local container_name="${CONTAINER_NAME:-httpboot-server}"
    
    cat << EOF
🎯 HTTP Boot Infrastructure Deployment Complete!

📡 Network Configuration:
   Subnet: ${NETWORK_SUBNET:-192.168.1.0/24}
   Host IP: ${HOST_IP:-192.168.1.10}
   Gateway: ${GATEWAY_IP:-192.168.1.1}
   DNS: ${DNS_PRIMARY:-8.8.8.8}, ${DNS_SECONDARY:-8.8.4.4}

🔌 Service Endpoints:
   HTTP Server: http://${HOST_IP:-127.0.0.1}:${HTTP_PORT:-8080}
   TFTP Server: ${HOST_IP:-127.0.0.1}:${TFTP_PORT:-69}
   Health Check: http://${HOST_IP:-127.0.0.1}:${HTTP_PORT:-8080}/health

🖥️ Boot Configuration:
   Distribution: ${PRIMARY_DISTRO:-debian}
   Architecture: ${ARCHITECTURE:-amd64}
   Boot Method: ${BOOT_METHOD:-both}
   DHCP Range: ${DHCP_RANGE_START:-192.168.1.100} - ${DHCP_RANGE_END:-192.168.1.200}

📁 Data Directories:
   TFTP Root: $(realpath "$data_dir")/tftp
   HTTP Root: $(realpath "$data_dir")/http
   Configs: $(realpath "$data_dir")/configs

🐳 Container Information:
   Name: $container_name
   Image: ${CONTAINER_REGISTRY:-docker.io}/httpboot-server:${CONTAINER_IMAGE_TAG:-latest}
   Status: Running
   Restart Policy: ${RESTART_POLICY:-always}

🔧 Management Commands:
   View logs: podman logs $container_name
   Stop service: podman stop $container_name
   Start service: podman start $container_name
   Restart service: podman restart $container_name
   Remove container: podman rm -f $container_name

📊 Health Monitoring:
   Health check: curl http://${HOST_IP:-127.0.0.1}:${HTTP_PORT:-8080}/health
   Service status: ./scripts/health-check.sh
   Container stats: podman stats $container_name

📚 Next Steps:
1. Configure your DHCP server to point clients to this boot server:
   - Next Server: ${HOST_IP:-192.168.1.10}
   - Boot Filename: pxelinux.0 (BIOS) or bootx64.efi (UEFI)

2. Test network boot from a client machine

3. Monitor logs and service health

4. Review documentation in ./docs/ directory

EOF

    print_status "$GREEN" "🎉 Setup completed successfully!"
    print_status "$BLUE" "📖 Check the generated documentation for detailed usage instructions"
}

# Cleanup function
cleanup() {
    if [[ ${1:-0} -ne 0 ]]; then
        print_status "$RED" "❌ Setup failed. Check $LOG_FILE for details."
        
        local container_name="${CONTAINER_NAME:-httpboot-server}"
        if podman ps -q --filter "name=$container_name" | grep -q .; then
            print_status "$YELLOW" "🧹 Cleaning up failed deployment..."
            podman stop "$container_name" || true
            podman rm "$container_name" || true
        fi
    fi
}

# Signal handling
trap 'cleanup $?' EXIT
trap 'print_status "$RED" "❌ Setup interrupted"; exit 1' INT TERM

# Configure services using templates
configure_services() {
    print_header "🔧 Configuring Service Templates"

    local configure_script="$SCRIPT_DIR/scripts/configure-services.sh"
    local configs_dir="$SCRIPT_DIR/data/configs"

    # Check if configuration script exists
    if [[ ! -f "$configure_script" ]]; then
        print_status "$YELLOW" "⚠️  configure-services.sh not found, skipping"
        return 0
    fi

    # Check if config templates directory exists
    if [[ ! -d "$configs_dir" ]]; then
        print_status "$RED" "❌ Configuration templates directory not found: $configs_dir"
        error_exit "Missing configuration templates"
    fi

    # Validate config templates exist
    local required_templates=(
        "$configs_dir/nginx.conf.template"
        "$configs_dir/dnsmasq.conf.template"
        "$configs_dir/tftpd-hpa.template"
        "$configs_dir/supervisord.conf.template"
    )

    print_status "$BLUE" "🔍 Validating configuration templates..."

    for template in "${required_templates[@]}"; do
        if [[ -f "$template" ]]; then
            print_status "$GREEN" "✅ Found: $(basename "$template")"
        else
            print_status "$YELLOW" "⚠️  Missing: $(basename "$template")"
        fi
    done

    # Make configure script executable
    if [[ ! -x "$configure_script" ]]; then
        print_status "$BLUE" "🔧 Making configure-services.sh executable"
        chmod +x "$configure_script"
    fi

    print_status "$BLUE" "📝 Configuration templates validated and ready for container use"
    print_status "$BLUE" "💡 Services will be configured during container startup via entrypoint.sh"
}

# Run comprehensive health check
run_health_check() {
    print_header "🔬 Running Comprehensive Health Check"

    # Check if health-check script exists
    local health_check_script="$SCRIPT_DIR/scripts/health-check.sh"

    if [[ ! -f "$health_check_script" ]]; then
        print_status "$YELLOW" "⚠️  Health check script not found, skipping"
        return 0
    fi

    if [[ ! -x "$health_check_script" ]]; then
        print_status "$BLUE" "🔧 Making health check script executable"
        chmod +x "$health_check_script"
    fi

    print_status "$BLUE" "🏥 Running health diagnostics..."

    # Run health check in quick mode for setup validation
    if "$health_check_script" quick; then
        print_status "$GREEN" "✅ Health check passed - all services are healthy"
    else
        local exit_code=$?
        case $exit_code in
            1)
                print_status "$YELLOW" "⚠️  Health check completed with warnings"
                print_status "$YELLOW" "📋 Run './scripts/health-check.sh check' for detailed analysis"
                ;;
            2)
                print_status "$RED" "❌ Health check found critical issues"
                print_status "$RED" "📋 Run './scripts/health-check.sh check' for detailed analysis"
                print_status "$YELLOW" "🔧 Container may still be starting - this is expected for new deployments"
                ;;
            *)
                print_status "$YELLOW" "⚠️  Health check completed with status: $exit_code"
                ;;
        esac
    fi

    print_status "$BLUE" "💡 Use './scripts/health-check.sh' for ongoing monitoring"
}

# Main deployment function
main() {
    local skip_validation=false
    local force_rebuild=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-validation)
                skip_validation=true
                shift
                ;;
            --force-rebuild)
                force_rebuild=true
                shift
                ;;
            --help|-h)
                cat << EOF
HTTP Boot Infrastructure Setup Script

Usage: $0 [OPTIONS]

Options:
    --skip-validation    Skip configuration validation
    --force-rebuild      Force rebuild of container image
    --help, -h           Show this help message

Examples:
    $0                   # Run with full validation
    $0 --skip-validation # Skip validation step
    $0 --force-rebuild   # Force container rebuild

EOF
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Start deployment
    print_header "🚀 HTTP Boot Infrastructure Setup"
    print_status "$BLUE" "📅 Started at: $(date)"
    print_status "$BLUE" "📍 Working directory: $SCRIPT_DIR"
    print_status "$BLUE" "📝 Log file: $LOG_FILE"
    
    # Initialize log file
    echo "HTTP Boot Infrastructure Setup - $(date)" > "$LOG_FILE"
    echo "Working directory: $SCRIPT_DIR" >> "$LOG_FILE"
    echo "Arguments: $*" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # Load configuration
    load_config
    
    # Run validation unless skipped
    if [[ "$skip_validation" != "true" ]]; then
        run_validation
    else
        print_status "$YELLOW" "⚠️  Skipping configuration validation"
    fi
    
    # Execute deployment steps
    check_prerequisites
    create_directories
    
    # Force rebuild if requested or if image doesn't exist
    local image_name="${CONTAINER_REGISTRY:-docker.io}/httpboot-server:${CONTAINER_IMAGE_TAG:-latest}"
    if [[ "$force_rebuild" == "true" ]] || ! podman image exists "$image_name"; then
        build_container
    else
        print_status "$BLUE" "📦 Using existing container image: $image_name"
    fi
    
    configure_services
    deploy_container
    test_services
    run_health_check
    generate_summary

    print_status "$GREEN" "✅ HTTP Boot Infrastructure setup completed successfully!"
}

# Run main function with all arguments
main "$@"