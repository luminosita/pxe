#!/bin/bash

# HTTP Boot Infrastructure - Configuration Backup Utility
# ========================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DESTINATION:-$PROJECT_DIR/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
COMPRESSION="${BACKUP_COMPRESSION:-gzip}"
CONTAINER_NAME="${CONTAINER_NAME:-httpboot-server}"

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

# Create backup directory
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        print_status "$GREEN" "✅ Created backup directory: $BACKUP_DIR"
    fi
}

# Generate backup filename
generate_backup_filename() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local hostname=$(hostname -s)
    
    case "$COMPRESSION" in
        "gzip") echo "httpboot_backup_${hostname}_${timestamp}.tar.gz" ;;
        "bzip2") echo "httpboot_backup_${hostname}_${timestamp}.tar.bz2" ;;
        "xz") echo "httpboot_backup_${hostname}_${timestamp}.tar.xz" ;;
        "none") echo "httpboot_backup_${hostname}_${timestamp}.tar" ;;
        *) echo "httpboot_backup_${hostname}_${timestamp}.tar.gz" ;;
    esac
}

# Create configuration backup
backup_configuration() {
    print_header "💾 Creating Configuration Backup"
    
    local backup_file="$BACKUP_DIR/$(generate_backup_filename)"
    local temp_dir=$(mktemp -d)
    local backup_name="httpboot_backup_$(date '+%Y%m%d_%H%M%S')"
    
    print_status "$BLUE" "📦 Preparing backup: $(basename "$backup_file")"
    
    # Create backup structure
    mkdir -p "$temp_dir/$backup_name"
    
    # Copy configuration files
    local config_files=(
        ".env"
        ".env.example"
        "validate-config.sh"
        "setup.sh"
        "docker-compose.yml"
        "Dockerfile"
    )
    
    print_status "$BLUE" "📋 Backing up configuration files..."
    for file in "${config_files[@]}"; do
        if [[ -f "$PROJECT_DIR/$file" ]]; then
            cp "$PROJECT_DIR/$file" "$temp_dir/$backup_name/"
            print_status "$GREEN" "  ✅ $file"
        else
            print_status "$YELLOW" "  ⚠️  $file (not found)"
        fi
    done
    
    # Copy scripts directory
    if [[ -d "$PROJECT_DIR/scripts" ]]; then
        cp -r "$PROJECT_DIR/scripts" "$temp_dir/$backup_name/"
        print_status "$GREEN" "  ✅ scripts/"
    fi
    
    # Copy docs directory
    if [[ -d "$PROJECT_DIR/docs" ]]; then
        cp -r "$PROJECT_DIR/docs" "$temp_dir/$backup_name/"
        print_status "$GREEN" "  ✅ docs/"
    fi
    
    # Copy data configurations (but not large boot files)
    if [[ -d "$PROJECT_DIR/data/configs" ]]; then
        mkdir -p "$temp_dir/$backup_name/data"
        cp -r "$PROJECT_DIR/data/configs" "$temp_dir/$backup_name/data/"
        print_status "$GREEN" "  ✅ data/configs/"
    fi
    
    # Create backup metadata
    create_backup_metadata "$temp_dir/$backup_name"
    
    # Create compressed archive
    print_status "$BLUE" "🗜️ Creating compressed archive..."
    cd "$temp_dir"
    
    case "$COMPRESSION" in
        "gzip")
            tar -czf "$backup_file" "$backup_name"
            ;;
        "bzip2")
            tar -cjf "$backup_file" "$backup_name"
            ;;
        "xz")
            tar -cJf "$backup_file" "$backup_name"
            ;;
        "none")
            tar -cf "$backup_file" "$backup_name"
            ;;
        *)
            tar -czf "$backup_file" "$backup_name"
            ;;
    esac
    
    # Cleanup temp directory
    rm -rf "$temp_dir"
    
    if [[ -f "$backup_file" ]]; then
        local backup_size=$(du -sh "$backup_file" | cut -f1)
        print_status "$GREEN" "✅ Backup created successfully: $(basename "$backup_file") ($backup_size)"
        echo "$backup_file"
    else
        print_status "$RED" "❌ Failed to create backup"
        return 1
    fi
}

