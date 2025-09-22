#!/bin/bash
set -euo pipefail

# HTTP Boot Container Entrypoint
# =============================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/lib/httpboot/logs/container.log
}

log "🚀 Starting HTTP Boot Infrastructure Container"

# Configure services with environment variables
log "🔧 Configuring services..."
/usr/local/bin/configure-services.sh

# Set proper ownership
log "🔐 Setting file permissions..."
chown -R httpboot:httpboot /var/lib/httpboot/tftp /var/lib/httpboot/http
chown -R root:root /var/lib/httpboot/logs /var/lib/httpboot/configs
chmod 755 /var/lib/httpboot/tftp /var/lib/httpboot/http
chmod 755 /var/lib/httpboot/logs /var/lib/httpboot/configs

# Ensure log directories are writable
mkdir -p /var/lib/httpboot/logs
chmod 755 /var/lib/httpboot/logs

# Create health check endpoint
log "🏥 Setting up health monitoring..."
cat > /var/lib/httpboot/http/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>HTTP Boot Server</title>
</head>
<body>
    <h1>HTTP Boot Infrastructure</h1>
    <p>Server Status: <strong>Running</strong></p>
    <p>Host: ${HOST_IP:-localhost}</p>
    <p>Distribution: ${PRIMARY_DISTRO:-debian}</p>
    <p>Architecture: ${ARCHITECTURE:-amd64}</p>
    <p>Started: $(date)</p>
    <ul>
        <li><a href="/health">Health Check</a></li>
        <li><a href="/status">Status</a></li>
    </ul>
</body>
</html>
EOF

log "✅ Container initialization complete"
log "🌐 HTTP Server: http://${HOST_IP:-localhost}:${HTTP_PORT:-8080}"
log "📡 TFTP Server: ${HOST_IP:-localhost}:${TFTP_PORT:-6969}"

# Start services directly without supervisor
log "🎯 Starting services directly..."
log "Starting nginx..."
nginx &

log "Starting TFTP service..."
/usr/sbin/in.tftpd --foreground --user httpboot --secure --create --verbose --address 0.0.0.0:${TFTP_PORT:-6969} /var/lib/httpboot/tftp &

log "✅ All services started successfully"
log "🌐 HTTP service running on port ${HTTP_PORT:-8080}"
log "📡 TFTP service running on port ${TFTP_PORT:-6969}"

# Keep container running and monitor services
while true; do
    # Check if nginx is still running
    if ! pgrep nginx > /dev/null; then
        log "⚠️  Nginx stopped, restarting..."
        nginx &
    fi

    # Check if TFTP is still running
    if ! pgrep in.tftpd > /dev/null; then
        log "⚠️  TFTP stopped, restarting..."
        /usr/sbin/in.tftpd --foreground --user httpboot --secure --create --verbose --address 0.0.0.0:${TFTP_PORT:-6969} /var/lib/httpboot/tftp &
    fi

    sleep 30
done