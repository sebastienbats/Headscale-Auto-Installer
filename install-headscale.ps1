# install-headscale.ps1 v2.4 – Windows
# Headscale Auto-Installer with .env, backup, pre-checks, upgrade, multi-env, UI
# Licensed under MIT License

param(
    [string]$ServerUrl,
    [int]$Port,
    [string]$InitialUser,
    [string]$BaseDomain,
    [string]$Dns1,
    [string]$Dns2,
    [string]$LogLevel,
    [int]$MetricsPort,
    [string]$EnvFile = ".env",
    [string]$Environment = "",
    [switch]$Reinstall,
    [switch]$Upgrade,
    [switch]$InstallUI
)

# ========== CHARGEMENT .ENV ==========
if (Test-Path $EnvFile) {
    Write-Host "📂 Loading environment from $EnvFile" -ForegroundColor Cyan
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            Set-Variable -Name $name -Value $value -Scope Global -Force
        }
    }
}

# Chargement .env.<Environment> si spécifié
if ($Environment) {
    $envProfileFile = ".env.$Environment"
    if (Test-Path $envProfileFile) {
        Write-Host "📂 Loading environment from $envProfileFile" -ForegroundColor Cyan
        Get-Content $envProfileFile | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]+)=(.*)') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                Set-Variable -Name $name -Value $value -Scope Global -Force
            }
        }
    } else {
        Write-Host "⚠️  Warning: Environment file $envProfileFile not found." -ForegroundColor Yellow
    }
    # Appliquer les valeurs par défaut selon le profil
    switch ($Environment) {
        "dev" {
            if (-not $LogLevel) { $Script:LogLevel = "debug" }
        }
        "prod" {
            if (-not $LogLevel) { $Script:LogLevel = "info" }
        }
        default {
            # Rien
        }
    }
}

# ========== VARIABLES PAR DÉFAUT ==========
$Script:Version = if ($env:HS_VERSION) { $env:HS_VERSION } else { "0.29.2" }
$Script:ListenAddr = if ($env:HS_LISTEN_ADDR) { $env:HS_LISTEN_ADDR } else { "0.0.0.0" }
$Script:Port = if ($env:HS_PORT) { [int]$env:HS_PORT } else { 8080 }
$Script:BaseDomain = if ($env:HS_BASE_DOMAIN) { $env:HS_BASE_DOMAIN } else { "headscale.internal" }
$Script:ServerUrl = if ($env:HS_SERVER_URL) { $env:HS_SERVER_URL } else { "" }
$Script:Dns1 = if ($env:HS_DNS1) { $env:HS_DNS1 } else { "1.1.1.1" }
$Script:Dns2 = if ($env:HS_DNS2) { $env:HS_DNS2 } else { "1.0.0.1" }
$Script:LogLevel = if ($env:HS_LOG_LEVEL) { $env:HS_LOG_LEVEL } else { "info" }
$Script:MetricsPort = if ($env:HS_METRICS_PORT) { [int]$env:HS_METRICS_PORT } else { 9090 }
$Script:InitialUser = if ($env:HS_USER) { $env:HS_USER } else { "admin" }

# Surcharge par paramètres (prioritaires)
if ($ServerUrl) { $Script:ServerUrl = $ServerUrl }
if ($Port) { $Script:Port = $Port }
if ($InitialUser) { $Script:InitialUser = $InitialUser }
if ($BaseDomain) { $Script:BaseDomain = $BaseDomain }
if ($Dns1) { $Script:Dns1 = $Dns1 }
if ($Dns2) { $Script:Dns2 = $Dns2 }
if ($LogLevel) { $Script:LogLevel = $LogLevel }
if ($MetricsPort) { $Script:MetricsPort = $MetricsPort }

# ========== VÉRIFICATIONS ==========
function Test-Administrator {
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "❌ Error: This script must be run as Administrator." -ForegroundColor Red
        Write-Host "   Right-click PowerShell and select 'Run as administrator'." -ForegroundColor Yellow
        exit 1
    }
}

function Test-InternetConnectivity {
    Write-Host "🌐 Checking internet connectivity..." -ForegroundColor Cyan
    try {
        $response = Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        Write-Host "✅ Internet connectivity OK." -ForegroundColor Green
    } catch {
        Write-Host "❌ Error: No internet connectivity or unable to reach api.ipify.org." -ForegroundColor Red
        exit 1
    }
    try {
        $response = Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    } catch {
        Write-Host "❌ Error: Cannot reach GitHub. Check your network or firewall." -ForegroundColor Red
        exit 1
    }
}

