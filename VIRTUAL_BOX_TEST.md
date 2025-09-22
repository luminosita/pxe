⏺ 🖥️ VirtualBox PXE Boot Test Plan

  📋 Prerequisites Check

  1. Infrastructure Status:
  # Verify infrastructure is running
  curl http://localhost:8080/health
  podman ps | grep httpboot-server
  2. Boot Images:
  # Download Debian boot images if not present
  ./scripts/download-images.sh

  # Verify boot files exist
  ls -la ./data/tftp/pxelinux.0
  ls -la ./data/tftp/debian-installer/amd64/linux

  🌐 Network Configuration

  Current Setup Analysis:

  - Host IP: 192.168.1.10 (configured in .env)
  - HTTP Port: 8080
  - TFTP Port: 6969 (non-standard for rootless containers)
  - Network: 192.168.1.0/24

  VirtualBox Network Options:

  Option A: Host-Only Network (Recommended)
  # Create host-only network in VirtualBox
  VBoxManage hostonlyif create
  VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.1.1 --netmask 255.255.255.0

  Option B: Bridged Network
  - Use existing network adapter
  - Ensure no DHCP conflicts

  🔧 DHCP Configuration

  Since we don't have a DHCP server configured, we need to:

  Quick DHCP Setup (dnsmasq in container):

  # Check if dnsmasq is configured for DHCP
  podman exec httpboot-server cat /etc/dnsmasq.conf | grep dhcp-range

  # If not configured, we'll use manual IP assignment

  Manual IP Assignment (Simplest):

  - VM: 192.168.1.100
  - Gateway: 192.168.1.1
  - DNS: 8.8.8.8
  - Next-server: 192.168.1.10
  - Boot filename: pxelinux.0

  🖥️ VirtualBox VM Setup

  1. Create VM:

  # Create new VM
  VBoxManage createvm --name "PXE-Test" --register
  VBoxManage modifyvm "PXE-Test" --memory 1024 --cpus 1
  VBoxManage modifyvm "PXE-Test" --nic1 hostonly --hostonlyadapter1 vboxnet0
  VBoxManage modifyvm "PXE-Test" --boot1 net --boot2 none --boot3 none --boot4 none

  2. Enable PXE Boot:

  # Enable network boot
  VBoxManage modifyvm "PXE-Test" --nicbootprio1 1
  VBoxManage modifyvm "PXE-Test" --nattftpserver1 192.168.1.10
  VBoxManage modifyvm "PXE-Test" --nattftpfile1 pxelinux.0

  🧪 Test Execution Steps

  Phase 1: Basic Connectivity

  1. Start VM in headless mode:
  VBoxManage startvm "PXE-Test" --type headless
  2. Monitor network traffic:
  # Monitor DHCP requests
  sudo tcpdump -i vboxnet0 port 67 or port 68

  # Monitor TFTP requests
  sudo tcpdump -i vboxnet0 port 6969

  Phase 2: PXE Boot Test

  1. Start VM with GUI:
  VBoxManage startvm "PXE-Test"
  2. Expected boot sequence:
    - VM attempts network boot
    - DHCP request/response (if configured)
    - TFTP request for pxelinux.0
    - Download boot files
    - Display PXE menu

  Phase 3: Validation

  1. Check infrastructure logs:
  # Monitor HTTP requests
  podman logs -f httpboot-server | grep nginx

  # Check file access
  curl http://localhost:8080/boot/debian-installer/amd64/linux -I
  2. Verify file transfers:
  # Manual TFTP test
  tftp 192.168.1.10 6969
  > get pxelinux.0
  > quit

  🚨 Expected Issues & Solutions

  Issue 1: DHCP Not Working

  Solution: Configure dnsmasq or use static IP
  # In VM: Configure static network
  # IP: 192.168.1.100/24
  # Gateway: 192.168.1.1
  # TFTP Server: 192.168.1.10

  Issue 2: TFTP Port 6969

  Solution: Most PXE clients expect port 69
  # Option A: Run with privileged ports
  sudo podman run --privileged -p 69:69/udp ...

  # Option B: Use iptables redirect
  sudo iptables -t nat -A PREROUTING -p udp --dport 69 -j REDIRECT --to-port 6969

  Issue 3: File Not Found

  Solution: Check file paths and permissions
  ls -la ./data/tftp/pxelinux.0
  ls -la ./data/tftp/debian-installer/

  ⏱️ Quick Test (5 minutes)

  # 1. Verify infrastructure
  curl http://localhost:8080/health && echo "✅ HTTP OK"

  # 2. Check TFTP
  echo "test" | nc -u localhost 6969 && echo "✅ TFTP accessible"

  # 3. Create minimal VM
  VBoxManage createvm --name "Quick-PXE-Test" --register
  VBoxManage modifyvm "Quick-PXE-Test" --memory 512 --boot1 net

  # 4. Start and observe boot attempt
  VBoxManage startvm "Quick-PXE-Test"

  🎯 Success Criteria

  - ✅ VM initiates network boot
  - ✅ TFTP requests reach our server
  - ✅ pxelinux.0 downloads successfully
  - ✅ PXE boot menu appears
  - ✅ Can select Debian installer option
  - ✅ Kernel and initrd download via HTTP

⏺ 🎯 VirtualBox PXE Test Plan Summary

  This plan provides a comprehensive yet practical approach to testing the HTTP Boot Infrastructure with VirtualBox:

  🚀 Key Highlights:

  1. 📋 Prerequisites: Verify infrastructure and download boot images
  2. 🌐 Network Setup: Host-only network configuration with proper IP addressing
  3. 🔧 DHCP Strategy: Both automated and manual IP assignment options
  4. 🖥️ VM Creation: Command-line VirtualBox setup for consistent testing
  5. 🧪 Phased Testing: Basic connectivity → PXE boot → Full validation
  6. 🚨 Issue Mitigation: Pre-identified common problems with solutions
  7. ⏱️ Quick Test: 5-minute validation option for rapid feedback

  ⚠️ Key Challenge Identified:

  The TFTP port 6969 (rootless container) vs standard port 69 (PXE expectation) will likely require:
  - Port forwarding rules, OR
  - Privileged container mode, OR
  - iptables PREROUTING rules

  🎯 Next Steps:

  1. Ensure boot images are downloaded
  2. Configure VirtualBox host-only network
  3. Create test VM
  4. Execute phased testing
  5. Document results and refine setup

  The plan balances thoroughness with practicality - providing both comprehensive testing and quick validation options. Ready to proceed with implementation!