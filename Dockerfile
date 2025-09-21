FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && \
    apt-get install -y nginx tftpd-hpa supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create user and directories
RUN useradd -r httpboot && \
    mkdir -p /var/lib/httpboot/http /var/lib/httpboot/tftp /var/lib/httpboot/logs

# Create simple nginx config
RUN printf 'server {\n    listen 8080;\n    root /var/lib/httpboot/http;\n    index index.html;\n    location / {\n        autoindex on;\n    }\n    location /health {\n        return 200 "OK";\n        add_header Content-Type text/plain;\n    }\n}\n' > /etc/nginx/sites-available/default

# Create TFTP configuration
RUN printf 'TFTP_USERNAME="httpboot"\nTFTP_DIRECTORY="/var/lib/httpboot/tftp"\nTFTP_ADDRESS="0.0.0.0:6969"\nTFTP_OPTIONS="--secure --create --verbose"\n' > /etc/default/tftpd-hpa

# Create supervisor configuration
RUN printf '[supervisord]\nnodaemon=true\nlogfile=/var/lib/httpboot/logs/supervisord.log\n\n[program:nginx]\ncommand=nginx -g "daemon off;"\nautostart=true\nautorestart=true\nstdout_logfile=/var/lib/httpboot/logs/nginx.log\nstderr_logfile=/var/lib/httpboot/logs/nginx.error.log\n\n[program:tftpd]\ncommand=/usr/sbin/in.tftpd --foreground --user httpboot --secure --create --verbose --address 0.0.0.0:6969 /var/lib/httpboot/tftp\nautostart=true\nautorestart=true\nstdout_logfile=/var/lib/httpboot/logs/tftp.log\nstderr_logfile=/var/lib/httpboot/logs/tftp.error.log\n' > /etc/supervisor/conf.d/httpboot.conf

# Create simple index page
RUN printf '<h1>HTTP Boot Server</h1><p>Server is running</p>' > /var/lib/httpboot/http/index.html

# Set permissions
RUN chown -R httpboot:httpboot /var/lib/httpboot

EXPOSE 8080 6969/udp

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/httpboot.conf"]