# Create backup metadata
create_backup_metadata() {
    local backup_dir="$1"
    local metadata_file="$backup_dir/backup_metadata.txt"
    
    cat > "$metadata_file" << EOF
HTTP Boot Infrastructure Backup Metadata
========================================

Backup Information:
  Timestamp: $(date)
  Hostname: $(hostname)
  User: $(whoami)
  Backup Script Version: 1.0
  Compression: $COMPRESSION

System Information:
  Operating System: $(uname -s)
  Kernel Version: $(uname -r)
  Architecture: $(uname -m)

Container Information:
EOF
    
    # Add container information if available
    if command -v podman >/dev/null 2>&1; then
        echo "  Podman Version: $(podman --version)" >> "$metadata_file"
        
        if podman ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
            echo "  Container Status: Running" >> "$metadata_file"
            echo "  Container ID: $(podman ps -q --filter "name=$CONTAINER_NAME")" >> "$metadata_file"
            echo "  Container Image: $(podman ps --filter "name=$CONTAINER_NAME" --format "{{.Image}}")" >> "$metadata_file"
        else
            echo "  Container Status: Not Running" >> "$metadata_file"
        fi
    fi
    
    # Add configuration summary
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        echo "" >> "$metadata_file"
        echo "Configuration Summary:" >> "$metadata_file"
        grep -E "^[A-Z_]+=" "$PROJECT_DIR/.env" | while IFS='=' read -r key value; do
            # Mask sensitive values
            case "$key" in
                *PASSWORD*|*SECRET*|*KEY*)
                    echo "  $key=***MASKED***" >> "$metadata_file"
                    ;;
                *)
                    echo "  $key=$value" >> "$metadata_file"
                    ;;
            esac
        done
    fi
    
    # Add file checksums
    echo "" >> "$metadata_file"
    echo "File Checksums (SHA256):" >> "$metadata_file"
    find "$backup_dir" -type f ! -name "backup_metadata.txt" -exec sha256sum {} \; | \
    sed "s|$backup_dir/||" >> "$metadata_file"
}

# Export container configuration
export_container_config() {
    print_header "🐳 Exporting Container Configuration"
    
    if ! command -v podman >/dev/null 2>&1; then
        print_status "$YELLOW" "⚠️  Podman not available - skipping container export"
        return 0
    fi
    
    local export_dir="$BACKUP_DIR/container_exports"
    mkdir -p "$export_dir"
    
    # Check if container exists
    if ! podman ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        print_status "$YELLOW" "⚠️  Container '$CONTAINER_NAME' not found"
        return 0
    fi
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local export_file="$export_dir/${CONTAINER_NAME}_${timestamp}.tar"
    
    print_status "$BLUE" "📦 Exporting container: $CONTAINER_NAME"
    
    if podman export "$CONTAINER_NAME" -o "$export_file"; then
        local export_size=$(du -sh "$export_file" | cut -f1)
        print_status "$GREEN" "✅ Container exported: $(basename "$export_file") ($export_size)"
        
        # Compress the export
        print_status "$BLUE" "🗜️ Compressing container export..."
        gzip "$export_file"
        
        local compressed_size=$(du -sh "$export_file.gz" | cut -f1)
        print_status "$GREEN" "✅ Container compressed: $(basename "$export_file.gz") ($compressed_size)"
    else
        print_status "$RED" "❌ Failed to export container"
        return 1
    fi
}

