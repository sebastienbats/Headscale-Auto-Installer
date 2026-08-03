#!/bin/bash
# Headscale Config Fixer v1.1
# Corrige la configuration pour la compatibilité avec v0.29.2+
# Licensed under MIT License

set -e

exiterr() { echo "❌ Error: $1" >&2; exit 1; }

# ========== VERSION ET CHEMINS ==========
HS_CONF="/etc/headscale/config.yaml"
HS_CONF_DIR="/etc/headscale"
HS_DATA_DIR="/var/lib/headscale"
HS_RUN_DIR="/var/run/headscale"
HS_SOCK="/var/run/headscale/headscale.sock"
HS_BIN="/usr/local/bin/headscale"

# ========== FONCTIONS ==========
fix_config() {
    echo "🔧 Fixing Headscale configuration for v0.29.2+..."
    
    # Vérifier que Headscale est installé
    if [ ! -f "$HS_BIN" ]; then
        exiterr "Headscale is not installed. Please run install-headscale.sh first."
    fi
    
    # Arrêter le service
    echo "🛑 Stopping Headscale service..."
    systemctl stop headscale 2>/dev/null || true
    
    # Sauvegarder l'ancienne config
    if [ -f "$HS_CONF" ]; then
        local backup="${HS_CONF}.old.$(date +%Y%m%d_%H%M%S)"
        cp "$HS_CONF" "$backup"
        echo "💾 Configuration backed up to $backup"
    fi
    
    # Extraire l'URL du serveur depuis l'ancienne config si possible
    local server_url="http://$(hostname -I | awk '{print $1}'):8080"
    if [ -f "${HS_CONF}.old" ]; then
        server_url=$(grep "^server_url:" "${HS_CONF}.old" 2>/dev/null | awk '{print $2}' || echo "$server_url")
    fi
    
    # Créer la nouvelle configuration
    echo "📝 Creating new configuration file..."
    cat > "$HS_CONF" <<EOF
# Headscale configuration - Compatible v0.29.2+
server_url: ${server_url}
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090
grpc_listen_addr: 0.0.0.0:50443
grpc_allow_insecure: false

# Private key path
private_key_path: ${HS_DATA_DIR}/private.key

# Database
db_type: sqlite3
db_path: ${HS_DATA_DIR}/db.sqlite

# Magic DNS base domain
base_domain: headscale.internal

# DNS configuration (new syntax for v0.29.2+)
dns:
  nameservers:
    global:
      - 1.1.1.1
      - 1.0.0.1
  domains: []
  split_dns: {}

# Policy configuration (new syntax for v0.29.2+)
policy:
  path: ${HS_CONF_DIR}/acl_policy.hujson

# Log level (new syntax for v0.29.2+)
log:
  level: info
  format: text

# IP prefixes for nodes
ip_prefixes:
  - fd7a:115c:a1e0::/48
  - 100.64.0.0/10

# Default preauth key expiry
default_preauth_key_expiry: 24h
EOF

    # Mettre à jour la politique ACL
    echo "📝 Updating ACL policy..."
    cat > "${HS_CONF_DIR}/acl_policy.hujson" <<'EOF'
{
  "groups": {
    "group:admins": ["admin"]
  },
  "hosts": {},
  "acls": [
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["*:*"]
    }
  ],
  "tests": [],
  "autoApprovers": {
    "exitNode": ["tag:exit-node"],
    "routes": {
      "0.0.0.0/0": ["tag:gateway"],
      "::/0": ["tag:gateway"]
    }
  },
  "randomizeClientPort": false
}
EOF

    # APPLIQUER LES BONNES PERMISSIONS
    echo "🔑 Setting correct permissions..."
    chown root:headscale "$HS_CONF" "${HS_CONF_DIR}/acl_policy.hujson"
    chmod 640 "$HS_CONF" "${HS_CONF_DIR}/acl_policy.hujson"
    
    # Vérifier que les permissions sont correctes
    echo "📋 Permissions vérifiées:"
    ls -la "$HS_CONF"
    ls -la "${HS_CONF_DIR}/acl_policy.hujson"
    
    echo "✅ Configuration updated!"
}

