# HTTP Boot Infrastructure - Troubleshooting Guide

This guide covers common issues, solutions, and debugging techniques for the HTTP Boot Infrastructure.

## 📋 Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Container Issues](#container-issues)
- [Network Boot Problems](#network-boot-problems)
- [Service-Specific Issues](#service-specific-issues)
- [Configuration Problems](#configuration-problems)
- [Performance Issues](#performance-issues)
- [Security and Permission Issues](#security-and-permission-issues)
- [Advanced Debugging](#advanced-debugging)

## 🔍 Quick Diagnostics

### Service Management Overview

The HTTP Boot Infrastructure uses **direct service management** instead of supervisor. Services (nginx and TFTP) are managed directly by the entrypoint script with built-in monitoring and restart capabilities.

**Key service processes to check:**
- `nginx` - HTTP server process
- `in.tftpd` - TFTP server process
- `entrypoint.sh` - Main management process

### First Steps for Any Issue

1. **Run health check:**
   ```bash
   ./scripts/health-check.sh
   ```

2. **Check container status:**
   ```bash
   podman ps -a
   podman logs httpboot-server
   ```

3. **Validate configuration:**
   ```bash
   ./validate-config.sh
   ```

### Common Commands for Debugging

```bash
# Check all services
podman exec httpboot-server ps aux

# Test HTTP service
curl http://localhost:8080/health

# Test TFTP connectivity
echo "test" | nc -u localhost 6969

# Check running processes
podman exec httpboot-server ps aux

# Check disk space
df -h data/

# Monitor resource usage
podman stats httpboot-server
```

## 🐳 Container Issues

### Container Won't Start

#### Symptoms
- Container exits immediately
- "Port already in use" errors
- Permission denied errors

#### Solutions

1. **Check port conflicts:**
   ```bash
   # Check what's using your ports
   ss -tulpn | grep :8080
   ss -tulpn | grep :6969
   
   # Kill conflicting processes or change ports in .env
   sudo kill -9 <PID>
   ```

2. **Check permissions:**
   ```bash
   # For privileged ports (< 1024)
   sudo ./setup.sh
   
   # Or change to unprivileged ports in .env
   HTTP_PORT=8080
   TFTP_PORT=6969
   ```

3. **Check SELinux/AppArmor:**
   ```bash
   # SELinux
   getenforce
   sudo setsebool -P container_manage_cgroup true
   
   # Set correct context for data directory
   sudo chcon -Rt container_file_t ./data
   
   # AppArmor
   sudo aa-status
   ```

4. **Verify Podman configuration:**
   ```bash
   podman system info
   podman system reset  # Last resort - removes all containers
   ```

### Service Process Issues

#### Symptoms
- HTTP service not responding
- TFTP timeouts
- Services not starting automatically

#### Solutions

1. **Check service processes:**
   ```bash
   # View all processes in container
   podman exec httpboot-server ps aux

   # Check specific services
   podman exec httpboot-server pgrep nginx
   podman exec httpboot-server pgrep in.tftpd
   ```

2. **Restart individual services:**
   ```bash
   # Restart nginx
   podman exec httpboot-server pkill nginx
   # Wait for automatic restart (30 seconds)

   # Restart TFTP
   podman exec httpboot-server pkill in.tftpd
   # Wait for automatic restart (30 seconds)
   ```

3. **Check entrypoint script status:**
   ```bash
   # The entrypoint script should be PID 1
   podman exec httpboot-server ps -p 1

   # Monitor entrypoint logs in real-time
   podman logs -f httpboot-server
   ```

### Container Keeps Restarting

#### Symptoms
- Container status shows "Restarting"
- Health checks failing
- Services not responding

#### Solutions

1. **Check container logs:**
   ```bash
   podman logs --tail 50 httpboot-server
   ```

2. **Common restart causes:**
   ```bash
   # Out of memory
   podman inspect httpboot-server | grep -i memory
   
   # Failed health checks
   curl http://localhost:8080/health
   
   # Service process failures
   podman exec httpboot-server ps aux | grep -E "nginx|tftpd"
   ```

3. **Increase container resources:**
   ```bash
   # Edit docker-compose.yml or add to podman run:
   --memory=2g --cpus=2.0
   ```

### Container Networking Issues

#### Symptoms
- Services not accessible from host
- Port binding failures
- Container can't reach internet

#### Solutions

1. **Check network mode:**
   ```bash
   podman inspect httpboot-server | grep -i networkmode
   
   # Should show "host" for simplest setup
   ```

2. **Test connectivity:**
   ```bash
   # From container to internet
   podman exec httpboot-server ping -c 3 8.8.8.8
   
   # From host to container services
   telnet localhost 8080
   ```

3. **Firewall issues:**
   ```bash
   # Temporarily disable firewall for testing
   sudo systemctl stop firewalld
   sudo iptables -F
   
   # If this fixes it, add proper rules
   sudo firewall-cmd --permanent --add-port=8080/tcp
   sudo firewall-cmd --permanent --add-port=6969/udp
   sudo firewall-cmd --reload
   ```

## 🌐 Network Boot Problems

### Client Can't Find Boot Server

#### Symptoms
- PXE timeout errors
- "No bootable device" messages
- Client boots from local disk instead

#### Solutions

1. **Verify DHCP configuration:**
   ```bash
   # Check DHCP server logs
   sudo journalctl -u dhcpd
   sudo journalctl -u dnsmasq
   
   # Test DHCP response
   sudo nmap --script broadcast-dhcp-discover
   ```

2. **Verify DHCP options:**
   ```bash
   # Option 66 (next-server) should point to your boot server
   # Option 67 (boot-filename) should be "pxelinux.0" or "bootx64.efi"
   
   # For ISC DHCP, check:
   cat /etc/dhcp/dhcpd.conf | grep -E "next-server|filename"
   ```

3. **Network connectivity test:**
   ```bash
   # From a client machine
   ping 192.168.1.10  # Your boot server IP
   telnet 192.168.1.10 69  # TFTP port
   ```

### TFTP Download Failures

#### Symptoms
- "File not found" errors
- TFTP timeouts
- Partial file downloads

#### Solutions

1. **Check TFTP files:**
   ```bash
   # Verify boot files exist
   ls -la data/tftp/pxelinux.0
   ls -la data/tftp/pxelinux.cfg/default
   
   # Check file permissions
   chmod 644 data/tftp/pxelinux.0
   chmod 644 data/tftp/pxelinux.cfg/default
   ```

2. **Test TFTP service:**
   ```bash
   # Manual TFTP test
   tftp localhost
   > get pxelinux.0
   > quit
   
   # Or using curl
   curl -v tftp://localhost/pxelinux.0 -o /tmp/test
   ```

3. **Check TFTP configuration:**
   ```bash
   podman exec httpboot-server cat /etc/default/tftpd-hpa
   podman exec httpboot-server ps aux | grep tftpd
   ```

### Boot Menu Not Displaying

#### Symptoms
- Client boots but no menu appears
- Menu appears but shows no options
- Default option boots immediately

#### Solutions

1. **Check boot menu configuration:**
   ```bash
   cat data/tftp/pxelinux.cfg/default
   ```

2. **Verify menu files:**
   ```bash
   # Check for menu.c32
   ls -la data/tftp/menu.c32
   ls -la data/tftp/vesamenu.c32
   
   # Download if missing
   ./scripts/download-images.sh
   ```

3. **Test menu timeout:**
   ```bash
   # Edit timeout in pxelinux.cfg/default
   TIMEOUT 300  # 30 seconds (units are 1/10 second)
   ```

### UEFI Boot Issues

#### Symptoms
- UEFI clients can't boot
- Boot loops on UEFI systems
- Secure Boot failures

#### Solutions

1. **Check UEFI boot files:**
   ```bash
   ls -la data/tftp/bootx64.efi
   ls -la data/tftp/grubx64.efi
   ```

2. **Verify DHCP UEFI options:**
   ```bash
   # DHCP should serve different files for UEFI
   # Option 67 should be "bootx64.efi" for UEFI clients
   ```

3. **Secure Boot issues:**
   ```bash
   # Disable Secure Boot in BIOS/UEFI settings
   # Or add signed boot files
   cp signed-bootx64.efi data/tftp/
   ```

## 🔧 Service-Specific Issues

### HTTP Service Problems

#### Symptoms
- HTTP 500/502/503 errors
- Slow file downloads
- Authentication failures

#### Solutions

1. **Check nginx status:**
   ```bash
   podman exec httpboot-server ps aux | grep nginx
   podman exec httpboot-server nginx -t  # Test configuration
   ```

2. **Check nginx logs:**
   ```bash
   podman exec httpboot-server tail -f /var/lib/httpboot/logs/nginx.error.log
   podman exec httpboot-server tail -f /var/lib/httpboot/logs/nginx.log
   ```

3. **Test HTTP functionality:**
   ```bash
   # Test basic connectivity
   curl -v http://localhost:8080/
   
   # Test file serving
   curl -v http://localhost:8080/boot/pxelinux.0 -o /tmp/test
   
   # Test authentication (if enabled)
   curl -u admin:password http://localhost:8080/
   ```

### DHCP Relay Issues

#### Symptoms
- Clients don't get IP addresses
- Wrong boot options provided
- DHCP relay not forwarding

#### Solutions

1. **Check dnsmasq status:**
   ```bash
   podman exec httpboot-server ps aux | grep dnsmasq
   podman exec httpboot-server dnsmasq --test
   ```

2. **Check DHCP configuration:**
   ```bash
   podman exec httpboot-server cat /etc/dnsmasq.conf
   ```

3. **Monitor DHCP traffic:**
   ```bash
   # Inside container
   podman exec httpboot-server tail -f /var/lib/httpboot/logs/dnsmasq.log

   # On host
   sudo tcpdump -i any port 67 or port 68
   ```

### DNS Resolution Issues

#### Symptoms
- Can't download boot images
- Package installation failures
- Slow boot times

#### Solutions

1. **Test DNS resolution:**
   ```bash
   podman exec httpboot-server nslookup debian.org
   podman exec httpboot-server dig ubuntu.com
   ```

2. **Check DNS configuration:**
   ```bash
   podman exec httpboot-server cat /etc/resolv.conf
   ```

3. **Update DNS servers:**
   ```bash
   # Edit .env file
   DNS_PRIMARY=1.1.1.1
   DNS_SECONDARY=8.8.8.8
   
   # Restart container
   podman restart httpboot-server
   ```

## ⚙️ Configuration Problems

### Invalid Network Configuration

#### Symptoms
- Validation script fails
- Clients can't reach server
- DHCP conflicts

#### Solutions

1. **Check network calculations:**
   ```bash
   # Verify subnet contains all IPs
   ipcalc 192.168.1.0/24
   
   # Check IP conflicts
   nmap -sn 192.168.1.0/24
   ```

2. **Common network fixes:**
   ```bash
   # Fix in .env file
   NETWORK_SUBNET=192.168.1.0/24
   HOST_IP=192.168.1.10           # Must be in subnet
   DHCP_RANGE_START=192.168.1.100 # Must be in subnet
   DHCP_RANGE_END=192.168.1.200   # Must be in subnet
   GATEWAY_IP=192.168.1.1         # Must be in subnet
   ```

### Environment Variable Issues

#### Symptoms
- Services use wrong settings
- Features not working as configured
- Validation passes but runtime fails

#### Solutions

1. **Check variable loading:**
   ```bash
   # Verify .env file format
   grep -v '^#' .env | grep -v '^$'
   
   # Check for special characters
   cat -A .env | grep -E '\r|\t'
   ```

2. **Test variable expansion:**
   ```bash
   # Source and test
   source .env
   echo $NETWORK_SUBNET
   echo $HTTP_PORT
   ```

3. **Common variable problems:**
   ```bash
   # No spaces around = sign
   NETWORK_SUBNET=192.168.1.0/24  # Correct
   NETWORK_SUBNET = 192.168.1.0/24  # Wrong
   
   # Quote values with spaces
   ALLOWED_NETWORKS="192.168.1.0/24,10.0.0.0/8"
   
   # Boolean values
   ENABLE_HTTP_AUTH=true  # Not TRUE or True
   ```

### File Permission Issues

#### Symptoms
- "Permission denied" errors
- Files not accessible
- Container can't write files

#### Solutions

1. **Fix data directory permissions:**
   ```bash
   sudo chown -R $(id -u):$(id -g) data/
   chmod -R 755 data/
   chmod -R 644 data/tftp/*
   chmod -R 644 data/http/*
   ```

2. **SELinux context issues:**
   ```bash
   # Check context
   ls -Z data/
   
   # Fix context
   sudo chcon -Rt container_file_t data/
   
   # Or disable SELinux temporarily
   sudo setenforce 0
   ```

3. **Container user issues:**
   ```bash
   # Check container user
   podman exec httpboot-server id
   
   # Fix ownership in container
   podman exec httpboot-server chown -R httpboot:httpboot /var/lib/httpboot
   ```

## 🚀 Performance Issues

### Slow Boot Times

#### Symptoms
- Long delays during boot
- Timeouts during file download
- Client boot takes > 5 minutes

#### Solutions

1. **Optimize TFTP settings:**
   ```bash
   # Increase TFTP block size in .env
   TFTP_BLOCKSIZE=1468  # Maximum for most networks
   ```

2. **Check network bandwidth:**
   ```bash
   # Test download speed
   wget http://localhost:8080/boot/initrd.gz -O /dev/null
   
   # Monitor network usage
   iftop
   vnstat
   ```

3. **Optimize container resources:**
   ```bash
   # Increase container limits
   podman update --memory=2g --cpus=2.0 httpboot-server
   ```

### High Resource Usage

#### Symptoms
- High CPU/memory usage
- System becomes unresponsive
- Container gets killed (OOM)

#### Solutions

1. **Monitor resource usage:**
   ```bash
   podman stats httpboot-server
   htop
   ```

2. **Optimize services:**
   ```bash
   # Reduce nginx worker processes
   # Edit nginx.conf in container
   worker_processes 1;
   
   # Limit dnsmasq cache
   cache-size=500
   ```

3. **Scale resources:**
   ```bash
   # Increase system resources
   # Add more RAM
   # Use faster storage (SSD)
   ```

### Storage Issues

#### Symptoms
- "No space left on device"
- Slow file access
- Container stops due to disk full

#### Solutions

1. **Check disk usage:**
   ```bash
   df -h
   du -sh data/
   du -sh data/tftp/
   du -sh data/http/
   ```

2. **Clean up old files:**
   ```bash
   # Remove old boot images
   find data/ -name "*.tar.gz" -mtime +30 -delete
   
   # Clean container logs
   podman logs httpboot-server | tail -1000 > /tmp/logs
   echo "" | podman exec -i httpboot-server tee /var/log/httpboot/*.log
   ```

3. **Move to larger storage:**
   ```bash
   # Change data directory in .env
   DATA_DIRECTORY=/mnt/large-storage/httpboot-data
   
   # Migrate data
   rsync -av data/ /mnt/large-storage/httpboot-data/
   ```

## 🔒 Security and Permission Issues

### Authentication Problems

#### Symptoms
- HTTP auth not working
- Clients can access without credentials
- Wrong credentials accepted

#### Solutions

1. **Verify HTTP auth configuration:**
   ```bash
   # Check .env settings
   grep -E "HTTP_AUTH|HTTP_USERNAME|HTTP_PASSWORD" .env
   
   # Test authentication
   curl -u admin:password http://localhost:8080/
   ```

2. **Check nginx auth setup:**
   ```bash
   podman exec httpboot-server cat /etc/nginx/.htpasswd
   podman exec httpboot-server nginx -t
   ```

3. **Regenerate credentials:**
   ```bash
   # Update password in .env
   HTTP_PASSWORD=new-secure-password
   
   # Restart container to apply
   podman restart httpboot-server
   ```

### SSL/TLS Issues

#### Symptoms
- SSL certificate errors
- Clients can't connect via HTTPS
- Mixed content warnings

#### Solutions

1. **Check certificate validity:**
   ```bash
   openssl x509 -in ssl.crt -text -noout
   openssl verify ssl.crt
   ```

2. **Test SSL configuration:**
   ```bash
   curl -k https://localhost:8080/
   openssl s_client -connect localhost:443
   ```

3. **Generate new certificates:**
   ```bash
   # Self-signed certificate
   openssl req -x509 -newkey rsa:4096 -keyout ssl.key -out ssl.crt -days 365 -nodes
   
   # Update paths in .env
   SSL_CERT_PATH=/path/to/ssl.crt
   SSL_KEY_PATH=/path/to/ssl.key
   ```

### Firewall and Network Security

#### Symptoms
- Connections blocked
- Services unreachable from network
- Access denied errors

#### Solutions

1. **Check firewall rules:**
   ```bash
   # iptables
   sudo iptables -L -n
   
   # firewalld
   sudo firewall-cmd --list-all
   
   # ufw
   sudo ufw status
   ```

2. **Add required rules:**
   ```bash
   # Allow HTTP Boot ports
   sudo firewall-cmd --permanent --add-port=8080/tcp
   sudo firewall-cmd --permanent --add-port=6969/udp
   sudo firewall-cmd --reload
   ```

3. **Test connectivity:**
   ```bash
   # From client network
   telnet boot-server-ip 8080
   nc -u boot-server-ip 6969
   ```

## 🔬 Advanced Debugging

### Network Packet Analysis

```bash
# Capture DHCP traffic
sudo tcpdump -i any -n port 67 or port 68

# Capture TFTP traffic
sudo tcpdump -i any -n port 6969

# Capture HTTP traffic
sudo tcpdump -i any -n port 8080

# Full network capture for specific client
sudo tcpdump -i any host client-ip -w capture.pcap
```

### Container Debugging

```bash
# Enter container shell
podman exec -it httpboot-server /bin/bash

# Check running processes
podman exec httpboot-server ps aux

# Check service status
podman exec httpboot-server ps aux | grep -E "nginx|tftpd|dnsmasq"

# Debug individual services
podman exec httpboot-server nginx -t
podman exec httpboot-server dnsmasq --test

# Check container filesystem
podman exec httpboot-server find /var/lib/httpboot -type f | head -20
```

### Log Analysis

```bash
# Search for specific errors
podman logs httpboot-server 2>&1 | grep -i error

# Monitor live logs
podman logs -f httpboot-server

# Export logs for analysis
podman logs httpboot-server > debug.log

# Analyze access patterns
podman exec httpboot-server tail -1000 /var/lib/httpboot/logs/nginx.log | \
  awk '{print $1}' | sort | uniq -c | sort -nr
```

### System Tracing

```bash
# Trace system calls
sudo strace -p $(podman inspect httpboot-server | jq '.[0].State.Pid')

# Monitor file access
sudo lsof -p $(podman inspect httpboot-server | jq '.[0].State.Pid')

# Check network connections
sudo netstat -tlpn | grep $(podman inspect httpboot-server | jq '.[0].State.Pid')
```

## 🆘 Emergency Recovery

### Complete Service Reset

```bash
# Stop all services
podman stop httpboot-server
podman rm httpboot-server

# Backup current configuration
./scripts/backup-config.sh

# Reset and redeploy
./setup.sh --force-rebuild
```

### Data Recovery

```bash
# Restore from backup
./scripts/backup-config.sh restore backups/latest-backup.tar.gz

# Re-download boot images
./scripts/download-images.sh --force

# Rebuild container
podman build -t httpboot-server:latest --no-cache .
```

### Network Recovery

```bash
# Reset network configuration
sudo systemctl restart networking
sudo systemctl restart podman

# Flush DNS cache
sudo systemctl restart systemd-resolved

# Reset firewall (DANGER: removes all rules)
sudo iptables -F
sudo iptables -X
```

## 📞 Getting Help

### Information to Collect

When reporting issues, please include:

1. **Environment details:**
   ```bash
   uname -a
   podman --version
   cat /etc/os-release
   ```

2. **Configuration files:**
   ```bash
   # Sanitize sensitive data first
   cat .env | sed 's/PASSWORD=.*/PASSWORD=***/'
   ```

3. **Service status:**
   ```bash
   ./scripts/health-check.sh > health-report.txt
   ```

4. **Log files:**
   ```bash
   podman logs httpboot-server > container.log
   ```

### Community Resources

- Project repository for issues and documentation
- Podman community for container-related issues
- Distribution-specific forums for boot image problems
- Network administration communities for DHCP/PXE issues

---

Remember: Most issues can be resolved by checking logs, validating configuration, and ensuring proper network connectivity. Start with the health check script and work through the common solutions before moving to advanced debugging.