# HTTP Boot Infrastructure

A complete containerized HTTP Boot server solution using Podman, designed for network booting Linux distributions in enterprise and lab environments.

## 🚀 Quick Start

1. **Configure your environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your network settings
   ```

2. **Validate configuration:**
   ```bash
   ./validate-config.sh
   ```

3. **Deploy the infrastructure:**
   ```bash
   ./setup.sh
   ```

4. **Configure your DHCP server** to point clients to this boot server

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Network Setup](#network-setup)
- [Usage](#usage)
- [Management](#management)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Extending](#extending)

## 🎯 Overview

This HTTP Boot infrastructure provides:

- **Multi-service container** with TFTP, HTTP, and optional DHCP relay
- **Multi-distribution support** for Debian, Ubuntu, CentOS, and Fedora
- **Flexible boot methods** supporting BIOS, UEFI, and hybrid configurations
- **Production-ready features** including health monitoring, backup utilities, and comprehensive logging
- **Easy management** with automated scripts and validation tools

### Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PXE Client    │────│   DHCP Server   │────│  HTTP Boot      │
│                 │    │                 │    │  Infrastructure │
│ • BIOS/UEFI     │    │ • IP Assignment │    │                 │
│ • Network Card  │    │ • Boot Options  │    │ • TFTP Server   │
│ • PXE Support   │    │ • Next Server   │    │ • HTTP Server   │
└─────────────────┘    └─────────────────┘    │ • Boot Images   │
                                              │ • Configurations│
                                              └─────────────────┘
```

## 🔧 Prerequisites

### System Requirements

- **Operating System:** Linux (tested on Ubuntu 22.04+, CentOS 8+, Fedora 35+)
- **Container Runtime:** Podman 3.0+ (installed and configured)
- **Disk Space:** Minimum 2GB available (more for multiple distributions)
- **Memory:** 1GB RAM minimum, 2GB recommended
- **Network:** Internet connectivity for downloading boot images

### Network Requirements

- **Dedicated subnet** or VLAN for boot clients
- **DHCP server access** for configuration (or use built-in DHCP relay)
- **Firewall rules** allowing TFTP (69/UDP) and HTTP (8080/TCP or custom)
- **Static IP** recommended for the boot server host

### Permission Requirements

- **Root access** for privileged ports (< 1024) or container privileges
- **Write access** to project directory for data storage
- **Network configuration** rights for service binding

## 📦 Installation

### 1. Download and Setup

```bash
# Clone or download the project
git clone <repository-url> httpboot-infrastructure
cd httpboot-infrastructure

# Make scripts executable
chmod +x *.sh scripts/*.sh
```

### 2. Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit configuration for your network
nano .env
```

### 3. Validation and Deployment

```bash
# Validate configuration
./validate-config.sh

# Deploy infrastructure
./setup.sh
```

## ⚙️ Configuration

### Environment Variables (.env)

#### Network Configuration
```bash
# Network topology
NETWORK_SUBNET=192.168.1.0/24          # Your network subnet
HOST_IP=192.168.1.10                   # Static IP for boot server
GATEWAY_IP=192.168.1.1                 # Network gateway
DNS_PRIMARY=8.8.8.8                    # Primary DNS server
DNS_SECONDARY=8.8.4.4                  # Secondary DNS server

# DHCP settings (if using built-in DHCP)
DHCP_RANGE_START=192.168.1.100         # DHCP range start
DHCP_RANGE_END=192.168.1.200           # DHCP range end
```

#### Service Configuration
```bash
# Service ports
HTTP_PORT=8080                         # HTTP server port
TFTP_PORT=69                           # TFTP server port

# Boot configuration
PRIMARY_DISTRO=debian                  # Primary distribution (debian/ubuntu/centos/fedora)
ARCHITECTURE=amd64                     # Target architecture (amd64/arm64/i386)
BOOT_METHOD=both                       # Boot method (bios/uefi/both)
BOOT_TIMEOUT=30                        # Boot menu timeout (seconds)
```

#### Container Settings
```bash
# Container configuration
CONTAINER_NAME=httpboot-server         # Container name
DATA_DIRECTORY=./data                  # Data storage directory
RESTART_POLICY=always                  # Container restart policy
```

### Validation

The `validate-config.sh` script performs comprehensive validation:

- ✅ **Network configuration** validation (IP formats, subnet calculations)
- ✅ **System requirements** checking (Podman, permissions, disk space)
- ✅ **Port availability** verification
- ✅ **Internet connectivity** testing
- ✅ **Configuration completeness** validation

## 🌐 Network Setup

### DHCP Server Configuration

Configure your DHCP server to direct clients to the HTTP Boot infrastructure:

#### ISC DHCP Server
```bash
# /etc/dhcp/dhcpd.conf
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    
    # PXE Boot Configuration
    next-server 192.168.1.10;            # HTTP Boot server IP
    
    # BIOS clients
    if option client-arch = 00:00 {
        filename "pxelinux.0";
    }
    # UEFI clients
    elsif option client-arch = 00:07 {
        filename "bootx64.efi";
    }
    elsif option client-arch = 00:09 {
        filename "bootx64.efi";
    }
}
```

#### Dnsmasq
```bash
# /etc/dnsmasq.conf
dhcp-range=192.168.1.100,192.168.1.200,12h
dhcp-option=option:router,192.168.1.1
dhcp-option=option:dns-server,8.8.8.8

