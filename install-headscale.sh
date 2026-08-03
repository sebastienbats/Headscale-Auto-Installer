#!/bin/bash
# Headscale Auto-Installer v2.5.1 – Linux
# Correction : meilleure gestion du démarrage du service et diagnostics
# Licensed under MIT License

set -e

exiterr() { echo "❌ Error: $1" >&2; exit 1; }
exiterr2() { exiterr "Package installation failed. Check your package manager."; }
exiterr3() { exiterr "'yum install' failed."; }
exiterr4() { exiterr "'zypper install' failed."; }

# ========== VERSION ET CHEMINS ==========
HS_VERSION="0.29.2"
HS_CONF="/etc/headscale/config.yaml"
HS_CONF_DIR="/etc/headscale"
HS_DATA_DIR="/var/lib/headscale"
HS_RUN_DIR="/var/run/headscale"
HS_SOCK="/var/run/headscale/headscale.sock"
HS_BIN="/usr/local/bin/headscale"
HS_SVC="/etc/systemd/system/headscale.service"
HS_IPT_SVC="/etc/systemd/system/headscale-iptables.service"
HS_LOG="/var/log/headscale.log"

# ========== VARIABLES PAR DÉFAUT ==========
SERVER_URL=""
PORT="8080"
USERNAME="admin"
BASE_DOMAIN="headscale.internal"
DNS1="1.1.1.1"
DNS2="1.0.0.1"
LISTEN_ADDR="0.0.0.0"
LOG_LEVEL="info"
METRICS_PORT="9090"
AUTO=0
REMOVE=0
REINSTALL=0
UPGRADE=0
ENV_PROFILE=""
INSTALL_UI=0

# ========== CHARGEMENT .ENV ==========
load_env_file() {
    local env_file="$1"
    if [ -f "$env_file" ]; then
        echo "📂 Loading environment from $env_file"
        set -a
        source "$env_file"
        set +a
    fi
}

load_env_file ".env"

apply_profile_defaults() {
    local profile="$1"
    case "$profile" in
        dev)
            LOG_LEVEL="${LOG_LEVEL:-debug}"
            ;;
        prod)
            LOG_LEVEL="${LOG_LEVEL:-info}"
            ;;
        *)
            ;;
    esac
}

# ========== VÉRIFICATIONS PRÉ-INSTALLATION ==========
check_shell() {
    if readlink /proc/$$/exe 2>/dev/null | grep -q "dash"; then
        exiterr 'This installer needs to be run with "bash", not "sh".'
    fi
}

check_root() {
    if [ "$(id -u)" != 0 ]; then
        exiterr "This installer must be run as root. Try 'sudo bash $0'"
    fi
}

check_os() {
    if grep -qs "ubuntu" /etc/os-release; then
        os="ubuntu"
        os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
        if [[ -z "$os_version" || ! "$os_version" =~ ^[0-9]+$ || "$os_version" -lt 2004 ]]; then
            ubuntu_codename=$(grep 'UBUNTU_CODENAME' /etc/os-release | cut -d '=' -f 2 | tr -d '"')
            case "$ubuntu_codename" in
                focal) os_version=2004 ;;
                jammy) os_version=2204 ;;
                noble) os_version=2404 ;;
            esac
        fi
    elif [[ -e /etc/debian_version ]]; then
        os="debian"
        os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
        if [[ -z "$os_version" || ! "$os_version" =~ ^[0-9]+$ || "$os_version" -lt 11 ]]; then
            exiterr "This installer supports Debian 11+ only."
        fi
    elif grep -qs "AlmaLinux" /etc/redhat-release; then
        os="almalinux"
        os_version=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
        if [[ -z "$os_version" || ! "$os_version" =~ ^[0-9]+$ || "$os_version" -lt 8 ]]; then
            exiterr "This installer supports AlmaLinux 8+ only."
        fi
    elif grep -qs "Rocky" /etc/redhat-release; then
        os="rocky"
        os_version=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
        if [[ -z "$os_version" || ! "$os_version" =~ ^[0-9]+$ || "$os_version" -lt 8 ]]; then
            exiterr "This installer supports Rocky Linux 8+ only."
        fi
    elif grep -qs "CentOS" /etc/redhat-release; then
        os="centos"
        os_version=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
        if [[ -z "$os_version" || ! "$os_version" =~ ^[0-9]+$ || "$os_version" -lt 7 ]]; then
            exiterr "This installer supports CentOS 7+ only."
        fi
    elif grep -qs "Red Hat" /etc/redhat-release; then
        os="rhel"
        os_version=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
        if [[ -z "$os_version" || ! "$os_version" =~ ^[0-9]+$ || "$os_version" -lt 7 ]]; then
            exiterr "This installer supports RHEL 7+ only."
        fi
    elif grep -qs "Fedora" /etc/redhat-release; then
        os="fedora"
        os_version=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
        if [[ -z "$os_version" || ! "$os_version" =~ ^[0-9]+$ || "$os_version" -lt 34 ]]; then
            exiterr "This installer supports Fedora 34+ only."
        fi
    elif grep -qs "openSUSE" /etc/os-release; then
        os="opensuse"
        os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | cut -d '.' -f1)
        if [[ -z "$os_version" || ! "$os_version" =~ ^[0-9]+$ || "$os_version" -lt 15 ]]; then
            exiterr "This installer supports openSUSE Leap 15+ only."
        fi
    else
        exiterr "This installer seems to be running on an unsupported distribution. Supported distros are Ubuntu, Debian, AlmaLinux, Rocky Linux, CentOS, RHEL, Fedora and openSUSE."
    fi
}

