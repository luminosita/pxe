#!/bin/bash

# HTTP Boot Infrastructure - Health Check and Monitoring Script
# =============================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables from .env if available
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

CONTAINER_NAME="${CONTAINER_NAME:-httpboot-server}"
HTTP_PORT="${HTTP_PORT:-8080}"
TFTP_PORT="${TFTP_PORT:-6969}"
HOST_IP="${HOST_IP:-127.0.0.1}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"
LOG_FILE="${LOG_FILE:-$PROJECT_DIR/health-check.log}"

# Health check status
OVERALL_STATUS="HEALTHY"
ISSUES_FOUND=()
WARNINGS_FOUND=()

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

# Log function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Add issue
add_issue() {
    ISSUES_FOUND+=("$1")
    OVERALL_STATUS="UNHEALTHY"
    log_message "ERROR" "$1"
}

# Add warning
add_warning() {
    WARNINGS_FOUND+=("$1")
    if [[ "$OVERALL_STATUS" == "HEALTHY" ]]; then
        OVERALL_STATUS="WARNING"
    fi
    log_message "WARN" "$1"
}

# Check container status
check_container_status() {
    print_header "🐳 Container Health Check"
    
    if ! command -v podman >/dev/null 2>&1; then
        add_issue "Podman is not installed or not available"
        return 1
    fi
    
    # Check if container exists
    if ! podman ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        add_issue "Container '$CONTAINER_NAME' does not exist"
        return 1
    fi
    
    # Check if container is running
    if ! podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        add_issue "Container '$CONTAINER_NAME' is not running"
        
        # Show container status
        local status=$(podman ps -a --filter "name=$CONTAINER_NAME" --format "{{.Status}}")
        print_status "$RED" "❌ Container status: $status"
        
        # Show recent logs
        print_status "$YELLOW" "📋 Recent container logs:"
        podman logs --tail 10 "$CONTAINER_NAME" 2>/dev/null || true
        
        return 1
    fi
    
    print_status "$GREEN" "✅ Container is running"
    
    # Get container details
    local container_id=$(podman ps -q --filter "name=$CONTAINER_NAME")
    local image_name=$(podman ps --filter "name=$CONTAINER_NAME" --format "{{.Image}}")
    local uptime=$(podman ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}")
    
    print_status "$BLUE" "📊 Container details:"
    print_status "$BLUE" "   ID: $container_id"
    print_status "$BLUE" "   Image: $image_name"
    print_status "$BLUE" "   Uptime: $uptime"
    
    # Check container health (if health check is defined)
    local health_status=$(podman inspect "$CONTAINER_NAME" --format "{{.State.Health.Status}}" 2>/dev/null || echo "unknown")
    if [[ "$health_status" != "unknown" ]]; then
        case "$health_status" in
            "healthy")
                print_status "$GREEN" "✅ Container health check: $health_status"
                ;;
            "unhealthy")
                add_issue "Container health check failed: $health_status"
                ;;
            "starting")
                add_warning "Container health check still starting"
                ;;
            *)
                add_warning "Container health check status unknown: $health_status"
                ;;
        esac
    fi
    
    return 0
}

