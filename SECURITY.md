# 🛡️ Security Policy

## Overview

Security is a top priority for this project. 

This repository provides reusable deployment configurations, scripts, and documentation for deploying **Laravel** applications using modern infrastructure components:

* **Containers:** Docker, Podman
* **Web Servers & Proxies:** FrankenPHP, Caddy, Nginx, Apache
* **Database:** MariaDB
* **Networking:** Cloudflare Tunnel

Because this repository contains deployment infrastructure and configuration templates, security vulnerabilities may impact container isolation, deployment automation, reverse proxy rules, environment configuration, network exposure, and production authentication.

---

## Supported Versions

Security fixes are applied exclusively to the latest commit on the `main` branch. This repository does not issue release-tagged security patches.

| Version / Branch | Supported | Notes |
| :--- | :---: | :--- |
| **Latest `main`** | ✅ | Always pull the latest changes before deploying. |
| **Older Commits** | ❌ | Historical commits and old branches receive no updates. |

---

## Reporting a Vulnerability

> [!IMPORTANT]
> **Please do not publicly disclose security vulnerabilities** through GitHub Issues, Pull Requests, or public discussions until the issue has been investigated and patched.

If you discover a security issue, please submit it privately using **GitHub’s Private Vulnerability Reporting** feature (via the **Security** tab of this repository).

### Information to Include
To help us triage and resolve the issue quickly, please include:

1. **Description:** Clear explanation of the vulnerability and its potential impact.
2. **Affected Component:** Specific file, script, container setup, or documentation (e.g., `docker/php/Caddyfile`, `scripts/deploy.sh`).
3. **Reproduction Steps:** Step-by-step instructions or a minimal Proof of Concept (PoC).
4. **Environment Context:** Affected commit hash, Docker engine version, or OS details.
5. **Mitigation:** Suggested fix or workaround (if available).

---

## 🚨 Secret Exposure Protocol

If you discover that an active production credential, API key, OAuth secret, database password, `APP_KEY`, Cloudflare token, or SSH private key has been accidentally committed to this repository:

1. **Report it privately immediately.**
2. **Do not copy, quote, or redistribute** the exposed secret in any public forum.
3. Include the **file path**, **commit hash**, and **type of secret** in your private report.

> [!CAUTION]
> Any credential exposed in a public commit must be treated as compromised and **revoked/rotated immediately**.

---

## 📋 Production Security Checklists

### 1. Pre-Deployment Verification
Before deploying an application to production using these configurations, verify that:

- [ ] `.env` is listed in `.gitignore` and **never committed**.
- [ ] `APP_DEBUG` is set to `false` in production.
- [ ] Production `APP_KEY`, database, and OAuth credentials are secure.
- [ ] Cloudflare Tunnel tokens and SSH keys are stored in a secure secret manager.
- [ ] The application is configured to strictly enforce HTTPS.
- [ ] Unnecessary database/container ports are not exposed to the public internet.
- [ ] Host and cloud firewall rules (e.g., Security Groups) restrict inbound traffic.
- [ ] Dependencies (Composer, NPM, Docker base images, Host OS) are up to date.
- [ ] Automated database and asset backups are configured and tested.

### 2. Container Hardening
When executing containerized environments (`docker-compose.yml` / Podman):

* **Privileges:** Avoid running containers as `root` unless explicitly necessary.
* **Port Binding:** The provided `docker-compose.yml` defaults to binding application ports to `127.0.0.1` so services are only exposed through a trusted reverse proxy or Cloudflare Tunnel.
* **Base Images:** Audit Dockerfiles and regularly pull updated base images (`frankenphp`, `mariadb`, `php`).
* **Volume Mounts:** Restrict host directory permissions mounted into containers.

---

## 📜 Deployment Automation

The deployment script (`scripts/deploy.sh`) automates the following production procedures:

1. Fetching recent changes from Git.
2. Rebuilding and restarting application containers.
3. Installing production Composer dependencies (`--no-dev`).
4. Running database migrations (`php artisan migrate --force`).
5. Clearing and rebuilding configuration, route, and view caches.

> [!WARNING]
> Always review `scripts/deploy.sh` line-by-line in a staging environment before running it on production servers.

---

## 🔒 Prohibited Repository Content

The following sensitive items **must never** be committed to this repository:

```text
├── .env / .env.production
├── APP_KEY values
├── Passwords & DB Credentials
├── Private SSH Keys (id_rsa, id_ed25519)
├── API Keys & OAuth Secrets
├── Cloudflare Tunnel Tokens
└── SSL/TLS Private Keys (*.key, *.pem)
