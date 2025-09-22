FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages including gettext-base for envsubst
RUN apt-get update && \
    apt-get install -y nginx tftpd-hpa gettext-base dnsmasq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create user and directories
RUN useradd -r httpboot && \
    mkdir -p /var/lib/httpboot/http /var/lib/httpboot/tftp /var/lib/httpboot/logs /var/lib/httpboot/configs /etc/httpboot

# Copy configuration templates to container
COPY templates/ /etc/httpboot/

# Copy service configuration and entrypoint scripts
COPY scripts/configure-services.sh /usr/local/bin/configure-services.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/configure-services.sh /usr/local/bin/entrypoint.sh

# Create log directory for services
RUN mkdir -p /var/lib/httpboot/logs

# Set initial permissions
RUN chown -R httpboot:httpboot /var/lib/httpboot

EXPOSE 8080 6969/udp

# Use entrypoint script to configure services dynamically
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]