function Test-PortAvailability {
    param([int]$Port)
    Write-Host "🔍 Checking if port $Port is available..." -ForegroundColor Cyan
    $existing = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "❌ Error: Port $Port is already in use by process $($existing.OwningProcess)." -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Port $Port is free." -ForegroundColor Green
}

function Test-DiskSpace {
    param([string]$Path = "C:\")
    $minSpaceMB = 100
    Write-Host "💾 Checking disk space (need at least ${minSpaceMB}MB)..." -ForegroundColor Cyan
    $drive = Get-PSDrive -Name (Split-Path -Qualifier $Path)
    if ($drive.Free -lt ($minSpaceMB * 1MB)) {
        Write-Host "❌ Error: Insufficient disk space on drive $Path. At least ${minSpaceMB}MB required." -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Disk space OK ($([math]::Round($drive.Free / 1MB, 0)) MB available)." -ForegroundColor Green
}

function Test-WindowsVersion {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $version = [Version]$os.Version
    $major = $version.Major
    $build = $version.Build
    if ($major -lt 10 -or ($major -eq 10 -and $build -lt 14393)) {
        Write-Host "⚠️  Warning: This script is tested on Windows 10 1607+ and Windows Server 2016+." -ForegroundColor Yellow
        Write-Host "   Your version ($($os.Caption)) may work but is not officially supported." -ForegroundColor Yellow
    } else {
        Write-Host "✅ Windows version OK: $($os.Caption)" -ForegroundColor Green
    }
}

# ========== FONCTIONS DE BACKUP ==========
function Backup-Config {
    param($ConfigDir, $DataDir)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = Join-Path $ConfigDir "backup_$timestamp"
    if (Test-Path $ConfigDir) {
        Write-Host "💾 Creating backup of current configuration in $backupDir" -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        Copy-Item -Path (Join-Path $ConfigDir "config.yaml") -Destination $backupDir -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $DataDir "private.key") -Destination $backupDir -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $DataDir "db.sqlite") -Destination $backupDir -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $ConfigDir "acl_policy.hujson") -Destination $backupDir -ErrorAction SilentlyContinue
        Write-Host "✅ Backup completed at $backupDir" -ForegroundColor Green
    } else {
        Write-Host "ℹ️  No existing configuration found to backup." -ForegroundColor Yellow
    }
}

function Stop-HeadscaleService {
    Stop-Service -Name $HS_SERVICE_NAME -Force -ErrorAction SilentlyContinue
}

# ========== FONCTION DE MISE À JOUR ==========
function Update-Headscale {
    param($CurrentVersion)
    Write-Host "🔍 Checking for updates..." -ForegroundColor Cyan
    try {
        $latest = Invoke-WebRequest -Uri "https://api.github.com/repos/juanfont/headscale/releases/latest" -UseBasicParsing -ErrorAction Stop
        $json = $latest.Content | ConvertFrom-Json
        $latestVersion = $json.tag_name -replace '^v',''
        Write-Host "📊 Latest version: $latestVersion, current installed version: $CurrentVersion" -ForegroundColor Yellow
        if ($latestVersion -eq $CurrentVersion) {
            Write-Host "✅ You are already running the latest version." -ForegroundColor Green
            return
        }
        Write-Host "⬆️  Upgrading from $CurrentVersion to $latestVersion..." -ForegroundColor Cyan
        Backup-Config -ConfigDir $HS_CONF_DIR -DataDir $HS_DATA_DIR
        Stop-HeadscaleService
        $Script:Version = $latestVersion
        Download-HeadscaleBinary
        Start-Service -Name $HS_SERVICE_NAME
        Write-Host "✅ Upgrade completed successfully to version $latestVersion." -ForegroundColor Green
        Write-Host "💾 Backup of previous configuration is kept in $($HS_CONF_DIR)\backup_*" -ForegroundColor Yellow
    } catch {
        Write-Host "❌ Error: Failed to fetch latest version from GitHub: $_" -ForegroundColor Red
        exit 1
    }
}