check_required_commands() {
    local missing=()
    for cmd in wget curl systemctl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        exiterr "Missing required commands: ${missing[*]}. Please install them first."
    fi
}

check_internet_connectivity() {
    echo "🌐 Checking internet connectivity..."
    if ! curl -fsSL --connect-timeout 5 https://api.ipify.org >/dev/null 2>&1; then
        exiterr "No internet connectivity or unable to reach api.ipify.org. Check your network."
    fi
    if ! curl -fsSL --connect-timeout 5 https://github.com >/dev/null 2>&1; then
        exiterr "Cannot reach GitHub. Please check your network or firewall."
    fi
    echo "✅ Internet connectivity OK."
}

check_port_availability() {
    local port="$1"
    echo "🔍 Checking if port $port is available..."
    if ss -tulpn 2>/dev/null | grep -q ":$port "; then
        exiterr "Port $port is already in use. Please choose another port with --port or stop the conflicting service."
    fi
    echo "✅ Port $port is free."
}

check_disk_space() {
    local min_space_mb=100
    echo "💾 Checking disk space (need at least ${min_space_mb}MB)..."
    local avail_kb
    avail_kb=$(df --output=avail "$HS_DATA_DIR" 2>/dev/null | tail -1)
    if [ -z "$avail_kb" ]; then
        avail_kb=$(df --output=avail /var/lib 2>/dev/null | tail -1)
    fi
    if [ -z "$avail_kb" ] || [ "$avail_kb" -lt $((min_space_mb * 1024)) ]; then
        exiterr "Insufficient disk space. At least ${min_space_mb}MB required in /var/lib."
    fi
    echo "✅ Disk space OK ($((avail_kb / 1024)) MB available)."
}

# ========== FONCTIONS DE BACKUP ==========
backup_config() {
    local backup_dir="${HS_CONF_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
    if [ -d "$HS_CONF_DIR" ] && [ -f "$HS_CONF" ]; then
        echo "💾 Creating backup of current configuration in $backup_dir"
        mkdir -p "$backup_dir"
        cp -r "$HS_CONF_DIR/config.yaml" "$backup_dir/" 2>/dev/null || true
        cp -r "$HS_DATA_DIR/private.key" "$backup_dir/" 2>/dev/null || true
        cp -r "$HS_DATA_DIR/db.sqlite" "$backup_dir/" 2>/dev/null || true
        cp -r "$HS_CONF_DIR/acl_policy.hujson" "$backup_dir/" 2>/dev/null || true
        echo "✅ Backup completed at $backup_dir"
    else
        echo "ℹ️  No existing configuration found to backup."
    fi
}

stop_headscale() {
    systemctl stop headscale.service 2>/dev/null || true
}