# Check HTTP service
check_http_service() {
    print_header "🌐 HTTP Service Health Check"

    # Use localhost for local health checks, regardless of configured HOST_IP
    local local_ip="127.0.0.1"
    local http_url="http://$local_ip:$HTTP_PORT"
    local health_url="$http_url/health"

    print_status "$BLUE" "🔍 Testing HTTP service at: $http_url"
    
    # Test health endpoint
    if command -v curl >/dev/null 2>&1; then
        local http_response=$(curl -s -w "%{http_code}" -o /dev/null --connect-timeout 10 "$health_url" 2>/dev/null || echo "000")
        
        case "$http_response" in
            "200")
                print_status "$GREEN" "✅ HTTP health endpoint responding (200 OK)"
                ;;
            "000")
                add_issue "HTTP service not responding - connection failed"
                ;;
            *)
                add_issue "HTTP health endpoint returned unexpected code: $http_response"
                ;;
        esac
    else
        add_warning "curl not available - cannot test HTTP service"
    fi
    
    # Test main HTTP endpoint
    if command -v curl >/dev/null 2>&1; then
        local main_response=$(curl -s -w "%{http_code}" -o /dev/null --connect-timeout 10 "$http_url" 2>/dev/null || echo "000")
        
        case "$main_response" in
            "200"|"301"|"302")
                print_status "$GREEN" "✅ HTTP main endpoint accessible ($main_response)"
                ;;
            "000")
                add_issue "HTTP main endpoint not accessible - connection failed"
                ;;
            *)
                add_warning "HTTP main endpoint returned code: $main_response"
                ;;
        esac
    fi
    
    # Check if port is listening (check container port mapping)
    local port_mapped=false
    if command -v podman >/dev/null 2>&1; then
        if podman port "$CONTAINER_NAME" 2>/dev/null | grep -q "$HTTP_PORT/tcp"; then
            print_status "$GREEN" "✅ HTTP port $HTTP_PORT is mapped from container"
            port_mapped=true
        fi
    fi

    if [[ "$port_mapped" != "true" ]]; then
        # Fallback to system port check
        if command -v ss >/dev/null 2>&1; then
            if ss -tulpn | grep -q ":$HTTP_PORT "; then
                print_status "$GREEN" "✅ HTTP port $HTTP_PORT is listening"
            else
                add_issue "HTTP port $HTTP_PORT is not accessible"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tulpn 2>/dev/null | grep -q ":$HTTP_PORT "; then
                print_status "$GREEN" "✅ HTTP port $HTTP_PORT is listening"
            else
                add_issue "HTTP port $HTTP_PORT is not accessible"
            fi
        fi
    fi
}

# Check TFTP service
check_tftp_service() {
    print_header "📁 TFTP Service Health Check"

    # Use localhost for local health checks
    local local_ip="127.0.0.1"
    print_status "$BLUE" "🔍 Testing TFTP service on port: $TFTP_PORT"
    
    # Check if TFTP port is listening (check container port mapping)
    local tftp_port_mapped=false
    if command -v podman >/dev/null 2>&1; then
        if podman port "$CONTAINER_NAME" 2>/dev/null | grep -q "$TFTP_PORT/udp"; then
            print_status "$GREEN" "✅ TFTP port $TFTP_PORT is mapped from container"
            tftp_port_mapped=true
        fi
    fi

    if [[ "$tftp_port_mapped" != "true" ]]; then
        # Fallback to system port check
        if command -v ss >/dev/null 2>&1; then
            if ss -tulpn | grep -q ":$TFTP_PORT "; then
                print_status "$GREEN" "✅ TFTP port $TFTP_PORT is listening"
            else
                add_issue "TFTP port $TFTP_PORT is not accessible"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tulpn 2>/dev/null | grep -q ":$TFTP_PORT "; then
                print_status "$GREEN" "✅ TFTP port $TFTP_PORT is listening"
            else
                add_issue "TFTP port $TFTP_PORT is not accessible"
            fi
        fi
    fi
    
    # Test TFTP connectivity using nc (if available)
    if command -v nc >/dev/null 2>&1; then
        if timeout 3 nc -u -z "$local_ip" "$TFTP_PORT" 2>/dev/null; then
            print_status "$GREEN" "✅ TFTP port is accessible"
        else
            add_warning "TFTP port accessibility test inconclusive"
        fi
    else
        add_warning "nc not available - cannot test TFTP connectivity"
    fi

    # Test TFTP service using tftp client (if available)
    if command -v tftp >/dev/null 2>&1; then
        local test_result=$(timeout 5 bash -c "echo 'get pxelinux.0 /dev/null' | tftp $local_ip $TFTP_PORT" 2>&1 || echo "failed")
        if [[ "$test_result" != *"failed"* ]] && [[ "$test_result" != *"timeout"* ]]; then
            print_status "$GREEN" "✅ TFTP service responds to requests"
        else
            add_warning "TFTP service test failed or pxelinux.0 not found"
        fi
    else
        print_status "$BLUE" "📝 tftp client not available - skipping service test"
    fi
}