# Backup data directory (selective)
backup_data_selective() {
    print_header "📁 Creating Selective Data Backup"
    
    local data_dir="${DATA_DIRECTORY:-$PROJECT_DIR/data}"
    
    if [[ ! -d "$data_dir" ]]; then
        print_status "$YELLOW" "⚠️  Data directory not found: $data_dir"
        return 0
    fi
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local data_backup_file="$BACKUP_DIR/httpboot_data_${timestamp}.tar.gz"
    
    print_status "$BLUE" "📦 Creating selective data backup..."
    
    # Create temporary exclusion list
    local temp_exclude=$(mktemp)
    cat > "$temp_exclude" << 'EOF'
*.iso
*.img
*.tar.gz
*.deb
*.rpm
netboot.tar.gz
linux-*
initrd-*
vmlinuz-*
EOF
    
    # Create data backup excluding large files
    if tar --exclude-from="$temp_exclude" \
           -czf "$data_backup_file" \
           -C "$(dirname "$data_dir")" \
           "$(basename "$data_dir")"; then
        local backup_size=$(du -sh "$data_backup_file" | cut -f1)
        print_status "$GREEN" "✅ Data backup created: $(basename "$data_backup_file") ($backup_size)"
    else
        print_status "$RED" "❌ Failed to create data backup"
        rm -f "$temp_exclude"
        return 1
    fi
    
    # Cleanup
    rm -f "$temp_exclude"
}

# Cleanup old backups
cleanup_old_backups() {
    print_header "🧹 Cleaning Up Old Backups"
    
    if [[ "$BACKUP_RETENTION_DAYS" -eq 0 ]]; then
        print_status "$BLUE" "📝 Backup retention disabled (BACKUP_RETENTION_DAYS=0)"
        return 0
    fi
    
    print_status "$BLUE" "🗑️ Removing backups older than $BACKUP_RETENTION_DAYS days..."
    
    local deleted_count=0
    
    # Find and remove old backup files
    while IFS= read -r -d '' file; do
        local file_age_days=$(( ($(date +%s) - $(stat -c %Y "$file")) / 86400 ))
        
        if [[ $file_age_days -gt $BACKUP_RETENTION_DAYS ]]; then
            print_status "$YELLOW" "🗑️ Removing old backup: $(basename "$file") (${file_age_days} days old)"
            rm "$file"
            ((deleted_count++))
        fi
    done < <(find "$BACKUP_DIR" -name "httpboot_backup_*.tar*" -print0 2>/dev/null)
    
    # Cleanup old container exports
    if [[ -d "$BACKUP_DIR/container_exports" ]]; then
        while IFS= read -r -d '' file; do
            local file_age_days=$(( ($(date +%s) - $(stat -c %Y "$file")) / 86400 ))
            
            if [[ $file_age_days -gt $BACKUP_RETENTION_DAYS ]]; then
                print_status "$YELLOW" "🗑️ Removing old container export: $(basename "$file")"
                rm "$file"
                ((deleted_count++))
            fi
        done < <(find "$BACKUP_DIR/container_exports" -name "*.tar.gz" -print0 2>/dev/null)
    fi
    
    if [[ $deleted_count -gt 0 ]]; then
        print_status "$GREEN" "✅ Cleaned up $deleted_count old backup files"
    else
        print_status "$BLUE" "📋 No old backups to clean up"
    fi
}

