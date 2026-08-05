#!/bin/bash
# Headscale Config Fixer v1.15 – Configuration DERP public + tagOwners
# Licensed under MIT License

set -e

exiterr() { echo "❌ Error: $1" >&2; exit 1; }

HS_CONF="/etc/headscale/config.yaml"
HS_CONF_DIR="/etc/headscale"
HS_DATA_DIR="/var/lib/headscale"
HS_RUN_DIR="/var/run/headscale"
HS_SOCK="/var/run/headscale/headscale.sock"
HS_BIN="/usr/local/bin/headscale"

fix_config() {
    echo "🔧 Fixing Headscale configuration (DERP public + tagOwners)..."
    if [ ! -f "$HS_BIN" ]; then
        exiterr "Headscale is not installed."
    fi
    systemctl stop headscale 2>/dev/null || true
    mkdir -p "$HS_DATA_DIR" "$HS_RUN_DIR" "$HS_CONF_DIR"
    chown headscale:headscale "$HS_DATA_DIR" "$HS_RUN_DIR"
    chmod 750 "$HS_DATA_DIR" "$HS_RUN_DIR"

    if [ -f "$HS_CONF" ]; then
        cp "$HS_CONF" "${HS_CONF}.old.$(date +%Y%m%d_%H%M%S)"
        echo "💾 Backup created."
    fi

    local server_url="http://$(hostname -I | awk '{print $1}'):8080"
    if [ -f "${HS_CONF}.old" ]; then
        server_url=$(grep "^server_url:" "${HS_CONF}.old" 2>/dev/null | awk '{print $2}' || echo "$server_url")
    fi

    cat > "$HS_CONF" <<EOF
server_url: ${server_url}
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090
grpc_listen_addr: 0.0.0.0:50443
grpc_allow_insecure: false

private_key_path: ${HS_DATA_DIR}/private.key

noise:
  private_key_path: ${HS_DATA_DIR}/noise_private.key

database:
  type: sqlite
  sqlite:
    path: ${HS_DATA_DIR}/db.sqlite
    write_ahead_log: true
    wal_autocheckpoint: 1000

dns:
  magic_dns: true
  base_domain: headscale.internal
  override_local_dns: true
  nameservers:
    global:
      - 1.1.1.1
      - 1.0.0.1

derp:
  server:
    enabled: false
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  auto_update: true

policy:
  mode: file
  path: ${HS_CONF_DIR}/acl_policy.hujson

log:
  level: info
  format: text

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48

default_preauth_key_expiry: 24h
EOF

    cat > "${HS_CONF_DIR}/acl_policy.hujson" <<'EOF'
{
  "groups": {
    "group:admins": ["admin@headscale.internal"]
  },
  "tagOwners": {
    "tag:gateway": ["group:admins"],
    "tag:exit-node": ["group:admins"]
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

    chown root:headscale "$HS_CONF" "${HS_CONF_DIR}/acl_policy.hujson"
    chmod 640 "$HS_CONF" "${HS_CONF_DIR}/acl_policy.hujson"
    echo "✅ Configuration updated with DERP public + tagOwners."
}

diagnose_headscale() {
    echo ""
    echo "📋 Headscale Diagnostics:"
    echo "========================"
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
    echo "DERP section:"
    grep -A 5 "^derp:" "$HS_CONF" 2>/dev/null || echo "DERP section not found"
}

restart_headscale() {
    echo "🔄 Restarting Headscale..."
    mkdir -p "$HS_RUN_DIR"
    chown headscale:headscale "$HS_RUN_DIR"
    chmod 750 "$HS_RUN_DIR"
    systemctl daemon-reload
    systemctl restart headscale
    sleep 5
    systemctl status headscale --no-pager
    ls -la "$HS_SOCK" 2>/dev/null || echo "Socket not found"
}

case "$1" in
    --fix)   fix_config ;;
    --diagnose) diagnose_headscale ;;
    --restart) restart_headscale ;;
    *) echo "Usage: $0 --fix|--diagnose|--restart" ;;
esac