# Check data directories
check_data_directories() {
    print_header "📂 Data Directory Health Check"
    
    local data_dir="${DATA_DIRECTORY:-$PROJECT_DIR/data}"
    local required_dirs=(
        "$data_dir/tftp"
        "$data_dir/http"
        "$data_dir/configs"
    )
    
    print_status "$BLUE" "🔍 Checking data directories in: $data_dir"
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "Unknown")
            local files=$(find "$dir" -type f | wc -l)
            print_status "$GREEN" "✅ $(basename "$dir"): $files files, $size"
        else
            add_issue "Required directory missing: $dir"
        fi
    done
    
    # Check for important boot files
    local important_files=(
        "$data_dir/tftp/pxelinux.0"
        "$data_dir/tftp/pxelinux.cfg/default"
    )
    
    print_status "$BLUE" "🔍 Checking important boot files:"
    
    for file in "${important_files[@]}"; do
        if [[ -f "$file" ]]; then
            local size=$(du -sh "$file" 2>/dev/null | cut -f1 || echo "Unknown")
            print_status "$GREEN" "✅ $(basename "$file"): $size"
        else
            add_warning "Important boot file missing: $(basename "$file")"
        fi
    done
    
    # Check disk space
    local available_space=$(df -h "$data_dir" | awk 'NR==2 {print $4}' || echo "Unknown")
    local usage_percent=$(df -h "$data_dir" | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
    
    print_status "$BLUE" "💾 Disk space: $available_space available (${usage_percent}% used)"
    
    if [[ "$usage_percent" -gt 90 ]]; then
        add_issue "Disk space critically low: ${usage_percent}% used"
    elif [[ "$usage_percent" -gt 80 ]]; then
        add_warning "Disk space getting low: ${usage_percent}% used"
    fi
}

# Check boot images and PXE configuration
check_boot_images() {
    print_header "🚀 Boot Images and PXE Configuration Check"

    local data_dir="$PROJECT_DIR/data"
    local tftp_dir="$data_dir/tftp"
    local http_dir="$data_dir/http"

    print_status "$BLUE" "🔍 Validating PXE boot files..."

    # Critical PXE boot files
    local critical_files=(
        "$tftp_dir/pxelinux.0"
        "$tftp_dir/pxelinux.cfg/default"
    )

    # Check critical PXE files
    for file in "${critical_files[@]}"; do
        if [[ -e "$file" ]]; then
            if [[ -L "$file" ]]; then
                local target=$(readlink "$file")
                if [[ -e "$file" ]]; then
                    print_status "$GREEN" "✅ $(basename "$file") (symlink → $target)"
                else
                    add_issue "Broken symlink: $(basename "$file") → $target"
                fi
            else
                print_status "$GREEN" "✅ $(basename "$file")"
            fi
        else
            add_issue "Critical PXE file missing: $(basename "$file")"
        fi
    done

    # Check boot menu configuration
    local boot_menu="$tftp_dir/pxelinux.cfg/default"
    if [[ -f "$boot_menu" ]]; then
        print_status "$BLUE" "📋 Checking boot menu configuration..."

        # Check if menu has content
        if [[ -s "$boot_menu" ]]; then
            local menu_lines=$(wc -l < "$boot_menu" 2>/dev/null || echo "0")
            print_status "$GREEN" "✅ Boot menu configured ($menu_lines lines)"

            # Check for common menu entries
            if grep -q "LABEL\|MENU LABEL" "$boot_menu" 2>/dev/null; then
                print_status "$GREEN" "✅ Boot menu contains boot options"
            else
                add_warning "Boot menu exists but may not contain boot options"
            fi
        else
            add_issue "Boot menu file is empty"
        fi
    else
        add_issue "Boot menu configuration file not found"
    fi

    # Check Debian installer files
    print_status "$BLUE" "🐧 Checking Debian installer files..."
    local debian_dir="$tftp_dir/debian-installer/amd64"
    local debian_files=(
        "$debian_dir/linux"
        "$debian_dir/initrd.gz"
        "$debian_dir/pxelinux.0"
    )

    for file in "${debian_files[@]}"; do
        if [[ -f "$file" ]]; then
            local size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "Unknown")
            print_status "$GREEN" "✅ $(basename "$file") ($size)"
        else
            add_warning "Debian installer file missing: $(basename "$file")"
        fi
    done

    # Check HTTP access to boot files
    print_status "$BLUE" "🌐 Checking HTTP access to boot files..."
    local http_base="http://${HOST_IP}:${HTTP_PORT}"

    # Test HTTP access to kernel and initrd
    local http_test_files=(
        "/boot/debian-installer/amd64/linux"
        "/boot/debian-installer/amd64/initrd.gz"
    )

    for file_path in "${http_test_files[@]}"; do
        local url="${http_base}${file_path}"
        if command -v curl >/dev/null 2>&1; then
            if curl -f -s -I "$url" >/dev/null 2>&1; then
                # Get file size from HTTP headers
                local http_size=$(curl -s -I "$url" | grep -i content-length | cut -d' ' -f2 | tr -d '\r\n' || echo "Unknown")
                if [[ "$http_size" != "Unknown" ]] && [[ "$http_size" -gt 0 ]]; then
                    local size_mb=$((http_size / 1024 / 1024))
                    print_status "$GREEN" "✅ HTTP: $(basename "$file_path") (${size_mb}MB)"
                else
                    print_status "$GREEN" "✅ HTTP: $(basename "$file_path")"
                fi
            else
                add_issue "HTTP access failed for: $(basename "$file_path")"
            fi
        else
            add_warning "curl not available for HTTP testing"
            break
        fi
    done

    # Check TFTP file structure
    print_status "$BLUE" "📁 Checking TFTP directory structure..."
    local required_dirs=(
        "$tftp_dir/pxelinux.cfg"
        "$tftp_dir/debian-installer"
        "$tftp_dir/debian-installer/amd64"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local file_count=$(find "$dir" -type f 2>/dev/null | wc -l || echo "0")
            print_status "$GREEN" "✅ $(basename "$dir")/ ($file_count files)"
        else
            add_warning "Directory missing: $(basename "$dir")/"
        fi
    done

    # Check HTTP symlinks
    print_status "$BLUE" "🔗 Checking HTTP symlinks..."
    local http_boot_dir="$http_dir/boot"
    if [[ -L "$http_boot_dir" ]]; then
        local target=$(readlink "$http_boot_dir")
        if [[ -e "$http_boot_dir" ]]; then
            print_status "$GREEN" "✅ HTTP boot symlink working → $target"
        else
            add_issue "Broken HTTP boot symlink → $target"
        fi
    elif [[ -d "$http_boot_dir" ]]; then
        print_status "$GREEN" "✅ HTTP boot directory exists"
    else
        add_issue "HTTP boot directory/symlink missing"
    fi

    # Summary of boot image status
    print_status "$BLUE" "📊 Boot Image Summary:"
    local total_tftp_files=$(find "$tftp_dir" -type f 2>/dev/null | wc -l || echo "0")
    local total_http_files=$(find "$http_dir" -type f 2>/dev/null | wc -l || echo "0")
    print_status "$BLUE" "   TFTP files: $total_tftp_files"
    print_status "$BLUE" "   HTTP files: $total_http_files"

    # Check if download script exists for troubleshooting
    local download_script="$PROJECT_DIR/scripts/download-images.sh"
    if [[ -x "$download_script" ]]; then
        print_status "$BLUE" "💡 To refresh boot images: ./scripts/download-images.sh"
    else
        add_warning "Download script not found or not executable"
    fi
}