# ========== FONCTIONS D'INSTALLATION ==========
install_packages() {
    local packages=()
    case "$os" in
        ubuntu|debian)
            packages=(wget curl)
            apt-get -y update || exiterr2
            apt-get -y install "${packages[@]}" || exiterr2
            ;;
        almalinux|rocky|centos|rhel|fedora)
            packages=(wget curl)
            if [[ "$os" == "fedora" ]]; then
                dnf -y install "${packages[@]}" || exiterr3
            else
                yum -y install epel-release || exiterr3
                yum -y install "${packages[@]}" || exiterr3
            fi
            ;;
        opensuse)
            packages=(wget curl)
            zypper -n install "${packages[@]}" || exiterr4
            ;;
    esac
}

download_headscale() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) hs_arch="amd64" ;;
        aarch64|arm64) hs_arch="arm64" ;;
        armv7l) hs_arch="armv7" ;;
        *) exiterr "Unsupported architecture: $arch" ;;
    esac
    hs_bin="headscale_${HS_VERSION}_linux_${hs_arch}"
    hs_base_url="https://github.com/juanfont/headscale/releases/download/v${HS_VERSION}"
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || exiterr "Failed to create temp directory."
    echo "📥 Downloading Headscale v${HS_VERSION} for linux/${hs_arch}..."
    wget -t 3 -T 30 -q "$hs_base_url/${hs_bin}" || curl -m 30 -fsSL "$hs_base_url/${hs_bin}" -o "$hs_bin" || {
        rm -rf "$tmp_dir"
        exiterr "Failed to download Headscale. Check your internet connection."
    }
    ( set -x; wget -t 3 -T 30 -q -O "$tmp_dir/checksums.txt" "$hs_base_url/checksums.txt" || curl -m 30 -fsSL "$hs_base_url/checksums.txt" -o "$tmp_dir/checksums.txt" ) 2>/dev/null || {
        rm -rf "$tmp_dir"
        exiterr "Failed to download checksums file."
    }
    echo "🔐 Verifying checksum..."
    (cd "$tmp_dir" && grep " $hs_bin$" checksums.txt | sha256sum -c -) >/dev/null 2>&1 || {
        rm -rf "$tmp_dir"
        exiterr "Headscale checksum verification failed."
    }
    mv "$tmp_dir/$hs_bin" "$HS_BIN"
    chmod 755 "$HS_BIN"
    rm -rf "$tmp_dir"
    echo "✅ Headscale binary installed successfully."
}

create_headscale_user() {
    if ! getent group headscale >/dev/null 2>&1; then
        groupadd --system headscale
    fi
    if ! id headscale >/dev/null 2>&1; then
        useradd --system --shell /usr/sbin/nologin \
            --gid headscale --home-dir "$HS_DATA_DIR" \
            --comment "Headscale daemon" headscale
    fi
}

create_directories() {
    mkdir -p "$HS_CONF_DIR" "$HS_DATA_DIR" "$HS_RUN_DIR"
    chown root:headscale "$HS_CONF_DIR"
    chmod 750 "$HS_CONF_DIR"
    chown headscale:headscale "$HS_DATA_DIR" "$HS_RUN_DIR"
    chmod 750 "$HS_DATA_DIR" "$HS_RUN_DIR"
    
    # Créer le répertoire pour les logs
    mkdir -p "$(dirname "$HS_LOG")"
    touch "$HS_LOG"
    chown headscale:headscale "$HS_LOG"
}

create_config() {
    cat > "$HS_CONF" <<EOF
# Headscale configuration
server_url: ${computed_server_url}
listen_addr: ${LISTEN_ADDR}:${PORT}
metrics_listen_addr: ${LISTEN_ADDR}:${METRICS_PORT}
grpc_listen_addr: ${LISTEN_ADDR}:50443
grpc_allow_insecure: false

# Private key path
private_key_path: ${HS_DATA_DIR}/private.key

# Database
db_type: sqlite3
db_path: ${HS_DATA_DIR}/db.sqlite

# Magic DNS base domain
base_domain: ${BASE_DOMAIN}

# DNS configuration
dns_config:
  nameservers:
    - ${DNS1}
${DNS2:+    - ${DNS2}}

# ACL policy path
acl_policy_path: ${HS_CONF_DIR}/acl_policy.hujson

# Log level
log_level: ${LOG_LEVEL}
log_format: text

# IP prefixes for nodes
ip_prefixes:
  - fd7a:115c:a1e0::/48
  - 100.64.0.0/10

# Default preauth key expiry
default_preauth_key_expiry: 24h

# Randomize client port
randomize_client_port: false
EOF

    cat > "${HS_CONF_DIR}/acl_policy.hujson" <<EOF
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
  }
}
EOF
    chown root:headscale "$HS_CONF" "${HS_CONF_DIR}/acl_policy.hujson"
    chmod 640 "$HS_CONF" "${HS_CONF_DIR}/acl_policy.hujson"
}

