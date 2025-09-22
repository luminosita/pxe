# HTTP Boot Infrastructure - Extending and Customization Guide

This guide covers how to extend the HTTP Boot Infrastructure with additional Linux distributions, custom boot options, and advanced features.

## 📋 Table of Contents

- [Adding New Linux Distributions](#adding-new-linux-distributions)
- [Custom Boot Options](#custom-boot-options)
- [Advanced Container Customization](#advanced-container-customization)
- [Integration with External Services](#integration-with-external-services)
- [Performance Optimization](#performance-optimization)
- [Security Enhancements](#security-enhancements)
- [Monitoring and Alerting](#monitoring-and-alerting)
- [Development and Testing](#development-and-testing)

## 🐧 Adding New Linux Distributions

### Supported Distribution Framework

The infrastructure is designed to easily support additional Linux distributions. Here's how to add them:

### Adding Rocky Linux

1. **Update environment configuration:**
   ```bash
   # Add to .env.example
   ROCKY_RELEASE=9.3                # 9.3, 9.2, 8.8
   ```

2. **Extend download script:**
   ```bash
   # Add to scripts/download-images.sh
   download_rocky() {
       print_header "📦 Downloading Rocky Linux $ROCKY_RELEASE ($ARCHITECTURE) Boot Files"
       
       local arch_dir
       case "$ARCHITECTURE" in
           "amd64"|"x86_64") arch_dir="x86_64" ;;
           "arm64"|"aarch64") arch_dir="aarch64" ;;
           *) 
               print_status "$RED" "❌ Unsupported architecture for Rocky Linux: $ARCHITECTURE"
               return 1
               ;;
       esac
       
       local base_url="https://download.rockylinux.org/pub/rocky/$ROCKY_RELEASE/BaseOS/$arch_dir/os"
       local boot_files=(
           "$base_url/images/pxeboot/vmlinuz:rocky-vmlinuz"
           "$base_url/images/pxeboot/initrd.img:rocky-initrd.img"
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
       
       create_rocky_pxe_config
   }
   
   create_rocky_pxe_config() {
       local config_file="$TFTP_DIR/pxelinux.cfg/rocky"
       
       cat > "$config_file" << EOF
   DEFAULT rocky-install
   
   LABEL rocky-install
       MENU LABEL Rocky Linux $ROCKY_RELEASE Installation
       KERNEL rocky-vmlinuz
       APPEND initrd=rocky-initrd.img inst.repo=https://download.rockylinux.org/pub/rocky/$ROCKY_RELEASE/BaseOS/x86_64/os/ inst.stage2=https://download.rockylinux.org/pub/rocky/$ROCKY_RELEASE/BaseOS/x86_64/os/
   EOF
       
       print_status "$GREEN" "✅ Created Rocky Linux PXE configuration"
   }
   ```

3. **Update main download function:**
   ```bash
   # In main() function, add:
   "rocky") download_rocky || success=false ;;
   ```

### Adding Alpine Linux

1. **Create Alpine download function:**
   ```bash
   download_alpine() {
       print_header "📦 Downloading Alpine Linux (Latest) Boot Files"
       
       local base_url="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/$ARCHITECTURE"
       local netboot_url="$base_url/netboot"
       
       # Download Alpine netboot files
       local alpine_files=(
           "$netboot_url/vmlinuz-lts:alpine-vmlinuz"
           "$netboot_url/initramfs-lts:alpine-initramfs"
           "$netboot_url/modloop-lts:alpine-modloop"
       )
       
       for file in "${alpine_files[@]}"; do
           local url="${file%:*}"
           local filename="${file#*:}"
           local output="$IMAGES_DIR/$filename"
           
           if download_with_retry "$url" "$output"; then
               ln -sf "$output" "$HTTP_DIR/images/" 2>/dev/null || true
               ln -sf "$output" "$TFTP_DIR/" 2>/dev/null || true
           fi
       done
       
       create_alpine_pxe_config
   }
   
   create_alpine_pxe_config() {
       local config_file="$TFTP_DIR/pxelinux.cfg/alpine"
       
       cat > "$config_file" << 'EOF'
   DEFAULT alpine-install
   
   LABEL alpine-install
       MENU LABEL Alpine Linux Installation
       KERNEL alpine-vmlinuz
       APPEND initrd=alpine-initramfs,alpine-modloop alpine_repo=https://dl-cdn.alpinelinux.org/alpine/latest-stable/main modloop=alpine-modloop
   
   LABEL alpine-rescue
       MENU LABEL Alpine Linux Rescue
       KERNEL alpine-vmlinuz
       APPEND initrd=alpine-initramfs rescue
   EOF
       
       print_status "$GREEN" "✅ Created Alpine Linux PXE configuration"
   }
   ```

### Adding Arch Linux

1. **Create Arch download function:**
   ```bash
   download_arch() {
       print_header "📦 Downloading Arch Linux Boot Files"
       
       # Arch uses ISO images, we need to extract boot files
       local iso_url="https://mirror.rackspace.com/archlinux/iso/latest"
       local iso_name=$(curl -s "$iso_url/" | grep -oP 'archlinux-\d{4}\.\d{2}\.\d{2}-x86_64\.iso' | head -1)
       
       if [[ -z "$iso_name" ]]; then
           print_status "$RED" "❌ Could not determine latest Arch ISO"
           return 1
       fi
       
       local iso_file="$IMAGES_DIR/$iso_name"
       
       if download_with_retry "$iso_url/$iso_name" "$iso_file"; then
           # Extract boot files from ISO
           extract_arch_boot_files "$iso_file"
       fi
   }
   
   extract_arch_boot_files() {
       local iso_file="$1"
       local mount_point="/tmp/arch_iso_$$"
       
       # Mount ISO and extract boot files
       sudo mkdir -p "$mount_point"
       sudo mount -o loop "$iso_file" "$mount_point"
       
       # Copy boot files
       cp "$mount_point/arch/boot/x86_64/vmlinuz-linux" "$TFTP_DIR/arch-vmlinuz"
       cp "$mount_point/arch/boot/x86_64/initramfs-linux.img" "$TFTP_DIR/arch-initramfs.img"
       
       # Copy to HTTP directory
       ln -sf "$TFTP_DIR/arch-vmlinuz" "$HTTP_DIR/images/"
       ln -sf "$TFTP_DIR/arch-initramfs.img" "$HTTP_DIR/images/"
       
       sudo umount "$mount_point"
       sudo rmdir "$mount_point"
       
       create_arch_pxe_config
   }
   
   create_arch_pxe_config() {
       local config_file="$TFTP_DIR/pxelinux.cfg/arch"
       
       cat > "$config_file" << 'EOF'
   DEFAULT arch-install
   
   LABEL arch-install
       MENU LABEL Arch Linux Installation
       KERNEL arch-vmlinuz
       APPEND initrd=arch-initramfs.img archiso_http_srv=http://192.168.1.10:8080/ archisobasedir=arch checksum verify
   EOF
       
       print_status "$GREEN" "✅ Created Arch Linux PXE configuration"
   }
   ```

### Custom Distribution Template

For adding any new distribution, follow this template:

```bash
# 1. Add environment variables to .env.example
CUSTOM_DISTRO_RELEASE=version

# 2. Create download function
download_custom_distro() {
    print_header "📦 Downloading Custom Distribution"
    
    # Set architecture mapping
    local arch_map
    case "$ARCHITECTURE" in
        "amd64") arch_map="x86_64" ;;
        "arm64") arch_map="aarch64" ;;
        *) arch_map="$ARCHITECTURE" ;;
    esac
    
    # Define download URLs
    local base_url="https://example.com/releases"
    local boot_files=(
        "$base_url/vmlinuz:custom-vmlinuz"
        "$base_url/initrd.img:custom-initrd.img"
    )
    
    # Download files
    for boot_file in "${boot_files[@]}"; do
        local url="${boot_file%:*}"
        local filename="${boot_file#*:}"
        local output="$IMAGES_DIR/$filename"
        
        if download_with_retry "$url" "$output"; then
            ln -sf "$output" "$HTTP_DIR/images/"
            ln -sf "$output" "$TFTP_DIR/"
        fi
    done
    
    # Create PXE configuration
    create_custom_distro_pxe_config
}

# 3. Create PXE configuration
create_custom_distro_pxe_config() {
    local config_file="$TFTP_DIR/pxelinux.cfg/custom"
    
    cat > "$config_file" << 'EOF'
DEFAULT custom-install

LABEL custom-install
    MENU LABEL Custom Distribution Installation
    KERNEL custom-vmlinuz
    APPEND initrd=custom-initrd.img custom-options

LABEL custom-rescue
    MENU LABEL Custom Distribution Rescue
    KERNEL custom-vmlinuz
    APPEND initrd=custom-initrd.img rescue
EOF
}

# 4. Add to main download logic
case "$PRIMARY_DISTRO" in
    "custom") download_custom_distro || success=false ;;
esac
```

## 🎛️ Custom Boot Options

### Adding Custom Operating Systems

#### Windows PE Boot (WinPE)

1. **Prepare WinPE files:**
   ```bash
   # Create WinPE directory
   mkdir -p data/tftp/winpe
   mkdir -p data/http/winpe
   
   # Copy WinPE files (you need to create these separately)
   cp winpe/bootmgr.exe data/tftp/winpe/
   cp winpe/boot.wim data/http/winpe/
   ```

2. **Add WinPE boot menu entry:**
   ```bash
   # Add to data/tftp/pxelinux.cfg/default
   cat >> data/tftp/pxelinux.cfg/default << 'EOF'
   
   LABEL winpe
       MENU LABEL Windows PE
       KERNEL memdisk
       APPEND initrd=winpe/winpe.iso iso raw
   EOF
   ```

#### FreeBSD Network Install

1. **Download FreeBSD boot files:**
   ```bash
   # Create FreeBSD download function
   download_freebsd() {
       local version="13.2"
       local base_url="https://download.freebsd.org/ftp/releases/amd64/$version-RELEASE"
       
       # Download boot files
       wget "$base_url/bootonly.iso" -O "$IMAGES_DIR/freebsd-$version-bootonly.iso"
       
       # Extract boot files if needed
       # (FreeBSD typically boots from ISO directly)
   }
   ```

2. **Add FreeBSD menu entry:**
   ```bash
   cat >> data/tftp/pxelinux.cfg/default << 'EOF'
   
   LABEL freebsd
       MENU LABEL FreeBSD 13.2 Installation
       KERNEL memdisk
       APPEND initrd=freebsd-13.2-bootonly.iso iso raw
   EOF
   ```

### Automated Installation Configurations

#### Debian Preseed

1. **Create preseed file:**
   ```bash
   cat > data/http/preseed/debian-auto.cfg << 'EOF'
   # Debian automatic installation preseed
   
   # Localization
   d-i debian-installer/locale string en_US
   d-i keyboard-configuration/xkb-keymap select us
   
   # Network configuration
   d-i netcfg/choose_interface select auto
   d-i netcfg/get_hostname string debian-auto
   d-i netcfg/get_domain string local
   
   # Mirror settings
   d-i mirror/country string manual
   d-i mirror/http/hostname string deb.debian.org
   d-i mirror/http/directory string /debian
   
   # Account setup
   d-i passwd/root-login boolean false
   d-i passwd/user-fullname string Auto User
   d-i passwd/username string autouser
   d-i passwd/user-password password autopass
   d-i passwd/user-password-again password autopass
   
   # Clock and time zone setup
   d-i clock-setup/utc boolean true
   d-i time/zone string UTC
   
   # Partitioning
   d-i partman-auto/method string regular
   d-i partman-auto/choose_recipe select atomic
   d-i partman/confirm boolean true
   d-i partman/confirm_nooverwrite boolean true
   
   # Package selection
   tasksel tasksel/first multiselect standard, ssh-server
   d-i pkgsel/upgrade select none
   
   # Boot loader installation
   d-i grub-installer/only_debian boolean true
   d-i grub-installer/bootdev string default
   
   # Finish up
   d-i finish-install/reboot_in_progress note
   EOF
   ```

2. **Add preseed boot option:**
   ```bash
   cat >> data/tftp/pxelinux.cfg/default << 'EOF'
   
   LABEL debian-auto
       MENU LABEL Debian Automatic Installation
       KERNEL debian-installer/amd64/linux
       APPEND initrd=debian-installer/amd64/initrd.gz url=http://192.168.1.10:8080/preseed/debian-auto.cfg auto=true priority=critical
   EOF
   ```

#### Ubuntu Autoinstall (Cloud-Init)

1. **Create autoinstall configuration:**
   ```bash
   mkdir -p data/http/autoinstall
   
   cat > data/http/autoinstall/ubuntu-auto.yaml << 'EOF'
   #cloud-config
   autoinstall:
     version: 1
     locale: en_US
     keyboard:
       layout: us
     network:
       network:
         version: 2
         ethernets:
           any:
             match:
               name: "e*"
             dhcp4: true
     storage:
       layout:
         name: direct
     identity:
       hostname: ubuntu-auto
       username: autouser
       password: '$6$exDY1mhS4KUYCE/2$zmn9ToZwTKLhCw.b4/b.ZRTIZM30JZ4QrOQ2aOXJ8yk96xpcCof0kxKwuX1kqLG/ygbJ1f8wxED22bTL4F46P0'
     ssh:
       install-server: true
       authorized-keys:
         - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... # Your SSH key
     packages:
       - openssh-server
       - curl
       - wget
     late-commands:
       - curtin in-target --target=/target -- systemctl enable ssh
   EOF
   ```

2. **Add autoinstall boot option:**
   ```bash
   cat >> data/tftp/pxelinux.cfg/default << 'EOF'
   
   LABEL ubuntu-auto
       MENU LABEL Ubuntu Automatic Installation
       KERNEL ubuntu-installer/amd64/linux
       APPEND initrd=ubuntu-installer/amd64/initrd.gz url=http://192.168.1.10:8080/autoinstall/ubuntu-auto.yaml autoinstall
   EOF
   ```

#### CentOS/RHEL Kickstart

1. **Create kickstart file:**
   ```bash
   cat > data/http/kickstart/centos-auto.ks << 'EOF'
   #version=RHEL9
   
   # Use network installation
   url --url="http://mirror.centos.org/centos/9-stream/BaseOS/x86_64/os/"
   
   # System language
   lang en_US.UTF-8
   
   # Keyboard layouts
   keyboard --vckeymap=us --xlayouts='us'
   
   # Network information
   network --bootproto=dhcp --device=link --activate
   network --hostname=centos-auto
   
   # Root password (password: autopass)
   rootpw --iscrypted $6$SALT$HASH
   
   # System timezone
   timezone UTC --isUtc
   
   # System bootloader configuration
   bootloader --location=mbr --boot-drive=sda
   
   # Partition clearing information
   clearpart --all --initlabel
   
   # Disk partitioning information
   autopart --type=lvm
   
   # Package selection
   %packages
   @^minimal-environment
   openssh-server
   %end
   
   # Enable services
   services --enabled=sshd
   
   # Reboot after installation
   reboot
   EOF
   ```

2. **Add kickstart boot option:**
   ```bash
   cat >> data/tftp/pxelinux.cfg/default << 'EOF'
   
   LABEL centos-auto
       MENU LABEL CentOS Automatic Installation
       KERNEL centos-vmlinuz
       APPEND initrd=centos-initrd.img inst.ks=http://192.168.1.10:8080/kickstart/centos-auto.ks
   EOF
   ```

### Custom Boot Menus

#### Hierarchical Menu System

1. **Create main menu:**
   ```bash
   cat > data/tftp/pxelinux.cfg/default << 'EOF'
   DEFAULT vesamenu.c32
   PROMPT 0
   TIMEOUT 300
   MENU TITLE HTTP Boot Infrastructure - Main Menu
   MENU BACKGROUND boot.jpg
   
   LABEL local
       MENU LABEL Boot from ^Local Disk
       MENU DEFAULT
       LOCALBOOT 0
   
   LABEL debian_menu
       MENU LABEL ^Debian Options
       CONFIG pxelinux.cfg/debian
   
   LABEL ubuntu_menu
       MENU LABEL ^Ubuntu Options
       CONFIG pxelinux.cfg/ubuntu
   
   LABEL tools_menu
       MENU LABEL ^Tools and Utilities
       CONFIG pxelinux.cfg/tools
   
   LABEL separator
       MENU SEPARATOR
   
   LABEL reboot
       MENU LABEL ^Reboot
       COM32 reboot.c32
   
   LABEL poweroff
       MENU LABEL ^Power Off
       COM32 poweroff.c32
   EOF
   ```

2. **Create submenu for Debian:**
   ```bash
   cat > data/tftp/pxelinux.cfg/debian << 'EOF'
   DEFAULT vesamenu.c32
   PROMPT 0
   TIMEOUT 300
   MENU TITLE Debian Installation Options
   MENU INCLUDE pxelinux.cfg/graphics.conf
   
   LABEL back
       MENU LABEL ^Back to Main Menu
       CONFIG pxelinux.cfg/default
   
   LABEL separator
       MENU SEPARATOR
   
   LABEL debian_install
       MENU LABEL Debian ^Standard Installation
       KERNEL debian-installer/amd64/linux
       APPEND initrd=debian-installer/amd64/initrd.gz
   
   LABEL debian_auto
       MENU LABEL Debian ^Automatic Installation
       KERNEL debian-installer/amd64/linux
       APPEND initrd=debian-installer/amd64/initrd.gz url=http://192.168.1.10:8080/preseed/debian-auto.cfg auto=true priority=critical
   
   LABEL debian_rescue
       MENU LABEL Debian ^Rescue Mode
       KERNEL debian-installer/amd64/linux
       APPEND initrd=debian-installer/amd64/initrd.gz rescue/enable=true
   
   LABEL debian_expert
       MENU LABEL Debian ^Expert Installation
       KERNEL debian-installer/amd64/linux
       APPEND initrd=debian-installer/amd64/initrd.gz priority=low
   EOF
   ```

#### Customizing Menu Appearance

1. **Create graphics configuration:**
   ```bash
   cat > data/tftp/pxelinux.cfg/graphics.conf << 'EOF'
   MENU RESOLUTION 1024 768
   MENU COLOR border       30;44   #40ffffff #a0000000 std
   MENU COLOR title        1;36;44 #9033ccff #a0000000 std
   MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
   MENU COLOR unsel        37;44   #50ffffff #a0000000 std
   MENU COLOR help         37;40   #c0ffffff #a0000000 std
   MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
   MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
   MENU COLOR msg07        37;40   #90ffffff #a0000000 std
   MENU COLOR tabmsg       31;40   #30ffffff #00000000 std
   
   MENU VSHIFT 8
   MENU HSHIFT 13
   MENU WIDTH 49
   MENU MARGIN 8
   MENU ROWS 16
   MENU TABMSGROW 24
   MENU CMDLINEROW 24
   MENU ENDROW 24
   MENU PASSWORDROW 11
   MENU TIMEOUTROW 22
   EOF
   ```

2. **Add custom background:**
   ```bash
   # Convert image to appropriate format (640x480, 14-color VGA)
   convert boot-logo.png -resize 640x480 -colors 14 data/tftp/boot.jpg
   ```

## 🐳 Advanced Container Customization

### Multi-Stage Container Build

```dockerfile
# Multi-stage Dockerfile for optimized container
FROM ubuntu:22.04 AS base

# Install build dependencies
RUN apt-get update && apt-get install -y \
    wget curl unzip build-essential \
    && rm -rf /var/lib/apt/lists/*

# Download and compile custom tools
FROM base AS builder
WORKDIR /build
RUN wget https://example.com/custom-tool.tar.gz && \
    tar -xzf custom-tool.tar.gz && \
    make && make install

# Final runtime image
FROM ubuntu:22.04
COPY --from=builder /usr/local/bin/custom-tool /usr/local/bin/
# ... rest of container setup
```

### Adding Custom Services

1. **Create custom service script:**
   ```bash
   cat > scripts/custom-service.sh << 'EOF'
   #!/bin/bash
   # Custom monitoring service
   
   while true; do
       # Custom monitoring logic
       check_custom_metrics
       sleep 60
   done
   EOF
   ```

### Container Hooks and Extensions

1. **Pre-start hooks:**
   ```bash
   # Add to entrypoint.sh
   run_pre_start_hooks() {
       if [[ -d /usr/local/hooks/pre-start ]]; then
           for hook in /usr/local/hooks/pre-start/*.sh; do
               if [[ -x "$hook" ]]; then
                   echo "Running pre-start hook: $(basename "$hook")"
                   "$hook"
               fi
           done
       fi
   }
   ```

2. **Configuration reload hooks:**
   ```bash
   # Add reload capability
   reload_configuration() {
       echo "Reloading configuration..."
       
       # Reload nginx
       nginx -s reload
       
       # Restart dnsmasq
       supervisorctl restart dnsmasq
       
       # Run custom reload hooks
       for hook in /usr/local/hooks/reload/*.sh; do
           [[ -x "$hook" ]] && "$hook"
       done
   }
   
   # Add signal handler
   trap 'reload_configuration' USR1
   ```

## 🔗 Integration with External Services

### LDAP Authentication

1. **Add LDAP support to nginx:**
   ```bash
   # Install nginx-ldap-auth module
   RUN apt-get install -y libnginx-mod-http-auth-ldap
   
   # Configure LDAP in nginx
   cat >> /etc/nginx/sites-available/httpboot << 'EOF'
   
   auth_ldap "LDAP Authentication";
   auth_ldap_servers ldap_server;
   
   upstream ldap_server {
       server ldap://ldap.company.com:389;
   }
   EOF
   ```

### Database Integration

1. **Add PostgreSQL client:**
   ```bash
   # In Dockerfile
   RUN apt-get install -y postgresql-client
   
   # Create database logging script
   cat > /usr/local/bin/log-boot-event.sh << 'EOF'
   #!/bin/bash
   
   DB_HOST="${DB_HOST:-localhost}"
   DB_NAME="${DB_NAME:-httpboot}"
   DB_USER="${DB_USER:-httpboot}"
   
   log_boot_event() {
       local client_ip="$1"
       local boot_file="$2"
       local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
       
       psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USER" -c \
           "INSERT INTO boot_log (timestamp, client_ip, boot_file) VALUES ('$timestamp', '$client_ip', '$boot_file');"
   }
   
   # Call from nginx log processing
   log_boot_event "$@"
   EOF
   ```

### Monitoring Integration

#### Prometheus Metrics

1. **Add metrics endpoint:**
   ```bash
   # Create metrics collector
   cat > /usr/local/bin/collect-metrics.sh << 'EOF'
   #!/bin/bash
   
   METRICS_FILE="/var/lib/httpboot/metrics.prom"
   
   # HTTP requests
   http_requests=$(grep -c "GET\|POST" /var/log/httpboot/nginx-access.log)
   echo "httpboot_http_requests_total $http_requests" > "$METRICS_FILE"
   
   # TFTP requests
   tftp_requests=$(grep -c "RRQ\|WRQ" /var/log/httpboot/dnsmasq.log)
   echo "httpboot_tftp_requests_total $tftp_requests" >> "$METRICS_FILE"
   
   # Boot events
   boot_events=$(grep -c "pxelinux.0" /var/log/httpboot/nginx-access.log)
   echo "httpboot_boot_events_total $boot_events" >> "$METRICS_FILE"
   EOF
   
   # Add to cron
   echo "*/1 * * * * /usr/local/bin/collect-metrics.sh" | crontab -
   ```

2. **Configure Prometheus scraping:**
   ```yaml
   # prometheus.yml
   scrape_configs:
     - job_name: 'httpboot'
       static_configs:
         - targets: ['httpboot-server:8080']
       metrics_path: '/metrics'
       scrape_interval: 30s
   ```

#### Grafana Dashboards

1. **Create dashboard JSON:**
   ```json
   {
     "dashboard": {
       "id": null,
       "title": "HTTP Boot Infrastructure",
       "tags": ["httpboot", "pxe"],
       "timezone": "browser",
       "panels": [
         {
           "title": "Boot Events Over Time",
           "type": "graph",
           "targets": [
             {
               "expr": "rate(httpboot_boot_events_total[5m])",
               "legendFormat": "Boot Events/sec"
             }
           ]
         },
         {
           "title": "Service Status",
           "type": "stat",
           "targets": [
             {
               "expr": "up{job=\"httpboot\"}",
               "legendFormat": "Service Status"
             }
           ]
         }
       ]
     }
   }
   ```

### External File Storage

#### NFS Integration

1. **Add NFS support:**
   ```bash
   # In Dockerfile
   RUN apt-get install -y nfs-common
   
   # Mount NFS share in entrypoint
   if [[ -n "${NFS_SERVER}" && -n "${NFS_PATH}" ]]; then
       mkdir -p /mnt/nfs-share
       mount -t nfs "${NFS_SERVER}:${NFS_PATH}" /mnt/nfs-share
       
       # Link additional boot files
       ln -sf /mnt/nfs-share/boot-images/* /var/lib/httpboot/http/images/
   fi
   ```

#### S3/Object Storage

1. **Add S3 integration:**
   ```bash
   # Install AWS CLI
   RUN apt-get install -y awscli
   
   # Sync boot files from S3
   sync_from_s3() {
       if [[ -n "${S3_BUCKET}" ]]; then
           aws s3 sync "s3://${S3_BUCKET}/boot-files/" /var/lib/httpboot/http/images/
       fi
   }
   
   # Add to cron for periodic sync
   echo "0 */6 * * * sync_from_s3" | crontab -
   ```

## ⚡ Performance Optimization

### Caching Strategies

#### HTTP Caching

1. **Configure nginx caching:**
   ```nginx
   # Add to nginx configuration
   proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=boot_cache:10m max_size=1g inactive=60m;
   
   location ~* \.(efi|img|iso|gz)$ {
       proxy_cache boot_cache;
       proxy_cache_valid 200 1h;
       proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
       
       add_header X-Cache-Status $upstream_cache_status;
       expires 1h;
   }
   ```

#### TFTP Optimization

1. **Optimize TFTP block size:**
   ```bash
   # In .env
   TFTP_BLOCKSIZE=1468  # Maximum for most Ethernet networks
   
   # Configure in tftpd
   TFTP_OPTIONS="--secure --create --verbose --blocksize 1468"
   ```

### Load Balancing

#### Multiple HTTP Boot Servers

1. **Create load balancer configuration:**
   ```nginx
   # nginx load balancer
   upstream httpboot_backend {
       server 192.168.1.10:8080;
       server 192.168.1.11:8080;
       server 192.168.1.12:8080;
   }
   
   server {
       listen 80;
       location / {
           proxy_pass http://httpboot_backend;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
       }
   }
   ```

2. **Shared storage for consistency:**
   ```bash
   # Use NFS or distributed filesystem
   # Mount shared storage on all boot servers
   mount -t nfs nfs-server:/boot-data /var/lib/httpboot
   ```

### Resource Monitoring

1. **Add resource monitoring:**
   ```bash
   cat > /usr/local/bin/monitor-resources.sh << 'EOF'
   #!/bin/bash
   
   # Monitor CPU, memory, disk usage
   cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
   mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
   disk_usage=$(df /var/lib/httpboot | tail -1 | awk '{print $5}' | sed 's/%//')
   
   # Log metrics
   echo "$(date): CPU=${cpu_usage}% MEM=${mem_usage}% DISK=${disk_usage}%" >> /var/log/httpboot/resources.log
   
   # Alert if thresholds exceeded
   [[ $(echo "$cpu_usage > 80" | bc) -eq 1 ]] && echo "High CPU usage: ${cpu_usage}%"
   [[ $(echo "$mem_usage > 80" | bc) -eq 1 ]] && echo "High memory usage: ${mem_usage}%"
   [[ $disk_usage -gt 80 ]] && echo "High disk usage: ${disk_usage}%"
   EOF
   
   # Run every minute
   echo "* * * * * /usr/local/bin/monitor-resources.sh" | crontab -
   ```

## 🔒 Security Enhancements

### Certificate Management

#### Automatic Certificate Renewal

1. **Add Let's Encrypt support:**
   ```bash
   # Install certbot
   RUN apt-get install -y certbot python3-certbot-nginx
   
   # Create renewal script
   cat > /usr/local/bin/renew-certificates.sh << 'EOF'
   #!/bin/bash
   
   certbot renew --nginx --quiet
   
   # Reload nginx if certificates were renewed
   if [[ $? -eq 0 ]]; then
       nginx -s reload
   fi
   EOF
   
   # Add to cron
   echo "0 2 * * * /usr/local/bin/renew-certificates.sh" | crontab -
   ```

### Access Control

#### IP-based Access Control

1. **Dynamic IP filtering:**
   ```bash
   cat > /usr/local/bin/update-access-control.sh << 'EOF'
   #!/bin/bash
   
   # Read allowed networks from configuration
   IFS=',' read -ra NETWORKS <<< "$ALLOWED_NETWORKS"
   
   # Generate nginx config snippet
   cat > /etc/nginx/conf.d/access-control.conf << 'NGINX_EOF'
   # Auto-generated access control
   NGINX_EOF
   
   for network in "${NETWORKS[@]}"; do
       echo "allow $network;" >> /etc/nginx/conf.d/access-control.conf
   done
   
   echo "deny all;" >> /etc/nginx/conf.d/access-control.conf
   
   # Reload nginx
   nginx -s reload
   EOF
   ```

#### Rate Limiting

1. **Add rate limiting:**
   ```nginx
   # Add to nginx config
   http {
       limit_req_zone $binary_remote_addr zone=boot_limit:10m rate=10r/m;
       
       server {
           location / {
               limit_req zone=boot_limit burst=5 nodelay;
               # ... rest of configuration
           }
       }
   }
   ```

### Audit Logging

1. **Enhanced logging:**
   ```bash
   cat > /usr/local/bin/audit-logger.sh << 'EOF'
   #!/bin/bash
   
   # Parse nginx logs for security events
   tail -f /var/log/httpboot/nginx-access.log | while read line; do
       # Extract IP, method, URI, status
       ip=$(echo "$line" | awk '{print $1}')
       method=$(echo "$line" | awk '{print $6}' | tr -d '"')
       uri=$(echo "$line" | awk '{print $7}')
       status=$(echo "$line" | awk '{print $9}')
       
       # Log security-relevant events
       case "$status" in
           403|404|401)
               logger -t httpboot-audit "SECURITY: $ip attempted $method $uri (status: $status)"
               ;;
       esac
   done
   EOF
   ```

## 📊 Monitoring and Alerting

### Custom Health Checks

1. **Application-specific health checks:**
   ```bash
   cat > /usr/local/bin/advanced-health-check.sh << 'EOF'
   #!/bin/bash
   
   # Check boot file integrity
   check_boot_files() {
       local failed=0
       
       # Verify checksums
       if [[ -f /var/lib/httpboot/checksums.md5 ]]; then
           cd /var/lib/httpboot/tftp
           if ! md5sum -c /var/lib/httpboot/checksums.md5 --quiet; then
               echo "CRITICAL: Boot file integrity check failed"
               failed=1
           fi
       fi
       
       return $failed
   }
   
   # Check external dependencies
   check_dependencies() {
       local failed=0
       
       # Test repository connectivity
       if ! curl -s --head "http://deb.debian.org/debian/" | head -1 | grep -q "200 OK"; then
           echo "WARNING: Debian repository unreachable"
           failed=1
       fi
       
       return $failed
   }
   
   # Main health check
   main() {
       local exit_code=0
       
       check_boot_files || exit_code=1
       check_dependencies || exit_code=1
       
       exit $exit_code
   }
   
   main "$@"
   EOF
   ```

### Integration with Alerting Systems

#### PagerDuty Integration

1. **Create PagerDuty alerting:**
   ```bash
   cat > /usr/local/bin/pagerduty-alert.sh << 'EOF'
   #!/bin/bash
   
   PAGERDUTY_URL="https://events.pagerduty.com/v2/enqueue"
   INTEGRATION_KEY="${PAGERDUTY_INTEGRATION_KEY}"
   
   send_alert() {
       local severity="$1"
       local summary="$2"
       local details="$3"
       
       curl -X POST "$PAGERDUTY_URL" \
           -H "Content-Type: application/json" \
           -d "{
               \"routing_key\": \"$INTEGRATION_KEY\",
               \"event_action\": \"trigger\",
               \"payload\": {
                   \"summary\": \"$summary\",
                   \"severity\": \"$severity\",
                   \"source\": \"httpboot-infrastructure\",
                   \"custom_details\": {
                       \"details\": \"$details\"
                   }
               }
           }"
   }
   
   # Usage: pagerduty-alert.sh critical "Service Down" "HTTP Boot server is not responding"
   send_alert "$@"
   EOF
   ```

## 🧪 Development and Testing

### Automated Testing

1. **Create test suite:**
   ```bash
   cat > tests/test-httpboot.sh << 'EOF'
   #!/bin/bash
   
   # Test HTTP service
   test_http_service() {
       echo "Testing HTTP service..."
       
       # Test health endpoint
       if curl -f http://localhost:8080/health; then
           echo "✅ HTTP health check passed"
       else
           echo "❌ HTTP health check failed"
           return 1
       fi
       
       # Test file serving
       if curl -f http://localhost:8080/boot/pxelinux.0 -o /dev/null; then
           echo "✅ File serving test passed"
       else
           echo "❌ File serving test failed"
           return 1
       fi
   }
   
   # Test TFTP service
   test_tftp_service() {
       echo "Testing TFTP service..."
       
       if command -v tftp >/dev/null; then
           if timeout 5 tftp localhost -c get pxelinux.0 /tmp/test-pxelinux.0; then
               echo "✅ TFTP test passed"
               rm -f /tmp/test-pxelinux.0
           else
               echo "❌ TFTP test failed"
               return 1
           fi
       else
           echo "⚠️ TFTP client not available, skipping test"
       fi
   }
   
   # Run all tests
   main() {
       local failed=0
       
       test_http_service || failed=1
       test_tftp_service || failed=1
       
       if [[ $failed -eq 0 ]]; then
           echo "✅ All tests passed"
       else
           echo "❌ Some tests failed"
       fi
       
       exit $failed
   }
   
   main "$@"
   EOF
   
   chmod +x tests/test-httpboot.sh
   ```

### Development Environment

1. **Create development docker-compose:**
   ```yaml
   # docker-compose.dev.yml
   version: '3.8'
   services:
     httpboot-dev:
       extends:
         file: docker-compose.yml
         service: httpboot-server
       ports:
         - "8080:8080"
         - "69:6969/udp"
       volumes:
         - ./data:/var/lib/httpboot
         - ./scripts:/usr/local/scripts
         - ./src:/usr/local/src  # Mount source for development
       environment:
         - LOG_LEVEL=debug
         - ENABLE_ACCESS_LOG=true
   ```

2. **Live development setup:**
   ```bash
   # Start development environment
   docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d
   
   # Watch for changes and reload
   cat > dev-watch.sh << 'EOF'
   #!/bin/bash
   
   # Install inotify-tools if needed
   command -v inotifywait >/dev/null || sudo apt-get install -y inotify-tools
   
   # Watch for changes
   while inotifywait -e modify,create,delete -r scripts/ data/; do
       echo "Changes detected, restarting services..."
       docker-compose restart httpboot-dev
   done
   EOF
   
   chmod +x dev-watch.sh
   ```

---

This extension guide provides frameworks and examples for customizing the HTTP Boot Infrastructure to meet specific needs. The modular design allows for easy integration of new distributions, services, and features while maintaining the core functionality and reliability of the system.