# Check DHCP service (if applicable)
check_dhcp_service() {
    print_header "🔌 DHCP Service Check"

    # Note: This infrastructure typically relies on existing DHCP server
    # but we can check basic DHCP-related configuration

    print_status "$BLUE" "🔍 Checking DHCP configuration..."

    # Check if DHCP relay is enabled
    if [[ "${ENABLE_DHCP_RELAY:-false}" == "true" ]]; then
        print_status "$BLUE" "📡 DHCP relay is enabled"

        # Check if we can reach the DHCP range
        if [[ -n "${DHCP_RANGE_START:-}" ]] && [[ -n "${DHCP_RANGE_END:-}" ]]; then
            print_status "$GREEN" "✅ DHCP range configured: ${DHCP_RANGE_START} - ${DHCP_RANGE_END}"
        else
            add_warning "DHCP range not fully configured"
        fi

        # Test network connectivity to DHCP range
        if [[ -n "${DHCP_RANGE_START:-}" ]] && command -v ping >/dev/null 2>&1; then
            local gateway="${GATEWAY_IP:-192.168.1.1}"
            if ping -c 1 -W 3 "$gateway" >/dev/null 2>&1; then
                print_status "$GREEN" "✅ Gateway ($gateway) is reachable"
            else
                add_warning "Gateway ($gateway) is not reachable"
            fi
        fi
    else
        print_status "$BLUE" "📝 DHCP relay disabled - relying on external DHCP server"

        # Basic network configuration validation
        if [[ -n "${NETWORK_SUBNET:-}" ]]; then
            print_status "$GREEN" "✅ Network subnet configured: ${NETWORK_SUBNET}"
        else
            add_warning "Network subnet not configured"
        fi

        if [[ -n "${GATEWAY_IP:-}" ]]; then
            print_status "$GREEN" "✅ Gateway IP configured: ${GATEWAY_IP}"

            # Test gateway connectivity
            if command -v ping >/dev/null 2>&1; then
                if ping -c 1 -W 3 "${GATEWAY_IP}" >/dev/null 2>&1; then
                    print_status "$GREEN" "✅ Gateway is reachable"
                else
                    add_warning "Gateway (${GATEWAY_IP}) is not reachable"
                fi
            fi
        else
            add_warning "Gateway IP not configured"
        fi
    fi

    # Check DHCP configuration files if they exist in container
    if podman exec "$CONTAINER_NAME" ls /etc/dhcp/ >/dev/null 2>&1; then
        local dhcp_configs=$(podman exec "$CONTAINER_NAME" ls /etc/dhcp/ 2>/dev/null | wc -l)
        if [[ "$dhcp_configs" -gt 0 ]]; then
            print_status "$GREEN" "✅ DHCP configuration files present"
        fi
    fi

    # Check if DHCP service is running in container (if enabled)
    if podman exec "$CONTAINER_NAME" ps aux 2>/dev/null | grep -q dhcp; then
        print_status "$GREEN" "✅ DHCP service is running in container"
    else
        print_status "$BLUE" "📝 No DHCP service running in container (expected for external DHCP)"
    fi
}