create_systemd_service() {
    cat > "$HS_SVC" <<EOF
[Unit]
Description=Headscale
After=network.target
Wants=network.target

[Service]
Type=simple
User=headscale
Group=headscale
ExecStart=${HS_BIN} serve -c ${HS_CONF}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5
WorkingDirectory=${HS_DATA_DIR}
StateDirectory=headscale
RuntimeDirectory=headscale
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true
PrivateTmp=true
StandardOutput=append:${HS_LOG}
StandardError=append:${HS_LOG}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

setup_firewall() {
    if systemctl is-active --quiet firewalld.service 2>/dev/null; then
        firewall-cmd -q --add-port="$PORT"/tcp
        firewall-cmd -q --permanent --add-port="$PORT"/tcp
    elif command -v iptables >/dev/null 2>&1; then
        iptables_path=$(command -v iptables)
        if [[ "$(systemd-detect-virt 2>/dev/null)" == "openvz" ]] && readlink -f "$(command -v iptables)" 2>/dev/null | grep -q "nft" && hash iptables-legacy 2>/dev/null; then
            iptables_path=$(command -v iptables-legacy)
        fi
        cat > "$HS_IPT_SVC" <<EOF
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$iptables_path -w 5 -I INPUT -p tcp --dport $PORT -j ACCEPT
ExecStop=$iptables_path -w 5 -D INPUT -p tcp --dport $PORT -j ACCEPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable --now headscale-iptables.service >/dev/null 2>&1
    fi
}

start_hs_service() {
    systemctl enable --now headscale.service >/dev/null 2>&1
}

wait_for_socket() {
    local i=0
    local max_attempts=60
    echo -n '⏳ Waiting for Headscale to start'
    while [ "$i" -lt "$max_attempts" ]; do
        if [ -S "$HS_SOCK" ]; then
            echo ""
            return 0
        fi
        echo -n '.'
        sleep 1
        i=$((i + 1))
        
        # Vérifier si le service est en échec
        if systemctl is-failed headscale.service 2>/dev/null; then
            echo ""
            echo "⚠️  Headscale service failed to start. Checking logs..."
            journalctl -u headscale.service --no-pager -n 20
            return 1
        fi
    done
    echo ""
    echo "⚠️  Timeout waiting for Headscale to start (${max_attempts}s)."
    echo "📋 Check service status: systemctl status headscale"
    echo "📋 Check logs: journalctl -u headscale.service -n 50"
    return 1
}

hs_cmd() {
    local retry=0
    local max_retries=5
    while [ "$retry" -lt "$max_retries" ]; do
        if [ -S "$HS_SOCK" ]; then
            "$HS_BIN" -c "$HS_CONF" "$@"
            return $?
        fi
        sleep 2
        retry=$((retry + 1))
    done
    echo "❌ Error: Headscale socket not available. Service may not be running." >&2
    return 1
}

create_initial_user() {
    echo "👤 Creating user '$USERNAME'..."
    hs_cmd users create "$USERNAME" 2>&1 || true
}

create_initial_key() {
    local user_id
    user_id=$(hs_cmd users list --name "$USERNAME" -o json 2>/dev/null | tr -d ' \n\t' | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    echo "=================================================================="
    echo "🔑 Initial pre-auth key"
    echo "   (user: $USERNAME, reusable, expires in 90 days)"
    echo "=================================================================="
    if [ -n "$user_id" ]; then
        hs_cmd preauthkeys create --user "$user_id" --reusable --expiration 90d 2>&1 || true
    else
        echo "⚠️  Warning: Could not find user '$USERNAME'. Skipping pre-auth key creation." >&2
        echo "Create a key manually: headscale -c $HS_CONF preauthkeys create --user $USERNAME --reusable --expiration 90d" >&2
    fi
    echo "=================================================================="
}

generate_api_key_for_ui() {
    if [ "$INSTALL_UI" = 1 ]; then
        echo "🔑 Generating API key for Headscale-UI..."
        local api_key
        api_key=$(hs_cmd apikeys create -e 9999d 2>/dev/null | tail -1)
        if [ -n "$api_key" ]; then
            echo "✅ API Key generated successfully!"
            echo "=================================================================="
            echo "🔐 Headscale-UI API Key (expires in 9999 days):"
            echo "$api_key"
            echo "=================================================================="
            echo "ℹ️  Use this key to configure your Headscale-UI instance."
            echo "   - If using Docker, set API_KEY environment variable."
            echo "   - If using standalone UI, configure it in the UI settings."
            echo "=================================================================="
        else
            echo "⚠️  Failed to generate API key. Please generate it manually:"
            echo "   headscale -c $HS_CONF apikeys create -e 9999d"
        fi
    fi
}

finish_setup() {
    echo ""
    echo "============================================================"
    if systemctl is-active --quiet headscale.service; then
        echo "✅ Installation completed successfully!"
    else
        echo "⚠️  Installation completed with warnings."
        echo "   Headscale service is not running. Check:"
        echo "   - systemctl status headscale"
        echo "   - journalctl -u headscale.service -n 50"
        echo ""
        echo "   Try starting it manually:"
        echo "   sudo systemctl start headscale"
    fi
    echo "============================================================"
    echo ""
    echo "🌐 Headscale server URL: $computed_server_url"
    echo ""
    echo "🔗 Connect a Tailscale client to this server:"
    echo "   tailscale up --login-server $computed_server_url --authkey <key>"
    echo ""
    echo "🛠️  Manage this server by running this script again:"
    echo "   sudo bash $0"
    
    if [ "$INSTALL_UI" = 1 ]; then
        echo ""
        echo "🌐 Headscale-UI available at:"
        echo "   https://hs.votredomaine.com/web (if using Docker with Caddy)"
        echo "   or http://$(hostname -I | awk '{print $1}')/web (standalone)"
        echo ""
        echo "🔑 Configure the UI with the API key generated above."
    fi
    
    echo ""
    if [ -z "$SERVER_URL" ] && check_ip "${public_ip:-$ip}" 2>/dev/null; then
        echo "⚠️  NOTE: Using plain HTTP. For production, set up a TLS reverse proxy"
        echo "   and re-run with --serverurl https://your-domain.example.com"
    fi
    echo "============================================================"
}

check_ip() {
    IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
    printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
}

# ========== FONCTION DE MISE À JOUR ==========
upgrade_headscale() {
    echo "🔍 Checking for updates..."
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/juanfont/headscale/releases/latest | grep -o '"tag_name":"v[^"]*"' | cut -d '"' -f 4 | sed 's/^v//')
    if [ -z "$latest_version" ]; then
        exiterr "Failed to fetch latest version from GitHub."
    fi
    echo "📊 Latest version: $latest_version, current installed version: $HS_VERSION"
    if [ "$latest_version" = "$HS_VERSION" ]; then
        echo "✅ You are already running the latest version."
        exit 0
    fi
    echo "⬆️  Upgrading from $HS_VERSION to $latest_version..."
    backup_config
    stop_headscale
    HS_VERSION="$latest_version"
    download_headscale
    start_hs_service
    echo "✅ Upgrade completed successfully to version $latest_version."
    echo "💾 Backup of previous configuration is kept in $HS_CONF_DIR/backup_*"
}

# ========== FONCTION D'INSTALLATION UI ==========
install_headscale_ui() {
    echo "🌐 Installing Headscale-UI..."
    UI_VERSION="latest"
    UI_DIR="/var/www/headscale-ui"
    NGINX_CONF="/etc/nginx/sites-available/headscale-ui"
    
    # Vérifier Nginx
    if ! command -v nginx >/dev/null 2>&1; then
        echo "📦 Installing Nginx..."
        case "$os" in
            ubuntu|debian)
                apt-get -y install nginx || exiterr "Failed to install Nginx."
                ;;
            almalinux|rocky|centos|rhel|fedora)
                yum -y install nginx || exiterr "Failed to install Nginx."
                ;;
            opensuse)
                zypper -n install nginx || exiterr "Failed to install Nginx."
                ;;
        esac
    fi
    
    echo "📥 Downloading Headscale-UI..."
    mkdir -p "$UI_DIR"
    wget -qO- "https://github.com/gurucomputing/headscale-ui/releases/download/${UI_VERSION}/headscale-ui.tar.gz" | tar -xz -C "$UI_DIR" || {
        exiterr "Failed to download Headscale-UI."
    }
    
    echo "⚙️  Configuring Nginx..."
    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name _;

    location /web/ {
        alias $UI_DIR/;
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/ 2>/dev/null || true
    systemctl reload nginx 2>/dev/null || systemctl restart nginx
    
    echo "✅ Headscale-UI installed successfully!"
    echo "🌐 Access UI at: http://$(hostname -I | awk '{print $1}')/web"
    echo "ℹ️  Don't forget to generate an API key: headscale -c $HS_CONF apikeys create -e 9999d"
}

