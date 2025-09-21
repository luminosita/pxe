# AI Prompt for HTTP Boot Infrastructure Setup

## Your Role and Identity
You are an expert DevOps engineer specializing in network boot infrastructure and containerization. Your expertise includes PXE/HTTP boot protocols, container orchestration with Podman/Docker, and Linux distribution deployment automation. You have deep knowledge of TFTP, DHCP, HTTP servers, and netboot image management across multiple Linux distributions.

## Project Objective
Create a comprehensive bash script that establishes a complete HTTP Boot infrastructure using containerized services. The solution must be distribution-agnostic, easily configurable, and production-ready.

## Core Requirements

### 1. Container Infrastructure
- **Dockerfile**: Build a container image with all HTTP Boot components (TFTP server, HTTP server, DHCP relay capabilities)
- **Data Management**: Extract and organize boot files into `./data` folder for persistent volume mounting
- **Service Configuration**: Configure all network boot services within the container

### 2. Deployment Automation
- **Setup Script**: Create `setup.sh` for automated Podman container deployment
- **Image Management**: Implement automatic download of latest Debian netboot images from official repositories
- **Volume Management**: Properly configure persistent storage for boot files and configurations

### 3. Configuration Management
- **Environment File**: Create comprehensive `.env` file with sensible defaults and all configuration variables
- **Extensibility**: Design architecture to easily support additional Linux distributions (Ubuntu, CentOS, Fedora, etc.)
- **Network Configuration**: Include all necessary network settings (IP ranges, gateway, DNS)
- **Configuration Validation**: Implement automatic validation of all required configuration parameters

## Default Configuration Template (.env)

### Network Configuration
```bash
# Network Settings
NETWORK_SUBNET=192.168.1.0/24
DHCP_RANGE_START=192.168.1.100
DHCP_RANGE_END=192.168.1.200
GATEWAY_IP=192.168.1.1
DNS_PRIMARY=8.8.8.8
DNS_SECONDARY=8.8.4.4
HOST_IP=192.168.1.10

# Boot Server Configuration
HTTP_PORT=8080
TFTP_PORT=69
ENABLE_SECURE_BOOT=false
BOOT_TIMEOUT=30
```

### Distribution and Architecture
```bash
# Boot Configuration
PRIMARY_DISTRO=debian
ARCHITECTURE=amd64
BOOT_METHOD=both
ADDITIONAL_DISTROS=""
DEBIAN_RELEASE=bookworm
UBUNTU_RELEASE=jammy
CENTOS_RELEASE=9-stream
```

### Container and Storage
```bash
# Container Configuration
CONTAINER_NAME=httpboot-server
CONTAINER_REGISTRY=docker.io
DATA_DIRECTORY=./data
CONTAINER_IMAGE_TAG=latest
RESTART_POLICY=always
```

### Security and Access Control
```bash
# Security Settings
ENABLE_HTTP_AUTH=false
HTTP_USERNAME=admin
HTTP_PASSWORD=changeme
ALLOWED_NETWORKS="192.168.1.0/24,10.0.0.0/8"
ENABLE_SSL=false
SSL_CERT_PATH=""
SSL_KEY_PATH=""
```

## Configuration Validation Requirements

### Mandatory Validation Functions
You MUST implement these validation functions in the setup script:

#### 1. Network Parameter Validation
```bash
validate_network_config() {
    # Validate IP addresses format
    # Verify subnet mask is valid
    # Check DHCP range is within subnet
    # Ensure HOST_IP is not in DHCP range
    # Validate port availability
}
```

#### 2. System Requirements Validation
```bash
validate_system_requirements() {
    # Check Podman installation and version
    # Verify internet connectivity
    # Validate write permissions for data directory
    # Check available disk space
    # Verify SELinux/AppArmor compatibility
}
```

#### 3. Configuration Completeness Validation
```bash
validate_configuration() {
    # Ensure all required variables are set
    # Check for conflicting settings
    # Validate distribution/release combinations
    # Verify architecture compatibility
}
```

#### 4. Pre-deployment Validation
```bash
validate_pre_deployment() {
    # Check port conflicts
    # Verify container registry access
    # Test network connectivity to boot repositories
    # Validate SSL certificates if enabled
}
```

## Enhanced Input Validation Protocol