# Check network connectivity
check_network_connectivity() {
    print_header "🌐 Network Connectivity Check"
    
    # Test internet connectivity
    print_status "$BLUE" "🔍 Testing internet connectivity..."
    
    local test_hosts=("8.8.8.8" "1.1.1.1")
    local connectivity_ok=false
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            print_status "$GREEN" "✅ Internet connectivity OK ($host)"
            connectivity_ok=true
            break
        fi
    done
    
    if [[ "$connectivity_ok" != "true" ]]; then
        add_warning "Internet connectivity may be limited"
    fi
    
    # Test DNS resolution
    print_status "$BLUE" "🔍 Testing DNS resolution..."
    
    local test_domains=("debian.org" "ubuntu.com")
    
    for domain in "${test_domains[@]}"; do
        if nslookup "$domain" >/dev/null 2>&1; then
            print_status "$GREEN" "✅ DNS resolution OK ($domain)"
            break
        fi
    done
    
    # Check network interfaces
    if command -v ip >/dev/null 2>&1; then
        print_status "$BLUE" "🔍 Network interfaces:"
        ip addr show | grep -E "inet.*scope global" | while read line; do
            print_status "$BLUE" "   $line"
        done
    fi
}

# Check log files
check_log_files() {
    print_header "📋 Log File Analysis"
    
    local log_sources=()
    
    # Container logs
    if podman ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
        log_sources+=("container:$CONTAINER_NAME")
    fi
    
    # Local log files
    local local_logs=(
        "$PROJECT_DIR/setup.log"
        "$LOG_FILE"
    )
    
    for log_file in "${local_logs[@]}"; do
        if [[ -f "$log_file" ]]; then
            log_sources+=("file:$log_file")
        fi
    done
    
    print_status "$BLUE" "🔍 Analyzing log sources..."
    
    for source in "${log_sources[@]}"; do
        local source_type="${source%:*}"
        local source_path="${source#*:}"
        
        case "$source_type" in
            "container")
                print_status "$BLUE" "📋 Container logs ($source_path):"
                local recent_logs=$(podman logs --tail 5 "$source_path" 2>/dev/null)
                
                # Check for error patterns
                local error_count=$(podman logs --since "1h" "$source_path" 2>/dev/null | grep -ci "error\|fail\|exception" || echo "0")
                local warning_count=$(podman logs --since "1h" "$source_path" 2>/dev/null | grep -ci "warn" || echo "0")
                
                if [[ "$error_count" -gt 0 ]]; then
                    add_warning "Found $error_count error(s) in container logs (last hour)"
                fi
                
                if [[ "$warning_count" -gt 5 ]]; then
                    add_warning "Found $warning_count warning(s) in container logs (last hour)"
                fi
                
                # Show recent logs
                if [[ -n "$recent_logs" ]]; then
                    echo "$recent_logs" | tail -3 | while read line; do
                        print_status "$CYAN" "   $line"
                    done
                fi
                ;;
                
            "file")
                if [[ -f "$source_path" ]]; then
                    local file_size=$(du -sh "$source_path" | cut -f1)
                    print_status "$BLUE" "📄 Log file: $(basename "$source_path") ($file_size)"
                    
                    # Check for recent errors
                    local recent_errors=$(tail -100 "$source_path" 2>/dev/null | grep -i "error\|fail" | tail -3)
                    if [[ -n "$recent_errors" ]]; then
                        print_status "$YELLOW" "⚠️  Recent errors found:"
                        echo "$recent_errors" | while read line; do
                            print_status "$YELLOW" "   $line"
                        done
                    fi
                fi
                ;;
        esac
    done
}