# ========== DIAGNOSTIC ==========
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
    echo "Configuration:"
    headscale -c "$HS_CONF" version 2>/dev/null || echo "Cannot get version"
}

# ========== MAIN ==========
echo ""
echo "🚀 Headscale Auto-Installer v2.5.1"
echo "============================================================"
echo ""

# Vérifier si --diagnose a été passé
if [ "$1" = "--diagnose" ]; then
    diagnose_headscale
    exit 0
fi

check_shell
check_root
check_os
check_required_commands
check_internet_connectivity

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --auto) AUTO=1 ;;
        --env) shift; ENV_PROFILE="$1" ;;
        --serverurl) shift; SERVER_URL="$1" ;;
        --port) shift; PORT="$1" ;;
        --user) shift; USERNAME="$1" ;;
        --basedomain) shift; BASE_DOMAIN="$1" ;;
        --listenaddr) shift; LISTEN_ADDR="$1" ;;
        --dns1) shift; DNS1="$1" ;;
        --dns2) shift; DNS2="$1" ;;
        --loglevel) shift; LOG_LEVEL="$1" ;;
        --metricsport) shift; METRICS_PORT="$1" ;;
        --remove) REMOVE=1 ;;
        --reinstall) REINSTALL=1 ;;
        --upgrade) UPGRADE=1 ;;
        --install-ui) INSTALL_UI=1 ;;
        --diagnose) diagnose_headscale; exit 0 ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --auto                     Non-interactive mode"
            echo "  --env <dev|prod>           Environment profile"
            echo "  --serverurl <url>          Public server URL"
            echo "  --port <port>              HTTP listen port"
            echo "  --user <username>          Initial admin user"
            echo "  --basedomain <domain>      MagicDNS base domain"
            echo "  --dns1 <ip>                Primary DNS server"
            echo "  --dns2 <ip>                Secondary DNS server"
            echo "  --loglevel <level>         Log level (debug/info/warn/error)"
            echo "  --metricsport <port>       Prometheus metrics port"
            echo "  --remove                   Uninstall Headscale"
            echo "  --reinstall                Reinstall with backup"
            echo "  --upgrade                  Upgrade to latest version"
            echo "  --install-ui               Install Headscale-UI (standalone)"
            echo "  --diagnose                 Run diagnostics"
            echo "  --help                     Show this help"
            echo ""
            echo "Environment variables (in .env or .env.<profile>):"
            echo "  HS_SERVER_URL, HS_PORT, HS_USER, HS_BASE_DOMAIN,"
            echo "  HS_DNS1, HS_DNS2, HS_LOG_LEVEL, HS_METRICS_PORT"
            exit 0
            ;;
        *) exiterr "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