function Download-HeadscaleBinary {
    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
    $hs_base_url = "https://github.com/juanfont/headscale/releases/download/v$($Script:Version)"
    $hs_bin_name = "headscale_${Script:Version}_windows_${arch}.exe"
    $hs_url = "$hs_base_url/$hs_bin_name"
    $checksum_url = "$hs_base_url/checksums.txt"
    Write-Host "📥 Downloading Headscale v$($Script:Version) for windows/$arch ..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $hs_url -OutFile "$env:TEMP\$hs_bin_name" -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "❌ Error: Failed to download Headscale. Check your internet connection." -ForegroundColor Red
        exit 1
    }
    Write-Host "🔐 Verifying checksum..." -ForegroundColor Cyan
    try {
        $checksums = Invoke-WebRequest -Uri $checksum_url -UseBasicParsing -ErrorAction Stop
        $checksum_line = $checksums.Content.Split("`n") | Where-Object { $_ -match $hs_bin_name }
        if ($checksum_line) {
            $expected_hash = $checksum_line.Split()[0]
            $actual_hash = (Get-FileHash "$env:TEMP\$hs_bin_name" -Algorithm SHA256).Hash.ToLower()
            if ($expected_hash -ne $actual_hash) {
                Write-Host "❌ Error: Checksum verification failed." -ForegroundColor Red
                exit 1
            }
            Write-Host "✅ Checksum verified." -ForegroundColor Green
        } else {
            Write-Host "⚠️  Warning: Could not find checksum for $hs_bin_name. Skipping verification." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️  Warning: Failed to download checksums. Skipping verification." -ForegroundColor Yellow
    }
    Move-Item -Force "$env:TEMP\$hs_bin_name" $HS_BIN
    Write-Host "✅ Headscale binary installed successfully." -ForegroundColor Green
}

# ========== FONCTION D'INSTALLATION UI ==========
function Install-HeadscaleUI {
    Write-Host "🌐 Installing Headscale-UI..." -ForegroundColor Cyan
    
    # Vérifier si le binaire Headscale existe
    if (-not (Test-Path $HS_BIN)) {
        Write-Host "❌ Error: Headscale must be installed before installing Headscale-UI." -ForegroundColor Red
        exit 1
    }
    
    # Télécharger Headscale-UI (version standalone pour Windows)
    $UI_DIR = "C:\ProgramData\HeadscaleUI"
    $UI_VERSION = "latest"
    
    Write-Host "📥 Downloading Headscale-UI..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $UI_DIR | Out-Null
    
    # Note: Headscale-UI est un site statique, nous le téléchargeons depuis GitHub
    $ui_download_url = "https://github.com/gurucomputing/headscale-ui/releases/download/${UI_VERSION}/headscale-ui.tar.gz"
    $ui_archive = "$env:TEMP\headscale-ui.tar.gz"
    
    try {
        Invoke-WebRequest -Uri $ui_download_url -OutFile $ui_archive -UseBasicParsing -ErrorAction Stop
        # Extraire l'archive (nécessite tar pour Windows ou un outil équivalent)
        if (Get-Command tar -ErrorAction SilentlyContinue) {
            tar -xzf $ui_archive -C $UI_DIR
        } else {
            # Utiliser 7-Zip si disponible
            if (Get-Command 7z -ErrorAction SilentlyContinue) {
                7z x $ui_archive -o"$UI_DIR" -y
            } else {
                Write-Host "⚠️  Warning: No extraction tool found. Please extract $ui_archive manually to $UI_DIR" -ForegroundColor Yellow
            }
        }
        Write-Host "✅ Headscale-UI installed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Warning: Failed to download Headscale-UI: $_" -ForegroundColor Yellow
        Write-Host "   You can manually download it from: $ui_download_url" -ForegroundColor Yellow
    }
    
    # Générer l'API Key
    Generate-APIKey
}