# Check system resources
check_system_resources() {
    print_header "⚡ System Resource Check"
    
    # CPU usage
    if command -v top >/dev/null 2>&1; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "Unknown")
        print_status "$BLUE" "🖥️ CPU usage: ${cpu_usage}%"
        
        if command -v bc >/dev/null 2>&1 && [[ "$cpu_usage" != "Unknown" ]]; then
            if (( $(echo "$cpu_usage > 80" | bc -l) )); then
                add_warning "High CPU usage: ${cpu_usage}%"
            fi
        fi
    fi
    
    # Memory usage
    if [[ -f /proc/meminfo ]]; then
        local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        local mem_used=$((mem_total - mem_available))
        local mem_percent=$((mem_used * 100 / mem_total))
        
        print_status "$BLUE" "🧠 Memory usage: ${mem_percent}%"
        
        if [[ "$mem_percent" -gt 90 ]]; then
            add_issue "Critical memory usage: ${mem_percent}%"
        elif [[ "$mem_percent" -gt 80 ]]; then
            add_warning "High memory usage: ${mem_percent}%"
        fi
    fi
    
    # Container resource usage (if available)
    if podman ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
        if command -v podman >/dev/null 2>&1; then
            print_status "$BLUE" "🐳 Container resource usage:"
            podman stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$CONTAINER_NAME" 2>/dev/null || true
        fi
    fi
}