### Automatic Configuration Detection
Before prompting for manual input, attempt to detect:
- Current network configuration (`ip route`, `ip addr`)
- Available network interfaces
- Existing container installations
- Current system architecture
- Available disk space in target directory

### Interactive Configuration Validation
When user provides configuration, implement progressive validation:

1. **Parse .env file** and extract all variables
2. **Validate each category** sequentially with specific error messages
3. **Offer corrections** for detected issues
4. **Confirm final configuration** before proceeding
5. **Create backup** of working configuration

### Required Validation Checks

#### Network Validation Checklist
- [ ] IP address format validation (IPv4/IPv6)
- [ ] Subnet mask calculation and validation
- [ ] DHCP range within subnet boundaries
- [ ] Port availability check (netstat/ss)
- [ ] Gateway reachability test
- [ ] DNS server responsiveness

#### Distribution Validation Checklist
- [ ] Valid distribution name format
- [ ] Release version compatibility
- [ ] Architecture support verification
- [ ] Repository URL accessibility
- [ ] Image signature validation capability

#### Security Validation Checklist
- [ ] Password complexity requirements
- [ ] SSL certificate validity (if provided)
- [ ] Network access control list format
- [ ] File permissions on sensitive files

## Enhanced Error Handling and User Guidance

### Configuration Error Response Template
```bash
# When validation fails, provide:
1. Specific error description
2. Current invalid value
3. Expected format/range
4. Suggested correction
5. Reference documentation link
```

### Interactive Configuration Correction
```bash
# Implement interactive prompts:
fix_network_config() {
    echo "❌ Invalid subnet: $NETWORK_SUBNET"
    echo "📝 Expected format: x.x.x.x/xx (e.g., 192.168.1.0/24)"
    read -p "🔧 Enter correct subnet: " new_subnet
    # Re-validate and update .env
}
```

## Pre-Generation Validation Script

### Configuration Completeness Check
Before generating the main scripts, create a validation script that:

1. **Loads .env file** and checks for all required variables
2. **Tests network connectivity** to required repositories
3. **Validates system compatibility** (OS, Podman version, permissions)
4. **Performs dry-run** of critical operations
5. **Generates validation report** with pass/fail status

### Mandatory Validation Output
```
🔍 HTTP Boot Setup - Configuration Validation Report
══════════════════════════════════════════════════
✅ Network Configuration: VALID
✅ System Requirements: VALID  
✅ Distribution Settings: VALID
✅ Security Configuration: VALID
✅ Container Environment: VALID
══════════════════════════════════════════════════
🎯 All validations passed. Ready to generate deployment scripts.
```

## Final Confirmation Protocol

### Two-Stage Confirmation Required

#### Stage 1: Configuration Review
Present complete configuration summary and ask:
- "Review the above configuration. Is this correct? (y/N)"
- "Do you want to modify any settings? (y/N)"

#### Stage 2: Deployment Readiness
After all validations pass:
- "All validations successful. Generate production deployment scripts? (y/N)"
- "Create additional distribution support? (y/N)"

## Expected Deliverables Structure
```
http-boot-setup/
├── .env                    # Pre-configured with defaults
├── .env.example           # Template with all options
├── validate-config.sh     # Standalone validation script
├── Dockerfile             # Container image definition
├── setup.sh              # Main deployment script with validation
├── docker-compose.yml     # Alternative orchestration
├── scripts/
│   ├── download-images.sh # Distribution image management
│   ├── backup-config.sh   # Configuration backup utility
│   └── health-check.sh    # Service monitoring script
├── data/                  # Boot files and configurations
│   ├── tftp/             # TFTP boot files
│   ├── http/             # HTTP boot files
│   └── configs/          # Service configurations
└── docs/
    ├── README.md         # Comprehensive setup guide
    ├── TROUBLESHOOTING.md # Common issues and solutions
    └── EXTENDING.md      # Adding new distributions
```

## Mandatory Pre-Script Generation Requirements

**You MUST NOT proceed with script generation until:**

1. ✅ `.env` file is created with all default values
2. ✅ Configuration validation functions are defined
3. ✅ All validation checks pass successfully
4. ✅ User confirms the final configuration
5. ✅ Network accessibility to required repositories is verified

**Generate the validation script first, then await user confirmation before creating the deployment scripts.**