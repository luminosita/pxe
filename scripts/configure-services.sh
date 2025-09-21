#!/bin/bash
set -euo pipefail

# Service Configuration Script
# ===========================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/lib/httpboot/logs/configure.log
}

log "🔧 Configuring HTTP Boot services..."

# Configure Nginx
log "📝 Configuring Nginx..."
envsubst '${HTTP_PORT} ${HOST_IP} ${PRIMARY_DISTRO} ${ARCHITECTURE}' \
    < /etc/httpboot/nginx.conf.template \
    > /etc/nginx/sites-available/httpboot

# Enable the site
ln -sf /etc/nginx/sites-available/httpboot /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/default.bak

# Configure dnsmasq
log "📝 Configuring dnsmasq..."
envsubst '${DHCP_RANGE_START} ${DHCP_RANGE_END} ${HOST_IP}' \
    < /etc/httpboot/dnsmasq.conf.template \
    > /etc/dnsmasq.conf

# Configure TFTP
log "📝 Configuring TFTP..."
envsubst '${TFTP_PORT}' \
    < /etc/httpboot/tftpd-hpa.template \
    > /etc/default/tftpd-hpa

# Test configuration files
log "🧪 Testing configuration files..."

# Test Nginx configuration
if ! nginx -t -c /etc/nginx/nginx.conf; then
    log "❌ Nginx configuration test failed"
    exit 1
fi

# Test dnsmasq configuration
if ! dnsmasq --test --conf-file=/etc/dnsmasq.conf; then
    log "❌ dnsmasq configuration test failed"
    exit 1
fi

log "✅ All service configurations validated successfully"

# Create PXE boot configuration
log "📝 Creating PXE boot configuration..."
mkdir -p /var/lib/httpboot/tftp/pxelinux.cfg

cat > /var/lib/httpboot/tftp/pxelinux.cfg/default << EOF
DEFAULT menu.c32
PROMPT 0
TIMEOUT 300
MENU TITLE HTTP Boot Infrastructure

LABEL debian
  MENU LABEL Debian ${ARCHITECTURE}
  KERNEL http://${HOST_IP}:${HTTP_PORT}/debian/vmlinuz
  APPEND initrd=http://${HOST_IP}:${HTTP_PORT}/debian/initrd.gz boot=live fetch=http://${HOST_IP}:${HTTP_PORT}/debian/filesystem.squashfs

LABEL local
  MENU LABEL Boot from local disk
  LOCALBOOT 0
EOF

log "✅ Service configuration completed successfully"