function Generate-APIKey {
    Write-Host "🔑 Generating API key for Headscale-UI..." -ForegroundColor Cyan
    try {
        $apiKey = & $HS_BIN -c $HS_CONF apikeys create -e 9999d 2>&1 | Select-Object -Last 1
        if ($apiKey -and $apiKey -notmatch "error") {
            Write-Host "✅ API Key generated successfully!" -ForegroundColor Green
            Write-Host "==================================================================" -ForegroundColor Yellow
            Write-Host "🔐 Headscale-UI API Key (expires in 9999 days):" -ForegroundColor Yellow
            Write-Host "$apiKey" -ForegroundColor White
            Write-Host "==================================================================" -ForegroundColor Yellow
            Write-Host "ℹ️  Use this key to configure your Headscale-UI instance." -ForegroundColor Cyan
            Write-Host "   - If using Docker, set API_KEY environment variable." -ForegroundColor Cyan
            Write-Host "   - If using standalone UI, configure it in the UI settings." -ForegroundColor Cyan
            Write-Host "==================================================================" -ForegroundColor Yellow
        } else {
            Write-Host "⚠️  Failed to generate API key. Please generate it manually:" -ForegroundColor Yellow
            Write-Host "   & `"$HS_BIN`" -c `"$HS_CONF`" apikeys create -e 9999d" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "⚠️  Failed to generate API key: $_" -ForegroundColor Yellow
        Write-Host "   Please generate it manually." -ForegroundColor Yellow
    }
}

# ========== MAIN ==========
Write-Host ""
Write-Host "🚀 Headscale Auto-Installer v2.4" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Exécution des vérifications
Test-Administrator
Test-InternetConnectivity
Test-WindowsVersion

# Chemins
$HS_BIN_DIR = "C:\Program Files\Headscale"
$HS_CONF_DIR = "C:\ProgramData\Headscale"
$HS_DATA_DIR = "C:\ProgramData\Headscale\data"
$HS_BIN = "$HS_BIN_DIR\headscale.exe"
$HS_CONF = "$HS_CONF_DIR\config.yaml"
$HS_SERVICE_NAME = "Headscale"

# Gestion --Upgrade
if ($Upgrade) {
    if (-not (Test-Path $HS_BIN)) {
        Write-Host "❌ Error: Headscale is not installed. Cannot upgrade." -ForegroundColor Red
        exit 1
    }
    Update-Headscale -CurrentVersion $Script:Version
    exit 0
}

# Gestion --InstallUI
if ($InstallUI) {
    if (-not (Test-Path $HS_BIN)) {
        Write-Host "❌ Error: Headscale must be installed before installing Headscale-UI." -ForegroundColor Red
        exit 1
    }
    Install-HeadscaleUI
    exit 0
}

# Vérifications (sauf si déjà installé)
if (-not (Test-Path $HS_BIN)) {
    Test-PortAvailability -Port $Script:Port
    Test-DiskSpace -Path "C:\"
}

# Menu si déjà installé
if (Test-Path $HS_BIN) {
    Write-Host "ℹ️  Headscale is already installed." -ForegroundColor Yellow
    Write-Host "Select an option:" -ForegroundColor Cyan
    Write-Host "  1) Reinstall (with backup)"
    Write-Host "  2) Uninstall"
    Write-Host "  3) Manage (run commands manually)"
    Write-Host "  4) Backup configuration only"
    Write-Host "  5) Upgrade to latest version"
    Write-Host "  6) Install Headscale-UI"
    Write-Host "  7) Generate API key for UI"
    Write-Host "  8) Exit"
    $choice = Read-Host "Select option"
    switch ($choice) {
        "1" {
            Stop-HeadscaleService
            Backup-Config -ConfigDir $HS_CONF_DIR -DataDir $HS_DATA_DIR
            Write-Host "🔄 Reinstalling..." -ForegroundColor Cyan
        }
        "2" {
            Write-Host "🗑️  Uninstalling Headscale..." -ForegroundColor Cyan
            Stop-HeadscaleService
            sc.exe delete $HS_SERVICE_NAME | Out-Null
            Remove-Item -Recurse -Force $HS_BIN_DIR -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $HS_CONF_DIR -ErrorAction SilentlyContinue
            Remove-NetFirewallRule -DisplayName "Headscale TCP *" -ErrorAction SilentlyContinue
            Write-Host "✅ Headscale uninstalled." -ForegroundColor Green
            exit 0
        }
        "3" {
            Write-Host "🛠️  Run commands manually:" -ForegroundColor Cyan
            Write-Host "   & `"$HS_BIN`" -c `"$HS_CONF`" <command>" -ForegroundColor White
            exit 0
        }
        "4" {
            Backup-Config -ConfigDir $HS_CONF_DIR -DataDir $HS_DATA_DIR
            exit 0
        }
        "5" {
            Update-Headscale -CurrentVersion $Script:Version
            exit 0
        }
        "6" {
            Install-HeadscaleUI
            exit 0
        }
        "7" {
            Generate-APIKey
            exit 0
        }
        default { exit 0 }
    }
}

if ($Reinstall) {
    Stop-HeadscaleService
    Backup-Config -ConfigDir $HS_CONF_DIR -DataDir $HS_DATA_DIR
}

# Création des dossiers
Write-Host "📁 Creating directories..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $HS_BIN_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $HS_CONF_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $HS_DATA_DIR | Out-Null

# Téléchargement
Download-HeadscaleBinary

# Calcul de l'URL du serveur
if ([string]::IsNullOrEmpty($Script:ServerUrl)) {
    try {
        $public_ip = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing -ErrorAction Stop).Content.Trim()
        $computed_server_url = "http://${public_ip}:$($Script:Port)"
    } catch {
        $computed_server_url = "http://localhost:$($Script:Port)"
    }
} else {
    $computed_server_url = $Script:ServerUrl
}

