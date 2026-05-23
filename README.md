# Cloud Infrastructure Setup — Automated Deployment

This repository provides an automated, one-script provisioning process for a cloud-native stack on Ubuntu. The deployment includes a Python web service, HashiCorp Vault for secrets management, Nginx for reverse proxying, and a complete Prometheus and Grafana monitoring setup.

---

## System Architecture

```
Client (Port 80)
      │
      ▼
  [ Nginx ]  ──── Reverse Proxy / Ingress
      │
      ├── /            ──▶  Flask App       (127.0.0.1:5000)
      └── /dashboard/  ──▶  Grafana         (127.0.0.1:3000)

  [ HashiCorp Vault ]  ──── Secrets Manager (127.0.0.1:8200)
      └── Read by Flask app at startup

  [ Prometheus ]       ──── Metrics Scraper (127.0.0.1:9090)
      └── Scraped by Grafana
```

| Layer           | Component             | Port | Access                  |
| --------------- | --------------------- | ---- | ----------------------- |
| Ingress / Proxy | Nginx                 | 80   | Public                  |
| Application     | Python Flask          | 5000 | Via Nginx `/`           |
| Secrets Manager | HashiCorp Vault (dev) | 8200 | Internal only           |
| Metrics         | Prometheus            | 9090 | Internal only           |
| Dashboard       | Grafana               | 3000 | Via Nginx `/dashboard/` |

> **Important:** Vault is configured in **dev mode** (in-memory storage). Any saved secrets will be wiped if the server or Vault service restarts. This is designed for testing/academic purposes—avoid using this setup in production.

---

## System Requirements

- A fresh Ubuntu 22.04 or 24.04 instance
- SSH connection with a `sudo`-capable user
- Active internet connection to fetch packages

---

## Quick Start / Deployment

```bash
# 1. Download the deployment script
wget -O deploy.sh "https://raw.githubusercontent.com/davidspringean12/cloud-programming-exam/refs/heads/main/deploy.sh"

# 2. Make it executable
chmod +x deploy.sh

# 3. Run it
sudo ./deploy.sh
```

The setup script is completely automated. It will not prompt you for any inputs or manual configuration.

---

## Automated Workflow Explained

1. **Refreshes** system repositories and updates package indexes.
2. **Sets up Nginx** to act as our ingress controller and reverse proxy.
3. **Installs HashiCorp Vault** using the official HashiCorp APT repo.
4. **Initializes Vault in dev mode** and automatically captures the newly generated root token.
5. **Writes a secret** (`cloud-vault-secret`) securely into Vault's key-value store.
6. **Deploys Python 3, Flask, and hvac** (the necessary Python library for Vault).
7. **Scaffolds `app.py`** — a simple Flask application configured to retrieve the secret from Vault.
8. **Installs Prometheus and Grafana** directly from their official sources.
9. **Tweaks Grafana's settings** so it safely serves traffic on the `/dashboard/` sub-path.
10. **Generates Nginx configuration** to route traffic correctly to the Flask app and Grafana dashboard.
11. **Checks and reloads Nginx** to activate the new traffic rules.

---

## Validating the Setup

Once the script finishes, you should see:

```
==========================================
 Installation Completed Successfully!
==========================================

 Flask app:  http://localhost/
 Grafana:    http://localhost/dashboard/
 Vault UI:   http://localhost:8200/ui
==========================================
```

| Service   | URL                           | Expected                                          |
| --------- | ----------------------------- | ------------------------------------------------- |
| Flask App | `http://<your-ip>/`           | Loads the web app and displays the decrypted secret |
| Grafana   | `http://<your-ip>/dashboard/` | Grafana metrics UI (handled via Nginx ingress)    |
| Vault UI  | `http://<your-ip>:8200/ui`    | Official HashiCorp Vault Web UI                   |

---

## Project Disclaimers \& Limitations

- **Vault Dev Infrastructure**: Vault data vanishes on reboot. A real-world setup requires persistent storage and a proper auto-unseal mechanism.
- **Static Vault Token**: The Python app relies on the Vault token injected at deployment time. If you restart Vault manually, the token expires, breaking the app until you re-run the deployment.
- **Unencrypted Traffic (No SSL/TLS)**: Everything operates on plain HTTP. In production environments, Nginx should handle TLS termination with a valid SSL certificate.
- **Background Processes**: The Python app runs in the background (`&`), not via `systemd`. If it crashes, it won't auto-restart.
- **Grafana Routing constraints**: You must access Grafana via `http://<your-ip>/dashboard/`. Hitting port 3000 directly will result in broken redirects because it's configured behind a proxy.

---

## Project Files

```
.
├── deploy.sh       # Main autonomous deployment file
└── README.md       # Project documentation (this file)
```

> The `app.py` source code is built on-the-fly and is intentionally kept out of the Git repository.
