# Headscale Auto-Installer 🚀

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Headscale Version](https://img.shields.io/badge/Headscale-0.29.2-blue)](https://github.com/juanfont/headscale/releases)
[![UI Version](https://img.shields.io/badge/Headscale--UI-latest-green)](https://github.com/gurucomputing/headscale-ui)

> Scripts d'installation automatisée pour **Headscale** (serveur de coordination auto‑hébergé compatible Tailscale) sur **Linux**, **Windows** et **Docker**, avec **interface Web** intégrée.

Ces scripts permettent de déployer un serveur Headscale en quelques secondes, avec une configuration prête à l'emploi incluant **l'approbation automatique des routes LAN**, **une interface Web** et **un reverse proxy** sécurisé.

---

## ✨ Fonctionnalités

- **Multi‑OS** : Linux (systemd), Windows (Service Windows), **Docker**.
- **Interface Web** : **Headscale-UI** intégrée via Docker ou installation autonome.
- **Reverse proxy** : Caddy pré‑configuré pour exposer Headscale et l’UI sur le même domaine.
- **Installation propre** : Téléchargement du binaire officiel depuis GitHub avec **vérification des sommes de contrôle**.
- **Variables d’environnement et fichier `.env`** : Toutes les options peuvent être définies via des variables `HS_*` ou un fichier `.env`.
- **Backup automatique** : Sauvegarde de la configuration (`config.yaml`, `private.key`, `db.sqlite`, `acl_policy.hujson`) avant toute réinstallation ou mise à jour.
- **Vérifications pré‑installation** : Port disponible, espace disque (>100 Mo), connectivité Internet, OS compatible.
- **Mise à jour automatique** : Commande `--upgrade` (Linux) ou `-Upgrade` (Windows) pour passer à la dernière version.
- **Routage LAN automatique** : Politique ACL avec `autoApprovers` pour approuver automatiquement les routes.
- **Environnements multiples** : Support des profils `dev`, `prod` via `.env.<profil>`.
- **Interface de gestion intégrée** : Sous Linux, menu interactif pour gérer utilisateurs, nœuds et clés.
- **Production‑ready** : Configuration recommandée pour SQLite, préfixes IP Tailscale, service robuste.

---

## 📁 Structure du projet
```text
Headscale-Auto-Installer
├── install-headscale.sh          # Script Linux (Bash) v2.4
├── install-headscale.ps1         # Script Windows (PowerShell) v2.4
├── .env.example                  # Exemple de configuration
├── .env.dev                      # Exemple pour développement
├── .env.prod                     # Exemple pour production
├── docker/
│   ├── Dockerfile
│   ├── docker-compose.yml        # Inclut Headscale + UI + Caddy
│   ├── config/
│   │   ├── config.yaml
│   │   └── acl_policy.hujson
│   ├── caddy/
│   │   └── Caddyfile             # Reverse proxy pour Headscale + UI
│   └── scripts/
│       └── init.sh
├── scripts/
│   └── install-headscale-ui.sh   # Installation autonome de l'UI
└── README.md                     # Documentation complète
```

---

## 🛠️ Prérequis

### Linux
- Distribution supportée : Ubuntu (20.04+), Debian (11+), AlmaLinux/Rocky (8+), CentOS (7+), RHEL (7+), Fedora (34+), openSUSE (15+).
- Accès `root` ou `sudo`.
- Connexion Internet sortante.

### Windows
- Windows 10/11, Windows Server 2016+.
- PowerShell 5.1+.
- Exécution en tant qu'**Administrateur**.

### Docker
- Docker et Docker Compose installés.

---

## 🚀 Installation rapide

### Linux

**Installation interactive :**
```bash
wget -O install-headscale.sh https://raw.githubusercontent.com/votre-utilisateur/votre-repo/main/install-headscale.sh
sudo bash install-headscale.sh
```
**Installation automatique (non interactive) :**
```bash
sudo bash install-headscale.sh --auto \
  --serverurl https://hs.mondomaine.com \
  --port 8443 \
  --user admin \
  --basedomain internal.local \
  --dns1 1.1.1.1 \
  --dns2 9.9.9.9
```
**Avec environnement :**
```bash
sudo bash install-headscale.sh --env prod
```
**Mise à jour :**
```bash
sudo bash install-headscale.sh --upgrade
```
### Windows
**Téléchargement et exécution (PowerShell en Admin) :**
```pwsh
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/votre-utilisateur/votre-repo/main/install-headscale.ps1" -OutFile install-headscale.ps1
.\install-headscale.ps1
```
**Avec paramètres personnalisés :**
```pwsh
.\install-headscale.ps1 -ServerUrl "https://hs.mondomaine.com" -InitialUser "admin" -Port 8443 -BaseDomain "vpn.local" -Environment prod
```
**Mise à jour :**
```powershell
.\install-headscale.ps1 -Upgrade
```
### Docker (recommandé pour l'UI)
```bash
git clone https://github.com/votre-utilisateur/votre-repo.git
cd votre-repo/docker
cp .env.example .env
# Modifiez .env avec vos paramètres
docker-compose up -d
```
**Accès :**
- Headscale : https://hs.votredomaine.com
- UI : https://hs.votredomaine.com/web (ou https://hs-ui.votredomaine.com)

## 🌐 Interface Web (Headscale-UI)
L’interface Web vous permet de gérer vos utilisateurs, nœuds et clés sans ligne de commande.

### Avec Docker
Incluse dans le docker-compose.yml avec Caddy comme reverse proxy.
**Installation autonome (sans Docker)**
```bash
curl -fsSL https://raw.githubusercontent.com/votre-utilisateur/votre-repo/main/scripts/install-headscale-ui.sh | sudo bash
```
### Génération de l’API Key
```bash
# Linux natif
headscale apikeys create -e 9999d

# Docker
docker exec -it headscale headscale apikeys create -e 9999d
```
### Sécurisation
Par défaut, l’UI est publique. Ajoutez une authentification dans le reverse proxy :
**Caddy (Caddyfile) :**
```caddy
hs-ui.votredomaine.com {
    basicauth {
        admin $2a$14$...
    }
    reverse_proxy headscale-ui:8080
}
```
**Nginx :**
```nginx
location /web/ {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    alias /var/www/headscale-ui/;
}
```
## ⚙️ Variables d’environnement
|Variable|Description|Défaut|
|--------|-----------|------|
|HS_SERVER_URL|URL publique du serveur|IP publique|
|HS_PORT|Port d'écoute|8080|
|HS_USER|Utilisateur initial|admin|
|HS_BASE_DOMAIN|Domaine MagicDNS|headscale.internal|
|HS_DNS1|DNS primaire|1.1.1.1|
|HS_DNS2|DNS secondaire|1.0.0.1|
|HS_LISTEN_ADDR|Adresse d'écoute|0.0.0.0|
|HS_LOG_LEVEL|Niveau de log|info|
|HS_METRICS_PORT|Port Prometheus|9090|
|HS_VERSION|Version (Linux/Windows)|0.29.2|

## 🌐 Routage LAN automatique
Les scripts activent les autoApprovers pour :
  - Les nœuds avec tag:gateway voient leurs routes approuvées automatiquement.
  - Les nœuds avec tag:exit-node deviennent des nœuds de sortie.
  **Client :**
    ```bash
    tailscale up --login-server https://hs.mondomaine.com \
    --advertise-routes=192.168.1.0/24 \
    --advertise-tags=tag:gateway
    ```
## 🎮 Gestion post‑installation
  ### Linux – Menu interactif
  ```bash
  sudo bash install-headscale.sh
  ```
  Menu : utilisateurs, nœuds, clés, backup, upgrade, désinstallation.
  ### Commandes manuelles
  **Linux :**
  ```bash
  headscale -c /etc/headscale/config.yaml <commande>
  ```
  **Windows :**
  ```powershell
  & "C:\Program Files\Headscale\headscale.exe" -c "C:\ProgramData\Headscale\config.yaml" <commande>
  ```
  **Exemples :**
  ```bash
  headscale users list
  headscale users create mon_utilisateur
  headscale preauthkeys create --user mon_utilisateur --reusable --expiration 90d
  headscale nodes list
  ```
## 🔄 Mise à jour automatique
  --upgrade (Linux) / -Upgrade (Windows) :
  - Sauvegarde la configuration
  - Arrête le service
  - Télécharge la dernière version depuis GitHub
  - Vérifie l’intégrité
  - Remplace le binaire et redémarre

## 🧹 Désinstallation
**Linux :**
```bash
sudo bash install-headscale.sh --remove
```
**Windows : menu interactif ou manuellement.**
**Docker :**
```bash
docker-compose down -v
```

## 🔒 Sécurité et recommandations
- HTTPS : Utilisez un reverse proxy (Caddy, Nginx) pour terminer le TLS.
- Base de données : SQLite pour la plupart des usages. PostgreSQL pour les charges lourdes.
- Mises à jour : Utilisez régulièrement --upgrade pour les correctifs de sécurité.

## 📜 Licence
MIT © 2026 – Vous êtes libre d’utiliser, modifier et redistribuer.