# Génération de la configuration
Write-Host "⚙️  Creating configuration..." -ForegroundColor Cyan
$configContent = @"
# Headscale configuration
server_url: ${computed_server_url}
listen_addr: $($Script:ListenAddr):$($Script:Port)
metrics_listen_addr: $($Script:ListenAddr):$($Script:MetricsPort)
grpc_listen_addr: $($Script:ListenAddr):50443
grpc_allow_insecure: false

# Private key path
private_key_path: ${HS_DATA_DIR}\private.key

# Database
db_type: sqlite3
db_path: ${HS_DATA_DIR}\db.sqlite

# Magic DNS base domain
base_domain: $($Script:BaseDomain)

# DNS configuration
dns_config:
  nameservers:
    - $($Script:Dns1)
$(if ($Script:Dns2) { "    - $($Script:Dns2)" })

# ACL policy path
acl_policy_path: ${HS_CONF_DIR}\acl_policy.hujson

# Log level
log_level: $($Script:LogLevel)
log_format: text

# IP prefixes for nodes
ip_prefixes:
  - fd7a:115c:a1e0::/48
  - 100.64.0.0/10

# Default preauth key expiry
default_preauth_key_expiry: 24h

# Randomize client port
randomize_client_port: false
"@
$configContent | Out-File -FilePath $HS_CONF -Encoding utf8

# ACL policy
$aclContent = @'
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
'@
$aclContent | Out-File -FilePath "$HS_CONF_DIR\acl_policy.hujson" -Encoding utf8

# Création du service Windows
Write-Host "🛠️  Creating Windows service..." -ForegroundColor Cyan
$serviceDescription = "Headscale - Self-hosted Tailscale coordination server"
$serviceParams = @{
    Name = $HS_SERVICE_NAME
    BinaryPathName = "`"$HS_BIN`" serve -c `"$HS_CONF`""
    DisplayName = $HS_SERVICE_NAME
    Description = $serviceDescription
    StartupType = "Automatic"
}

if (Get-Service -Name $HS_SERVICE_NAME -ErrorAction SilentlyContinue) {
    Stop-Service -Name $HS_SERVICE_NAME -Force -ErrorAction SilentlyContinue
    sc.exe delete $HS_SERVICE_NAME | Out-Null
    Start-Sleep -Seconds 2
}

New-Service @serviceParams
sc.exe failure $HS_SERVICE_NAME reset=86400 actions=restart/60000/restart/60000/restart/60000 | Out-Null

# Règle de pare-feu
Write-Host "🔥 Creating firewall rule..." -ForegroundColor Cyan
$ruleName = "Headscale TCP $($Script:Port)"
if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) {
    Remove-NetFirewallRule -DisplayName $ruleName
}
New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $Script:Port -Action Allow

# Démarrage du service
Write-Host "▶️  Starting Headscale service..." -ForegroundColor Cyan
Start-Service -Name $HS_SERVICE_NAME -ErrorAction Stop
Start-Sleep -Seconds 5

# Création utilisateur et clé
Write-Host "👤 Creating initial user '$($Script:InitialUser)'..." -ForegroundColor Cyan
& $HS_BIN -c $HS_CONF users create $Script:InitialUser 2>&1 | Out-Host

Write-Host "🔑 Creating pre-auth key..." -ForegroundColor Cyan
& $HS_BIN -c $HS_CONF preauthkeys create --user $Script:InitialUser --reusable --expiration 90d 2>&1 | Out-Host

# Installation de l'UI si demandée
if ($InstallUI) {
    Install-HeadscaleUI
}

# Fin
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "✅ Headscale installation completed successfully!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "🌐 Server URL: $computed_server_url" -ForegroundColor Cyan
Write-Host ""
Write-Host "🔗 Connect a Tailscale client to this server:" -ForegroundColor White
Write-Host "   tailscale up --login-server $computed_server_url --authkey <key>" -ForegroundColor Gray
Write-Host ""
Write-Host "🛠️  Manage Headscale:" -ForegroundColor White
Write-Host "   & `"$HS_BIN`" -c `"$HS_CONF`" <command>" -ForegroundColor Gray
Write-Host ""
Write-Host "📊 Service status:" -ForegroundColor White
Write-Host "   Get-Service $HS_SERVICE_NAME" -ForegroundColor Gray

if ($InstallUI) {
    Write-Host ""
    Write-Host "🌐 Headscale-UI installed!" -ForegroundColor Green
    Write-Host "   - Standalone version installed in C:\ProgramData\HeadscaleUI" -ForegroundColor Gray
    Write-Host "   - Configure your web server to serve this directory" -ForegroundColor Gray
    Write-Host "   - Or use Docker with the UI container included" -ForegroundColor Gray
}

Write-Host "============================================================" -ForegroundColor Green
