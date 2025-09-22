# CLAUDE.md

## HTTP Boot Infrastructure Generator

This Claude Code command creates a complete HTTP Boot infrastructure setup using containerized services with Podman. The generated solution is distribution-agnostic, production-ready, and includes comprehensive validation and error handling.

## What This Command Creates

### 📦 Generated Files Structure
```
pxe/
├── .env                    # Configuration with sensible defaults
├── .env.example           # Template with all configuration options
├── validate-config.sh     # Pre-deployment validation script
├── Dockerfile             # Multi-service container definition
├── setup.sh              # Main deployment automation script
├── docker-compose.yml     # Alternative orchestration option
├── templates/             # Service configuration templates
│   ├── nginx.conf.template       # HTTP server configuration
│   ├── dnsmasq.conf.template     # DHCP and DNS configuration
│   ├── tftpd-hpa.template        # TFTP server configuration
├── scripts/
│   ├── download-images.sh # Linux distribution image management
│   ├── backup-config.sh   # Configuration backup utility
│   └── health-check.sh    # Service monitoring and diagnostics
├── data/                  # Persistent storage directory
│   ├── tftp/             # TFTP boot files
│   ├── http/             # HTTP boot assets
│   ├── logs/             # Service logs
│   └── backup/           # Configuration backups
├── README.md         # Complete setup and usage guide
├── TROUBLESHOOTING.md # Common issues and solutions
└── EXTENDING.md      # Adding new Linux distributions
```

### 🚀 Key Features

- **Multi-Distribution Support**: Default Debian setup with extensible framework for Ubuntu, CentOS, Fedora
- **Comprehensive Validation**: Pre-flight checks for network, system requirements, and configuration
- **Production Ready**: Includes health monitoring, backup utilities, and troubleshooting guides
- **Security Focused**: Optional HTTP authentication, SSL support, network access controls
- **Architecture Agnostic**: Supports both x86_64 and ARM64 architectures
- **Boot Method Flexible**: Compatible with BIOS, UEFI, or hybrid boot environments

## Prerequisites

### System Requirements
- **Podman** 3.0+ installed and configured
- **Internet connectivity** for downloading boot images
- **Root or sudo access** for network service configuration
- **Minimum 2GB free disk space** for boot images and container data
- **Available network ports**: 69/UDP (TFTP), configurable HTTP port

### Network Planning
Before running, you should know:
- Target network subnet (e.g., 192.168.1.0/24)
- Available IP range for DHCP clients
- Gateway and DNS server addresses
- Host IP where the service will run

## Usage

### Quick Start (Interactive Mode)
```bash
claude httpboot-setup
```

This will:
1. Create the project structure with default configuration
2. Run interactive validation and configuration review
3. Generate all necessary scripts and documentation
4. Provide step-by-step deployment instructions

### Advanced Usage
```bash
# Generate with custom project name
claude httpboot-setup --name "my-boot-server"

# Skip interactive validation (use defaults)
claude httpboot-setup --skip-validation

# Generate for specific distributions
claude httpboot-setup --distros "debian,ubuntu,centos"
```

## Default Configuration

The generated `.env` file includes sensible defaults:

```bash
# Network (modify for your environment)
NETWORK_SUBNET=192.168.1.0/24
DHCP_RANGE_START=192.168.1.100
DHCP_RANGE_END=192.168.1.200
HOST_IP=192.168.1.10

# Services
HTTP_PORT=8080
TFTP_PORT=69
PRIMARY_DISTRO=debian
ARCHITECTURE=amd64

# Container
CONTAINER_NAME=httpboot-server
DATA_DIRECTORY=./data
RESTART_POLICY=always
```

## Post-Generation Steps

1. **Review Configuration**: Edit `.env` file for your network environment
2. **Run Validation**: Execute `./validate-config.sh` to verify setup
3. **Deploy Container**: Run `./setup.sh` to build and start services
4. **Configure DHCP**: Update your DHCP server to point to the boot server
5. **Test Boot**: Attempt network boot from a test client

## Validation Process

The command generates comprehensive validation that checks:
- ✅ Network configuration validity
- ✅ System requirements and permissions  
- ✅ Internet connectivity to repositories
- ✅ Port availability and conflicts
- ✅ Container runtime compatibility
- ✅ Configuration completeness

## Extending Support