# Restore configuration from backup
restore_configuration() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        print_status "$RED" "❌ Backup file not found: $backup_file"
        return 1
    fi
    
    print_header "🔄 Restoring Configuration from Backup"
    print_status "$BLUE" "📦 Restoring from: $(basename "$backup_file")"
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    
    # Extract backup
    print_status "$BLUE" "📂 Extracting backup archive..."
    cd "$temp_dir"
    
    case "$backup_file" in
        *.tar.gz) tar -xzf "$backup_file" ;;
        *.tar.bz2) tar -xjf "$backup_file" ;;
        *.tar.xz) tar -xJf "$backup_file" ;;
        *.tar) tar -xf "$backup_file" ;;
        *)
            print_status "$RED" "❌ Unsupported backup format"
            rm -rf "$temp_dir"
            return 1
            ;;
    esac
    
    # Find backup directory
    local backup_content_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "httpboot_backup_*" | head -1)
    
    if [[ -z "$backup_content_dir" ]]; then
        print_status "$RED" "❌ Invalid backup format - no backup directory found"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Confirm restore
    print_status "$YELLOW" "⚠️  This will overwrite existing configuration files."
    read -p "Continue with restore? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "$BLUE" "📋 Restore cancelled"
        rm -rf "$temp_dir"
        return 0
    fi
    
    # Restore files
    print_status "$BLUE" "🔄 Restoring configuration files..."
    
    # Copy files back to project directory
    if cp -r "$backup_content_dir"/* "$PROJECT_DIR/"; then
        print_status "$GREEN" "✅ Configuration restored successfully"
        
        # Display metadata if available
        if [[ -f "$PROJECT_DIR/backup_metadata.txt" ]]; then
            print_status "$BLUE" "📋 Backup metadata:"
            head -20 "$PROJECT_DIR/backup_metadata.txt"
            rm "$PROJECT_DIR/backup_metadata.txt"
        fi
    else
        print_status "$RED" "❌ Failed to restore configuration"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    print_status "$GREEN" "✅ Restore completed successfully"
    print_status "$YELLOW" "⚠️  Please review configuration and restart services if needed"
}

# List available backups
list_backups() {
    print_header "📋 Available Backups"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_status "$YELLOW" "⚠️  No backup directory found: $BACKUP_DIR"
        return 0
    fi
    
    local backup_files=()
    while IFS= read -r -d '' file; do
        backup_files+=("$file")
    done < <(find "$BACKUP_DIR" -name "httpboot_backup_*.tar*" -print0 2>/dev/null | sort -z)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        print_status "$YELLOW" "⚠️  No backup files found"
        return 0
    fi
    
    printf "%-40s %-10s %-20s\n" "Backup File" "Size" "Date"
    printf "%-40s %-10s %-20s\n" "$(printf '%.40s' "----------------------------------------")" "----------" "--------------------"
    
    for backup_file in "${backup_files[@]}"; do
        local size=$(du -sh "$backup_file" | cut -f1)
        local date=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
        printf "%-40s %-10s %-20s\n" "$(basename "$backup_file")" "$size" "$date"
    done
}

# Show usage information
show_usage() {
    cat << EOF
HTTP Boot Infrastructure - Configuration Backup Utility

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    backup              Create a configuration backup (default)
    backup-data         Create a selective data backup
    export-container    Export container configuration
    restore BACKUP_FILE Restore configuration from backup
    list               List available backups
    cleanup            Remove old backups
    help               Show this help message

Options:
    --compression TYPE  Compression method (gzip, bzip2, xz, none)
    --retention DAYS    Backup retention period in days
    --backup-dir DIR    Custom backup directory

Environment Variables:
    BACKUP_DESTINATION      Backup directory (default: ./backups)
    BACKUP_RETENTION_DAYS   Retention period in days (default: 7)
    BACKUP_COMPRESSION      Compression method (default: gzip)
    CONTAINER_NAME          Container name (default: httpboot-server)

Examples:
    $0                                    # Create configuration backup
    $0 backup                            # Create configuration backup
    $0 backup-data                       # Create selective data backup
    $0 export-container                  # Export container
    $0 restore backups/httpboot_backup_*.tar.gz
    $0 list                              # List available backups
    $0 cleanup                           # Remove old backups
    $0 --compression xz backup           # Use XZ compression

EOF
}

# Main function
main() {
    local command="backup"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            backup|backup-data|export-container|restore|list|cleanup|help)
                command="$1"
                shift
                ;;
            --compression)
                COMPRESSION="$2"
                shift 2
                ;;
            --retention)
                BACKUP_RETENTION_DAYS="$2"
                shift 2
                ;;
            --backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            *)
                if [[ "$command" == "restore" && -f "$1" ]]; then
                    restore_configuration "$1"
                    exit $?
                else
                    print_status "$RED" "❌ Unknown option: $1"
                    show_usage
                    exit 1
                fi
                ;;
        esac
    done
    
    # Create backup directory
    create_backup_dir
    
    # Execute command
    case "$command" in
        "backup")
            backup_configuration
            cleanup_old_backups
            ;;
        "backup-data")
            backup_data_selective
            ;;
        "export-container")
            export_container_config
            ;;
        "restore")
            print_status "$RED" "❌ Please specify backup file to restore"
            show_usage
            exit 1
            ;;
        "list")
            list_backups
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "help")
            show_usage
            ;;
        *)
            print_status "$RED" "❌ Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"