# PXE Boot
dhcp-match=set:bios,option:client-arch,0
dhcp-match=set:efi64,option:client-arch,7
dhcp-match=set:efi64,option:client-arch,9

dhcp-boot=tag:bios,pxelinux.0,192.168.1.10
dhcp-boot=tag:efi64,bootx64.efi,192.168.1.10

enable-tftp
tftp-root=/var/lib/httpboot/tftp
```

### Firewall Configuration

#### iptables
```bash
# Allow TFTP
iptables -A INPUT -p udp --dport 69 -j ACCEPT

# Allow HTTP
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT

# Save rules
iptables-save > /etc/iptables/rules.v4
```

#### firewalld
```bash
# Open ports
firewall-cmd --permanent --add-port=69/udp
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --reload
```

## 🎮 Usage

### Starting Services

```bash
# Start the infrastructure
./setup.sh

# Using docker-compose (alternative)
docker-compose up -d
```

### Managing Container

```bash
# Check status
podman ps

# View logs
podman logs httpboot-server

# Stop/start services
podman stop httpboot-server
podman start httpboot-server

# Restart services
podman restart httpboot-server
```

### Downloading Boot Images

```bash
# Download primary distribution
./scripts/download-images.sh

# Download all supported distributions
./scripts/download-images.sh --all

# Download specific distribution
./scripts/download-images.sh --distro ubuntu --arch amd64
```

### Health Monitoring

```bash
# Run health check
./scripts/health-check.sh

# Quick health check
./scripts/health-check.sh quick

# Continuous monitoring
./scripts/health-check.sh monitor

# Check system resources
./scripts/health-check.sh resources
```

### Configuration Backup

```bash
# Create configuration backup
./scripts/backup-config.sh

# List available backups
./scripts/backup-config.sh list

# Restore from backup
./scripts/backup-config.sh restore backups/httpboot_backup_*.tar.gz
```

## 🔧 Management

### Container Management

#### Updating the Container
```bash
# Stop current container
podman stop httpboot-server

# Rebuild with updates
./setup.sh --force-rebuild

# Or manually rebuild
podman build -t httpboot-server:latest .
```

#### Scaling and Performance
```bash
# Monitor resource usage
podman stats httpboot-server

# Update resource limits
podman update --memory=2g --cpus=2.0 httpboot-server
```

### Data Management

#### Directory Structure
```
data/
├── tftp/                    # TFTP boot files
│   ├── pxelinux.0
│   ├── pxelinux.cfg/
│   │   └── default
│   └── debian-installer/
├── http/                    # HTTP boot files
│   ├── boot/               # Symlinks to TFTP files
│   └── images/             # Additional boot images
├── configs/                 # Service configurations
├── logs/                   # Service logs
└── backup/                 # Configuration backups
```

#### Adding Custom Boot Options

1. **Create custom boot files:**
   ```bash
   # Add custom kernel and initrd
   cp custom-vmlinuz data/tftp/
   cp custom-initrd.img data/tftp/
   ```

2. **Update boot menu:**
   ```bash
   # Edit data/tftp/pxelinux.cfg/default
   cat >> data/tftp/pxelinux.cfg/default << EOF
   
   LABEL custom
       MENU LABEL Custom Boot Option
       KERNEL custom-vmlinuz
       APPEND initrd=custom-initrd.img custom-options
   EOF
   ```

3. **Restart services:**
   ```bash
   podman restart httpboot-server
   ```

### Log Management

#### Viewing Logs
```bash
# Container logs
podman logs -f httpboot-server