The framework is designed for easy extension:
- **New Distributions**: Add configuration in `.env` and update download scripts
- **Custom Boot Images**: Place images in `./data` directory structure
- **Additional Services**: Modify Dockerfile to include new components
- **Security Hardening**: Enable authentication and SSL in configuration

## Troubleshooting

Common issues and solutions are documented in the generated `TROUBLESHOOTING.md`:
- Network boot client configuration
- Container networking issues
- Image download failures
- Permission and SELinux problems

## Example Deployment Flow

```bash
# 1. Generate the setup
claude httpboot-setup

# 2. Customize configuration
vi .env

# 3. Validate setup
./validate-config.sh

# 4. Deploy infrastructure
./setup.sh

# 5. Download boot images
./scripts/download-images.sh

# 6. Validate boot file access
curl http://localhost:8080/boot/version.info
curl -I http://localhost:8080/boot/debian-installer/amd64/linux

# 7. Monitor services  
./scripts/health-check.sh

# 8. Configure DHCP server to use:
#    - Next Server: <HOST_IP>
#    - Boot Filename: pxelinux.0 (BIOS) or bootx64.efi (UEFI)
#    - TFTP Server: <HOST_IP>:6969 (Note: non-standard port for rootless containers)
```

## Security Considerations

The generated setup includes security best practices:
- Non-root container execution where possible
- Network access control lists
- Optional HTTP authentication
- SSL/TLS support for encrypted boot
- Configuration file permission hardening

## Support and Documentation

Each generated project includes:
- **README.md**: Complete setup and usage instructions
- **TROUBLESHOOTING.md**: Common issues and solutions
- **EXTENDING.md**: Guide for adding new distributions
- **Inline comments**: Detailed script documentation
- **Configuration examples**: Multiple deployment scenarios

This command creates enterprise-ready HTTP boot infrastructure that scales from lab environments to production deployments.

## Download Script Execution and Validation

### Download Script Usage

The `scripts/download-images.sh` script automatically downloads and configures boot images for the specified distribution:

```bash
# Download primary distribution (from .env)
./scripts/download-images.sh

# Download specific distribution and architecture
./scripts/download-images.sh --distro debian --arch amd64

# Download all supported distributions
./scripts/download-images.sh --all

# Force re-download even if files exist
./scripts/download-images.sh --force

# Show help
./scripts/download-images.sh --help
```

### Validation Commands

After running the download script, validate the HTTP Boot infrastructure:

#### HTTP Service Validation
```bash
# Test HTTP service health
curl http://localhost:8080/health

# Check boot file directory listing
curl http://localhost:8080/boot/

# Verify Debian installer files
curl http://localhost:8080/boot/debian-installer/amd64/

# Test kernel and initrd accessibility
curl -I http://localhost:8080/boot/debian-installer/amd64/linux
curl -I http://localhost:8080/boot/debian-installer/amd64/initrd.gz

# Check version information
curl http://localhost:8080/boot/version.info
```

#### TFTP Service Validation
```bash
# Test TFTP port connectivity
nc -u -w3 localhost 6969 < /dev/null && echo "TFTP accessible"

# Check TFTP service status in container
podman exec httpboot-server ps aux | grep tftp

# Verify TFTP files are present
podman exec httpboot-server ls -la /var/lib/httpboot/tftp/
```

#### File Structure Validation
```bash
# Verify TFTP directory structure
ls -la ./data/tftp/
ls -la ./data/tftp/debian-installer/amd64/

# Verify HTTP symlinks
ls -la ./data/http/boot/

# Check downloaded images
ls -la ./data/images/

# Verify file sizes and integrity
du -sh ./data/tftp/
du -sh ./data/http/
du -sh ./data/images/
```

#### Service Status Validation
```bash
# Check container status and port mappings
podman ps --filter name=httpboot-server

# Monitor service logs
podman logs httpboot-server

# Run health check script
./scripts/health-check.sh

# Check service processes in container
podman exec httpboot-server ps aux
```

### Troubleshooting Download Issues

If the download script fails:

1. **Check network connectivity**: `curl -I http://deb.debian.org/debian/`
2. **Verify disk space**: `df -h`
3. **Check permissions**: Ensure write access to `./data/` directory
4. **Manual extraction**: If download succeeds but extraction fails, manually extract:
   ```bash
   tar -xzf ./data/images/debian-stable-netboot.tar.gz -C ./data/tftp/
   ```
5. **Fix symlinks**: Create HTTP access symlinks:
   ```bash
   ln -sf ../../tftp/debian-installer ./data/http/boot/
   ln -sf ../../tftp/version.info ./data/http/boot/
   ```

