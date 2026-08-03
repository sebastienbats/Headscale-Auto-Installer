#!/bin/bash
# Installation autonome de Headscale-UI (sans Docker)

set -e

UI_VERSION="latest"
UI_DIR="/var/www/headscale-ui"
NGINX_CONF="/etc/nginx/sites-available/headscale-ui"

if [ "$EUID" -ne 0 ]; then
    echo "Veuillez exécuter en root (sudo)."
    exit 1
fi

echo "Téléchargement de Headscale-UI v${UI_VERSION}..."
mkdir -p "$UI_DIR"
wget -qO- "https://github.com/gurucomputing/headscale-ui/releases/download/${UI_VERSION}/headscale-ui.tar.gz" | tar -xz -C "$UI_DIR"

echo "Configuration de Nginx..."
cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name hs-ui.votredomaine.com;

    location /web/ {
        alias $UI_DIR/;
        try_files \$uri \$uri/ =404;
    }
}
EOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
systemctl reload nginx

echo "Headscale-UI installé sur http://hs-ui.votredomaine.com/web"
echo "Générez une clé API : headscale apikeys create -e 9999d"
