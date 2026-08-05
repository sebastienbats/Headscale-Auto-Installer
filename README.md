# Headscale Auto-Installer 🚀

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Headscale Version](https://img.shields.io/badge/Headscale-0.29.2-blue)](https://github.com/juanfont/headscale/releases)
[![UI Version](https://img.shields.io/badge/Headscale--UI-latest-green)](https://github.com/gurucomputing/headscale-ui)

> Scripts d'installation automatisée pour **Headscale** (serveur de coordination auto‑hébergé compatible Tailscale) sur **Linux**, **Windows (WSL)** et **Docker**, avec **interface Web** intégrée.

Ces scripts permettent de déployer un serveur Headscale en quelques secondes, avec une configuration prête à l'emploi incluant **l'approbation automatique des routes LAN**, **une interface Web** et **un reverse proxy** sécurisé.

---

## ✨ Fonctionnalités

- **Installation automatique** sur Linux avec systemd
- **Support Docker** avec Docker Compose (Headscale + UI + Caddy)
- **Interface Web** intégrée (Headscale-UI)
- **Reverse proxy** Caddy pré‑configuré
- **Variables d'environnement** et fichier `.env`
- **Backup automatique** avant réinstallation/mise à jour
- **Vérifications pré‑installation** (ports, disque, connectivité)
- **Mise à jour automatique** (`--upgrade`)
- **Routage LAN automatique** via `autoApprovers`
- **Environnements multiples** (`dev`, `prod`)
- **Diagnostics intégrés** (`--diagnose`)
- **Correction de configuration** (`fix-headscale.sh`)

---

## 📁 Structure du projet
```text
Headscale-Auto-Installer/
├── .env.example                  # Exemple de configuration (variables d’environnement)
├── .env.dev                      # Profil pour l’environnement de développement
├── .env.prod                     # Profil pour l’environnement de production
├── install-headscale.sh          # Script d’installation principal (Linux)
├── fix-headscale.sh              # Script de correction de configuration
├── README.md                     # Documentation complète du projet
└── docker/                       # Déploiement avec Docker
    ├── Dockerfile                # Construction de l’image Headscale
    ├── docker-compose.yml        # Orchestration Headscale + UI + Caddy
    ├── config/                   # Fichiers de configuration pour le conteneur
    │   ├── config.yaml           # Configuration Headscale (compatible v0.29.3+)
    │   └── acl_policy.hujson     # Politique ACL avec autoApprovers et randomizeClientPort
    ├── caddy/                    # Reverse proxy Caddy
    │   └── Caddyfile             # Routage vers Headscale et l’UI
    └── scripts/                  # Scripts d’initialisation du conteneur
        └── init.sh               # Création de l’utilisateur et de la clé pré‑authentifiée
```

---

## 🛠️ Prérequis

### Linux
- Distribution supportée : Ubuntu (20.04+), Debian (11+), AlmaLinux/Rocky (8+), CentOS (7+), RHEL (7+), Fedora (34+), openSUSE (15+).
- Accès `root` ou `sudo`.
- Connexion Internet sortante.

### Windows (WSL)
- Windows 10/11, Windows Server 2016+.

### Docker
- Docker et Docker Compose installés.

---

## 🚀 Installation rapide

### Linux

**Installation interactive :**
```bash
git clone https://github.com/sebastienbats/Headscale-Auto-Installer.git
cd Headscale-Auto-Installer
sudo bash install-headscale.sh
```
**Installation automatique (non interactive) :**
```bash
sudo bash install-headscale.sh --auto \
  --serverurl https://hs.mondomaine.com \
  --port 8443 \
  --user admin \
  --basedomain internal.local \
  --install-ui \
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
### Docker (recommandé pour l'UI)
```bash
git clone https://github.com/sebastienbats/Headscale-Auto-Installer.git
cd Headscale-Auto-Installer/docker
cp .env.example .env
# Modifiez .env avec vos paramètres
docker-compose up -d
```
**Accès :**
- Accès : https://hs.votredomaine.com/web (avec Docker) ou http://votre-ip/web (standalone)
- Génération de l'API Key :
  ```bash
  headscale -c /etc/headscale/config.yaml apikeys create -e 9999d
  ```

## 🛠️ Correction de configuration
Si Headscale ne démarre pas avec des erreurs de configuration :
```bash
# Télécharger et exécuter le script de correction
wget -O fix-headscale.sh https://raw.githubusercontent.com/sebastienbats/Headscale-Auto-Installer/main/fix-headscale.sh
sudo bash fix-headscale.sh --fix

# Diagnostics
sudo bash fix-headscale.sh --diagnose

# Redémarrer le service
sudo bash fix-headscale.sh --restart
```

## 🌐 Interface Web (Headscale-UI)
L’interface Web vous permet de gérer vos utilisateurs, nœuds et clés sans ligne de commande.

### Avec Docker
Incluse dans le docker-compose.yml avec Caddy comme reverse proxy.
### Installation autonome (sans Docker)
```bash
curl -fsSL https://raw.githubusercontent.com/sebastienbats/Headscale-Auto-Installer/main/scripts/install-headscale-ui.sh | sudo bash
```
### Génération de l’API Key
```bash
# Linux natif
headscale apikeys create -e 9999d

# Docker
docker exec -it headscale headscale apikeys create -e 9999d
```
### Sécurisation
Par défaut, l’UI est publique.
Ajoutez une authentification dans le reverse proxy :
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
|HS_USER|Utilisateur initial (doit contenir @)|admin@headscale.internal|
|HS_BASE_DOMAIN|Domaine MagicDNS|headscale.internal|
|HS_DNS1|DNS primaire|1.1.1.1|
|HS_DNS2|DNS secondaire|1.0.0.1|
|HS_LISTEN_ADDR|Adresse d'écoute|0.0.0.0|
|HS_LOG_LEVEL|Niveau de log|info|
|HS_METRICS_PORT|Port Prometheus|9090|
|HS_VERSION|Version (Linux/Windows)|0.29.3|

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
  **Exemples :**
  ```bash
  headscale users list
  headscale users create mon_utilisateur
  headscale preauthkeys create --user mon_utilisateur --reusable --expiration 90d
  headscale nodes list
  ```
## 🔄 Mise à jour automatique
  ```bash
  sudo bash install-headscale.sh --upgrade
  ```
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
**Docker :**
  ```bash
  docker-compose down -v
  ```

## 🔒 Sécurité et recommandations
- HTTPS : Utilisez un reverse proxy (Caddy, Nginx) pour terminer le TLS.
- Base de données : SQLite pour la plupart des usages. PostgreSQL pour les charges lourdes.
- Mises à jour : Utilisez régulièrement --upgrade pour les correctifs de sécurité.

## 🔧 Commandes utiles
```bash
# Gérer le service
sudo systemctl status headscale
sudo systemctl start headscale
sudo systemctl stop headscale

# Voir les logs
sudo journalctl -u headscale.service -n 50 -f

# Exécution manuelle pour capturer l’erreur
sudo -u headscale /usr/local/bin/headscale serve -c /etc/headscale/config.yaml 2>&1 | head -50

# Commandes Headscale
sudo -u headscale -c /etc/headscale/config.yaml users list
sudo -u headscale -c /etc/headscale/config.yaml nodes list
sudo -u headscale -c /etc/headscale/config.yaml preauthkeys create --user admin@headscale.internal --reusable --expiration 90d
# Arrêter / Démarrer
sudo systemctl stop headscale
sudo systemctl start headscale

# Lister les utilisateurs
sudo headscale -c /etc/headscale/config.yaml users list

# Créer un utilisateur
sudo headscale -c /etc/headscale/config.yaml users create nouveluser@headscale.internal

# Créer une clé
sudo headscale -c /etc/headscale/config.yaml preauthkeys create --user <id> --reusable --expiration 90d
```

## 📜 Licence
MIT © 2026 – Vous êtes libre d’utiliser, modifier et redistribuer.