### Expected Outcomes

After successful download and validation:
- **HTTP Service**: Responds on port 8080 with directory listings and file access
- **TFTP Service**: Listens on port 6969 (non-standard for rootless containers)
- **Boot Files**: Debian installer available with kernel, initrd, and bootloader files
- **Directory Structure**: Proper symlinks between TFTP and HTTP directories
- **PXE Configuration**: Default boot menu configured for network installation

## Development Workflow

### Branch-Based Development

This project follows a structured development workflow to ensure code quality and proper change management:

#### Before Making Changes
```bash
# Always create a feature branch before making changes
git checkout main
git pull origin main
git checkout -b feature/your-feature-name

# Example for template changes
git checkout -b feature/template-improvements
```

#### Making Changes
1. **Create Feature Branch**: Always work in feature branches, never directly in main
2. **Make Focused Changes**: Keep changes small and focused on a single feature or fix
3. **Test Changes**: Validate all changes with `./setup.sh` and health checks
4. **Update Documentation**: Update CLAUDE.md, README.md, or other docs as needed

#### Pull Request Process
```bash
# After completing your changes, commit them
git add .
git commit -m "feat: descriptive commit message

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# Push the branch and create a pull request
git push -u origin feature/your-feature-name
gh pr create --title "Brief PR title" --body "$(cat <<'EOF'
## Summary
- Brief description of changes
- Why these changes are needed

## Test Plan
- [ ] Validated setup.sh works correctly
- [ ] Health checks pass
- [ ] Container builds successfully
- [ ] All services start properly

## Documentation Updates
- [ ] Updated CLAUDE.md if needed
- [ ] Updated README.md if needed

🤖 Generated with [Claude Code](https://claude.ai/code)
EOF
)"
```

#### Git Branch Commands
```bash
# List all branches
git branch -a

# Switch to existing branch
git checkout branch-name

# Delete local branch (after merge)
git branch -d feature/branch-name

# Delete remote branch
git push origin --delete feature/branch-name
```

### GitHub CLI Integration

This project uses the GitHub CLI (`gh`) for streamlined pull request management:

#### Installation
```bash
# macOS
brew install gh

# Ubuntu/Debian
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh
```

#### Authentication
```bash
# Authenticate with GitHub
gh auth login
```

#### Common PR Operations
```bash
# Create pull request
gh pr create --title "Title" --body "Description"

# List pull requests
gh pr list

# View PR details
gh pr view PR_NUMBER

# Check PR status
gh pr status

# Merge PR (after approval)
gh pr merge PR_NUMBER --merge

# Close PR without merging
gh pr close PR_NUMBER
```

### Template Development

When modifying service configuration templates in `./templates/`:

#### Template Structure
```
./templates/
├── nginx.conf.template       # HTTP server configuration
├── dnsmasq.conf.template     # DHCP and DNS configuration
├── tftpd-hpa.template        # TFTP server configuration
```

#### Template Variables
All templates support environment variable substitution using `envsubst`:
- `${HTTP_PORT}` - HTTP service port (default: 8080)
- `${TFTP_PORT}` - TFTP service port (default: 6969)
- `${HOST_IP}` - Server IP address
- `${PRIMARY_DISTRO}` - Primary Linux distribution
- `${ARCHITECTURE}` - Target architecture (amd64, arm64)
- `${DHCP_RANGE_START}` - DHCP range start
- `${DHCP_RANGE_END}` - DHCP range end
- `${GATEWAY_IP}` - Network gateway
- `${DNS_PRIMARY}` - Primary DNS server
- `${DNS_SECONDARY}` - Secondary DNS server

#### Template Testing
```bash
# Test template validation
./setup.sh # Will validate all templates exist

# Test container build with templates
podman build -t httpboot-server:latest .

# Test template processing
podman run --rm -e HTTP_PORT=8080 httpboot-server:latest /usr/local/bin/configure-services.sh
```

### Best Practices

1. **Branch Naming**: Use descriptive names like `feature/template-refactor` or `fix/container-networking`
2. **Commit Messages**: Use conventional commit format: `feat:`, `fix:`, `docs:`, `refactor:`
3. **Pull Request Size**: Keep PRs focused and reviewable (< 500 lines of changes)
4. **Testing**: Always test changes with a full setup cycle before creating PR
5. **Documentation**: Update relevant documentation files when making functional changes