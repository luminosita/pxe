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
log "📡 TFTP Server: ${HOST_IP:-localhost}:${TFTP_PORT:-69}"

# Start supervisor to manage all services
log "🎯 Starting services with supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/httpboot.conf