done

# Charger le fichier .env.<profil> s'il existe
if [ -n "$ENV_PROFILE" ]; then
    load_env_file ".env.${ENV_PROFILE}"
    apply_profile_defaults "$ENV_PROFILE"
    echo "🌍 Environment profile: $ENV_PROFILE"
fi

# Gestion --upgrade
if [ "$UPGRADE" = 1 ]; then
    if [ ! -f "$HS_BIN" ]; then
        exiterr "Headscale is not installed. Cannot upgrade."
    fi
    upgrade_headscale
    exit 0
fi

# Gestion --install-ui (installation autonome)
if [ "$INSTALL_UI" = 1 ]; then
    if [ ! -f "$HS_BIN" ]; then
        exiterr "Headscale must be installed before installing Headscale-UI."
    fi
    install_headscale_ui
    generate_api_key_for_ui
    exit 0
fi

# Vérification du port (sauf désinstallation)
if [ "$REMOVE" = 0 ]; then
    check_port_availability "$PORT"
fi

if [ "$REMOVE" = 0 ]; then
    check_disk_space
fi

# Désinstallation
if [ "$REMOVE" = 1 ]; then
    echo "🗑️  Removing Headscale..."
    stop_headscale
    systemctl disable headscale.service 2>/dev/null
    rm -f "$HS_SVC" "$HS_IPT_SVC"
    systemctl daemon-reload
    rm -rf "$HS_CONF_DIR" "$HS_DATA_DIR" "$HS_RUN_DIR"
    rm -f "$HS_BIN" "$HS_LOG"
    echo "✅ Headscale removed."
    exit 0