diagnose_headscale() {
    echo ""
    echo "📋 Headscale Diagnostics:"
    echo "========================"
    echo "Service status:"
    systemctl status headscale.service --no-pager -l 2>/dev/null || echo "Service not found"
    echo ""
    echo "Last 20 log lines:"
    journalctl -u headscale.service --no-pager -n 20 2>/dev/null || echo "No logs found"
    echo ""
    echo "Socket existence:"
    ls -la "$HS_SOCK" 2>/dev/null || echo "Socket not found"
    echo ""
    echo "Binary location:"
    ls -la "$HS_BIN" 2>/dev/null || echo "Binary not found"
    echo ""
    echo "Configuration file permissions:"
    ls -la "$HS_CONF" 2>/dev/null || echo "Config not found"
    echo ""
    echo "ACL policy permissions:"
    ls -la "${HS_CONF_DIR}/acl_policy.hujson" 2>/dev/null || echo "ACL policy not found"
    echo ""
    echo "Configuration content (first 20 lines):"
    head -20 "$HS_CONF" 2>/dev/null || echo "Config not found"
    echo ""
    echo "Configuration validation:"
    if [ -f "$HS_BIN" ]; then
        "$HS_BIN" -c "$HS_CONF" version 2>/dev/null || echo "❌ Configuration invalid"
    fi
}

restart_headscale() {
    echo "🔄 Restarting Headscale service..."
    
    # Vérifier les permissions avant de redémarrer
    if [ -f "$HS_CONF" ]; then
        echo "🔑 Checking permissions..."
        chown root:headscale "$HS_CONF" 2>/dev/null || true
        chmod 640 "$HS_CONF" 2>/dev/null || true
        chown root:headscale "${HS_CONF_DIR}/acl_policy.hujson" 2>/dev/null || true
        chmod 640 "${HS_CONF_DIR}/acl_policy.hujson" 2>/dev/null || true
        ls -la "$HS_CONF"
    fi
    
    systemctl daemon-reload
    systemctl restart headscale
    sleep 3
    
    if systemctl is-active --quiet headscale.service; then
        echo "✅ Headscale is now running!"
        echo ""
        echo "🔍 Service status:"
        systemctl status headscale.service --no-pager
        echo ""
        echo "🔗 Socket:"
        ls -la "$HS_SOCK" 2>/dev/null || echo "Socket not found"
        echo ""
        echo "📋 Test command:"
        headscale -c "$HS_CONF" users list 2>&1 | head -5
    else
        echo "⚠️  Headscale failed to start. Check logs:"
        journalctl -u headscale.service --no-pager -n 20
        echo ""
        echo "🔧 Manual test:"
        sudo -u headscale /usr/local/bin/headscale serve -c "$HS_CONF" 2>&1 | head -10
    fi
}

# ========== MAIN ==========
echo ""
echo "🔧 Headscale Config Fixer v1.1"
echo "============================================================"
echo ""

if [ "$1" = "--diagnose" ]; then
    diagnose_headscale
    exit 0
fi

if [ "$1" = "--restart" ]; then
    restart_headscale
    exit 0
fi

if [ "$1" = "--fix" ] || [ -f "$HS_CONF" ]; then
    fix_config
    echo ""
    read -rp "Restart Headscale service now? (y/N): " restart
    if [[ $restart =~ ^[Yy] ]]; then
        restart_headscale
    fi
    echo ""
    echo "✅ Fix completed!"
    echo "🔍 Run with --diagnose to verify"
    echo "🔧 Run with --restart to start the service"
    exit 0
fi

echo "Usage:"
echo "  sudo bash fix-headscale.sh --fix      Fix Headscale configuration"
echo "  sudo bash fix-headscale.sh --diagnose Run diagnostics"
echo "  sudo bash fix-headscale.sh --restart  Restart Headscale service"
echo ""
echo "If Headscale is not installed, run install-headscale.sh first."
exit 0