# Service-specific logs
podman exec httpboot-server tail -f /var/log/httpboot/nginx-access.log
podman exec httpboot-server tail -f /var/log/httpboot/dnsmasq.log
```

#### Log Rotation
```bash
# Configure log rotation
cat > /etc/logrotate.d/httpboot << EOF
/var/log/httpboot/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 httpboot httpboot
    postrotate
        podman kill -s USR1 httpboot-server
    endscript
}
EOF
```

## 🛡️ Security

### Network Security

#### Access Control
```bash
# Configure allowed networks in .env
ALLOWED_NETWORKS="192.168.1.0/24,10.0.0.0/8"

# Enable HTTP authentication
ENABLE_HTTP_AUTH=true
HTTP_USERNAME=admin
HTTP_PASSWORD=secure-password-here
```

#### SSL/TLS Configuration
```bash
# Enable SSL
ENABLE_SSL=true
SSL_CERT_PATH=/path/to/certificate.crt
SSL_KEY_PATH=/path/to/private.key

# Generate self-signed certificate (for testing)
openssl req -x509 -newkey rsa:4096 -keyout ssl.key -out ssl.crt -days 365 -nodes
```

### Container Security

#### SELinux/AppArmor
```bash
# SELinux context for volumes
chcon -Rt container_file_t ./data

# Or disable SELinux enforcement for containers
setsebool -P container_manage_cgroup true
```

#### Rootless Operation
```bash
# Run as non-root user (configure in Dockerfile)
USER httpboot

# Use rootless Podman
podman --remote run --userns=keep-id ...
```

### Boot Security

#### Secure Boot Support
```bash
# Enable UEFI Secure Boot
ENABLE_SECURE_BOOT=true

# Add signed boot files to data/tftp/
cp signed-bootx64.efi data/tftp/
cp signed-grubx64.efi data/tftp/
```

#### Network Isolation
```bash
# Use dedicated VLAN for boot traffic
# Configure switch ports for boot VLAN
# Isolate boot network from production systems
```

## 📈 Monitoring and Alerts

### Health Monitoring

The infrastructure includes comprehensive health monitoring:

- **Service availability** checking (HTTP, TFTP, container status)
- **Resource usage** monitoring (CPU, memory, disk)
- **Log analysis** for errors and warnings
- **Network connectivity** testing

### Setting up Alerts

#### Email Notifications
```bash
# Install mail utilities
apt-get install mailutils

# Create monitoring script
cat > monitor-httpboot.sh << 'EOF'
#!/bin/bash
./scripts/health-check.sh quick
if [ $? -ne 0 ]; then
    echo "HTTP Boot infrastructure issues detected" | mail -s "Boot Server Alert" admin@company.com
fi
EOF

# Add to crontab
echo "*/5 * * * * /path/to/monitor-httpboot.sh" | crontab -
```

#### Integration with Monitoring Systems

##### Prometheus Metrics
```bash
# Enable Prometheus endpoint in nginx config
location /metrics {
    stub_status on;
    access_log off;
    allow 127.0.0.1;
    deny all;
}
```

##### Grafana Dashboard
```json
{
  "dashboard": {
    "title": "HTTP Boot Infrastructure",
    "panels": [
      {
        "title": "Service Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"httpboot\"}"
          }
        ]
      }
    ]
  }
}
```

## 📚 Additional Resources

### Documentation Files

- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[EXTENDING.md](EXTENDING.md)** - Adding new distributions and customizations
- **[SECURITY.md](SECURITY.md)** - Security best practices and hardening guide

### External Resources

- [Podman Documentation](https://docs.podman.io/)
- [PXE Boot Specification](https://www.intel.com/content/www/us/en/embedded/technology/pxe-boot-technology.html)
- [UEFI Network Boot](https://uefi.org/specifications)
- [Debian Network Boot](https://www.debian.org/distrib/netinst)
- [Ubuntu Network Installation](https://ubuntu.com/server/docs/install/netboot)

## 🤝 Contributing

### Reporting Issues

1. **Check existing issues** in the project repository
2. **Provide detailed information:**
   - Environment details (OS, Podman version)
   - Configuration files (sanitized)
   - Error logs and output
   - Steps to reproduce

### Feature Requests

1. **Describe the use case** and benefits
2. **Provide implementation details** if possible
3. **Consider backward compatibility**

### Development

1. **Fork the repository**
2. **Create feature branch** from main
3. **Test thoroughly** with validation scripts
4. **Submit pull request** with detailed description

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Podman team** for excellent container runtime
- **Debian/Ubuntu/CentOS/Fedora communities** for maintaining netboot images
- **PXE Boot specification authors** for standardizing network boot
- **Open source community** for tools and inspiration

---

For additional help and support, please refer to the troubleshooting guide or create an issue in the project repository.