fi

# Menu interactif si déjà installé et pas de réinstallation forcée
if [ -f "$HS_BIN" ] && [ -f "$HS_CONF" ] && [ "$REINSTALL" = 0 ]; then
    echo "ℹ️  Headscale is already installed."
    echo "Select an option:"
    echo "  1) Add a new user"
    echo "  2) Delete a user"
    echo "  3) List users"
    echo "  4) List all nodes"
    echo "  5) Register a node"
    echo "  6) Delete a node"
    echo "  7) Create a pre-auth key"
    echo "  8) List pre-auth keys"
    echo "  9) Remove Headscale"
    echo " 10) Backup configuration"
    echo " 11) Reinstall Headscale (with backup)"
    echo " 12) Upgrade Headscale to latest version"
    echo " 13) Install Headscale-UI (standalone)"
    echo " 14) Generate API key for UI"
    echo " 15) Run diagnostics"
    echo " 16) Exit"
    read -rp "Option: " option
    case $option in
        1) read -rp "Username: " u; hs_cmd users create "$u" 2>&1 ;;
        2) read -rp "Username: " u; hs_cmd users delete "$u" 2>&1 ;;
        3) hs_cmd users list 2>&1 ;;
        4) hs_cmd nodes list 2>&1 ;;
        5) read -rp "Node key: " k; read -rp "User: " u; hs_cmd nodes register --key "$k" --user "$u" 2>&1 ;;
        6) read -rp "Node ID: " id; hs_cmd nodes delete --identifier "$id" 2>&1 ;;
        7) read -rp "User: " u; hs_cmd preauthkeys create --user "$u" --reusable --expiration 90d 2>&1 ;;
        8) read -rp "User: " u; hs_cmd preauthkeys list --user "$u" 2>&1 ;;
        9) stop_headscale; systemctl disable headscale.service 2>/dev/null; rm -f "$HS_SVC" "$HS_IPT_SVC"; systemctl daemon-reload; rm -rf "$HS_CONF_DIR" "$HS_DATA_DIR" "$HS_RUN_DIR"; rm -f "$HS_BIN" "$HS_LOG"; echo "✅ Headscale removed." ;;
        10) backup_config; exit 0 ;;
        11) stop_headscale; backup_config; echo "🔄 Proceeding with reinstallation..."; REINSTALL=1 ;;
        12) upgrade_headscale; exit 0 ;;
        13) install_headscale_ui; generate_api_key_for_ui; exit 0 ;;
        14) generate_api_key_for_ui; exit 0 ;;
        15) diagnose_headscale; exit 0 ;;
        16) exit 0 ;;
    esac
    if [ "$option" != "11" ]; then
        exit 0
    fi
fi

# Si réinstallation, backup déjà fait
if [ "$REINSTALL" = 1 ]; then
    stop_headscale
    backup_config
fi

# Nouvelle installation
echo "📦 Installing required packages..."
install_packages