# Generate health report
generate_health_report() {
    print_header "📊 Health Check Summary"
    
    # Overall status
    case "$OVERALL_STATUS" in
        "HEALTHY")
            print_status "$GREEN" "✅ Overall Status: HEALTHY"
            ;;
        "WARNING")
            print_status "$YELLOW" "⚠️  Overall Status: WARNING"
            ;;
        "UNHEALTHY")
            print_status "$RED" "❌ Overall Status: UNHEALTHY"
            ;;
    esac
    
    # Issues found
    if [[ ${#ISSUES_FOUND[@]} -gt 0 ]]; then
        print_status "$RED" "❌ Issues Found (${#ISSUES_FOUND[@]}):"
        for issue in "${ISSUES_FOUND[@]}"; do
            print_status "$RED" "   • $issue"
        done
    fi
    
    # Warnings found
    if [[ ${#WARNINGS_FOUND[@]} -gt 0 ]]; then
        print_status "$YELLOW" "⚠️  Warnings (${#WARNINGS_FOUND[@]}):"
        for warning in "${WARNINGS_FOUND[@]}"; do
            print_status "$YELLOW" "   • $warning"
        done
    fi
    
    # Recommendations
    if [[ ${#ISSUES_FOUND[@]} -gt 0 || ${#WARNINGS_FOUND[@]} -gt 0 ]]; then
        print_header "🔧 Recommendations"
        
        if [[ ${#ISSUES_FOUND[@]} -gt 0 ]]; then
            print_status "$RED" "❗ Critical actions needed:"
            print_status "$RED" "   1. Check container logs: podman logs $CONTAINER_NAME"
            print_status "$RED" "   2. Restart services if needed: podman restart $CONTAINER_NAME"
            print_status "$RED" "   3. Verify network configuration in .env file"
        fi
        
        if [[ ${#WARNINGS_FOUND[@]} -gt 0 ]]; then
            print_status "$YELLOW" "📋 Suggested improvements:"
            print_status "$YELLOW" "   1. Monitor resource usage regularly"
            print_status "$YELLOW" "   2. Review log files for recurring issues"
            print_status "$YELLOW" "   3. Consider cleanup or optimization"
        fi
    fi
    
    # Log summary to file
    log_message "INFO" "Health check completed - Status: $OVERALL_STATUS, Issues: ${#ISSUES_FOUND[@]}, Warnings: ${#WARNINGS_FOUND[@]}"
}

# Continuous monitoring mode
continuous_monitoring() {
    print_header "🔄 Continuous Health Monitoring"
    print_status "$BLUE" "🕒 Monitoring interval: ${HEALTH_CHECK_INTERVAL}s"
    print_status "$BLUE" "📝 Log file: $LOG_FILE"
    print_status "$YELLOW" "Press Ctrl+C to stop monitoring"
    
    local check_count=0
    
    while true; do
        ((check_count++))
        
        echo ""
        print_status "$CYAN" "🔄 Health Check #$check_count - $(date)"
        
        # Reset status for this iteration
        OVERALL_STATUS="HEALTHY"
        ISSUES_FOUND=()
        WARNINGS_FOUND=()
        
        # Run abbreviated health checks
        check_container_status >/dev/null 2>&1 || true
        check_http_service >/dev/null 2>&1 || true
        check_tftp_service >/dev/null 2>&1 || true
        
        # Show brief status
        case "$OVERALL_STATUS" in
            "HEALTHY")
                print_status "$GREEN" "✅ Status: HEALTHY"
                ;;
            "WARNING")
                print_status "$YELLOW" "⚠️  Status: WARNING (${#WARNINGS_FOUND[@]} warnings)"
                ;;
            "UNHEALTHY")
                print_status "$RED" "❌ Status: UNHEALTHY (${#ISSUES_FOUND[@]} issues)"
                ;;
        esac
        
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

# Show usage
show_usage() {
    cat << EOF
HTTP Boot Infrastructure - Health Check Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    check              Run complete health check (default)
    quick              Run quick health check (essential services only)
    monitor            Continuous monitoring mode
    logs               Show recent log analysis only
    resources          Show system resource usage only
    help               Show this help message

Options:
    --container NAME   Container name to check (default: httpboot-server)
    --interval SECONDS Monitoring interval for continuous mode (default: 30)
    --log-file FILE    Log file path (default: ./health-check.log)

Environment Variables:
    CONTAINER_NAME         Container name (default: httpboot-server)
    HTTP_PORT             HTTP service port (default: 8080)
    TFTP_PORT             TFTP service port (default: 69)
    HOST_IP               Host IP address (default: 127.0.0.1)
    HEALTH_CHECK_INTERVAL Monitoring interval (default: 30)

Examples:
    $0                     # Run complete health check
    $0 quick              # Quick health check
    $0 monitor            # Continuous monitoring
    $0 --container my-server check
    $0 --interval 60 monitor

Exit Codes:
    0  - All checks passed (HEALTHY)
    1  - Warnings found (WARNING)
    2  - Critical issues found (UNHEALTHY)

EOF
}

# Main function
main() {
    local command="check"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            check|quick|monitor|logs|resources|help)
                command="$1"
                shift
                ;;
            --container)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            --interval)
                HEALTH_CHECK_INTERVAL="$2"
                shift 2
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            *)
                print_status "$RED" "❌ Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Initialize log file
    if [[ ! -f "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        touch "$LOG_FILE"
    fi
    
    # Execute command
    case "$command" in
        "check")
            print_header "🔍 HTTP Boot Infrastructure - Complete Health Check"
            check_container_status
            check_http_service
            check_tftp_service
            check_dhcp_service
            check_data_directories
            check_boot_images
            check_network_connectivity
            check_log_files
            check_system_resources
            generate_health_report
            ;;
        "quick")
            print_header "⚡ HTTP Boot Infrastructure - Quick Health Check"
            check_container_status
            check_http_service
            check_tftp_service
            check_boot_images
            generate_health_report
            ;;
        "monitor")
            continuous_monitoring
            ;;
        "logs")
            print_header "📋 Log File Analysis"
            check_log_files
            ;;
        "resources")
            print_header "⚡ System Resource Check"
            check_system_resources
            ;;
        "help")
            show_usage
            exit 0
            ;;
        *)
            print_status "$RED" "❌ Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
    
    # Exit with appropriate code
    case "$OVERALL_STATUS" in
        "HEALTHY") exit 0 ;;
        "WARNING") exit 1 ;;
        "UNHEALTHY") exit 2 ;;
    esac
}

# Handle interruption gracefully
trap 'print_status "$YELLOW" "🛑 Health check interrupted"; exit 0' INT TERM

# Run main function
main "$@"