# Configuration interactive si non auto et pas de paramètres
if [ "$AUTO" = 0 ] && [ -z "$SERVER_URL" ] && [ -z "$PORT" ] && [ -z "$USERNAME" ] && [ -z "$BASE_DOMAIN" ] && [ -z "$DNS1" ] && [ -z "$DNS2" ]; then
    echo ""
    echo "⚙️  Headscale server setup"
    echo ""
    read -rp "Do you want to use a domain name with HTTPS? (y/N): " response
    if [[ $response =~ ^[Yy] ]]; then
        read -rp "Enter HTTPS URL (e.g. https://hs.example.com): " srv_url
        if check_dns_name "$srv_url"; then
            srv_url="https://${srv_url}"
        fi
        until check_url "$srv_url" && printf '%s' "$srv_url" | grep -q '^https://'; do
            echo "Invalid URL. Enter a valid HTTPS URL."
            read -rp "HTTPS URL: " srv_url
            if check_dns_name "$srv_url"; then
                srv_url="https://${srv_url}"
            fi
        done
        SERVER_URL="${srv_url%/}"
    fi
    read -rp "TCP port [8080]: " p
    [[ -n "$p" ]] && PORT="$p"
    read -rp "Initial username [admin]: " u
    [[ -n "$u" ]] && USERNAME="$u"
    read -rp "MagicDNS base domain [headscale.internal]: " d
    [[ -n "$d" ]] && BASE_DOMAIN="$d"
    read -rp "Primary DNS server [1.1.1.1]: " d1
    [[ -n "$d1" ]] && DNS1="$d1"
    read -rp "Secondary DNS server [1.0.0.1]: " d2
    [[ -n "$d2" ]] && DNS2="$d2"
    read -rp "Install Headscale-UI (standalone)? (y/N): " ui_install
    if [[ $ui_install =~ ^[Yy] ]]; then
        INSTALL_UI=1
    fi
fi

# Calcul de l'URL du serveur
if [ -n "$SERVER_URL" ]; then
    computed_server_url="${SERVER_URL%/}"
else
    public_ip=$(curl -s -4 https://api.ipify.org 2>/dev/null || wget -qO- -4 https://api.ipify.org 2>/dev/null)
    if [ -z "$public_ip" ]; then
        public_ip=$(ip route get 1 | awk '{print $NF;exit}' 2>/dev/null)
    fi
    computed_server_url="http://${public_ip}:${PORT}"
fi

# Fonctions auxiliaires pour l'interactivité
check_dns_name() {
    FQDN_REGEX='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
    printf '%s' "$1" | tr -d '\n' | grep -Eq "$FQDN_REGEX"
}
check_url() {
    printf '%s' "$1" | tr -d '\n' | grep -Eq '^https?://[^[:space:]]+$'
}

echo ""
echo "📋 Configuration summary:"
echo "  Server URL: $computed_server_url"
echo "  Listen: $LISTEN_ADDR:$PORT"
echo "  User: $USERNAME"
echo "  Base domain: $BASE_DOMAIN"
echo "  DNS: $DNS1${DNS2:+, $DNS2}"
echo "  Log level: $LOG_LEVEL"
echo "  Metrics port: $METRICS_PORT"
if [ "$INSTALL_UI" = 1 ]; then
    echo "  Headscale-UI: Yes (standalone)"
fi
echo ""

read -rp "Proceed with installation? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy] ]]; then
    echo "Installation cancelled."
    exit 0
fi

download_headscale
create_headscale_user
create_directories
create_config
create_systemd_service
setup_firewall
start_hs_service

if wait_for_socket; then
    create_initial_user
    create_initial_key
    if [ "$INSTALL_UI" = 1 ]; then
        install_headscale_ui
        generate_api_key_for_ui
    fi
else
    echo ""
    echo "⚠️  Warning: Headscale service did not start properly."
    echo ""
    echo "📋 Diagnostics information:"
    echo "=========================="
    systemctl status headscale.service --no-pager 2>/dev/null
    echo ""
    echo "📋 Last 10 log lines:"
    journalctl -u headscale.service --no-pager -n 10 2>/dev/null
    echo ""
    echo "🔧 Try manually starting the service:"
    echo "   sudo systemctl start headscale"
    echo ""
    echo "🔧 For more details, run:"
    echo "   sudo bash $0 --diagnose"
fi

finish_setup
