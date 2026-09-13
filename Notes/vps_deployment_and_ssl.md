# Production VPS Deployment, DNS & SSL/TLS Reference Notes

This document provides a comprehensive retrospective of our self-hosted Linux VPS deployment (Phase 7: Track A), detailing the architectural lifecycle, the tools used, and every real-world problem and solution encountered.

---

## 1. What We Built (The End-to-End Architecture)

```
[User Browser: https://rhrony05.me]
                |
                v  (DNS: A Record resolves to 104.208.80.230)
  +-------------------------------------------------------------------+
  | Microsoft Azure Linux Virtual Machine (Ubuntu 24.04 LTS)          |
  | IP: 104.208.80.230 | 2 vCPUs | 1 GB RAM + 2 GB Swap               |
  | UFW Firewall: Only Ports 22 (SSH), 80 (HTTP), 443 (HTTPS) open    |
  |                                                                   |
  | +---------------------------------------------------------------+ |
  | | Docker Network: movie_network (Private Bridge)                | |
  | |                                                               | |
  | |  [Frontend / Nginx Container] (movie_booking_prod_frontend)   | |
  | |  • Port 80: HTTP -> 301 Redirect to HTTPS                    | |
  | |  • Port 443: Let's Encrypt SSL Termination (TLS 1.2/1.3)      | |
  | |  • Serves static Vite production bundle (HTML/CSS/JS)         | |
  | |  • Reverse Proxies `/api/` traffic internally to backend      | |
  | |                                                               | |
  | |  [Backend API Container] (movie_booking_prod_backend)         | |
  | |  • Node.js 20 Alpine running Express on port 5000 (Internal)  | |
  | |  • Non-root process (`USER node`, UID 1000)                   | |
  | |  • Pino structured logging with volume mount to host logs     | |
  | |                                                               | |
  | |  [Database Container] (movie_booking_prod_db)                 | |
  | |  • PostgreSQL 15 Alpine (Port 5432 Internal ONLY)             | |
  | |  • Persistent Docker Volume (`pgdata_prod`)                   | |
  | |  • Sealed from outside internet                               | |
  | +---------------------------------------------------------------+ |
  +-------------------------------------------------------------------+
```

---

## 2. Chronological Milestones Completed

### Milestone 1: Automated Database Disaster Recovery (Phase 7 Step 6)
* Created production automated backup scripts (`scripts/backup.sh`, `scripts/backup.ps1`) using `pg_dump` with gzip compression and 7-day retention pruning.
* Created automated restore scripts (`scripts/restore.sh`, `scripts/restore.ps1`) to rebuild from snapshots and completed a live recovery drill.

### Milestone 2: Cloud Infrastructure Provisioning (Azure VM)
* Activated Microsoft Azure for Students ($100 credit + 750 free VM hours).
* Selected **East Asia (Hong Kong)** region to adhere to Azure student policy restrictions.
* Provisioned **Ubuntu 24.04 LTS Gen2 VM** (`Standard_B2ats_v2`, 2 vCPUs, 1 GB RAM, 30 GB SSD).
* Generated and downloaded RSA SSH key pair (`movie-booking-server_key.pem`).
* Allocated public IPv4: `104.208.80.230`.

### Milestone 3: Server Hardening & Linux Environment Setup
* Configured Windows `icacls` to restrict `.pem` permissions to current user only.
* Connected via SSH and updated system packages (`apt-get update && apt-get upgrade -y`).
* Configured **UFW (Uncomplicated Firewall)**: allowed ports 22, 80, 443; shielded database port 5432.
* Allocated **2 GB Swap Space** on SSD with `vm.swappiness=10` to prevent Out-Of-Memory (OOM) crashes during Docker builds.
* Installed official **Docker Engine (v29.8)** and **Docker Compose Plugin (v5.5)**, adding `azureuser` to `docker` group.
* Codified this infrastructure-as-code into [`scripts/setup-server.sh`](../scripts/setup-server.sh).
* Created Windows global shortcut in `~/.ssh/config` for instant 1-command login: `ssh movie-server`.

### Milestone 4: Application Orchestration
* Cloned Git repository onto the VPS.
* Configured production `.env` (binding `FRONTEND_PORT=80`) and `backend/.env` (Google OAuth, Brevo, JWT).
* Spun up multi-container production stack via `docker compose -f docker-compose.prod.yml up --build -d`.
* Seeded database with 4 movies and 240 seats using `docker compose exec backend node src/scripts/seed.js`.
* Verified application live via raw IP: `http://104.208.80.230`.

### Milestone 5: Domain Name Mapping & DNS Configuration
* Claimed free 1-year custom domain **`rhrony05.me`** via GitHub Student Developer Pack (Namecheap `nc.me`).
* Configured DNS records in Namecheap Advanced DNS:
  * **`A Record`**: `@` ➔ `104.208.80.230` (TTL: Automatic / 1 min)
  * **`CNAME Record`**: `www` ➔ `rhrony05.me`
* Verified global DNS propagation using Cloudflare (`1.1.1.1`) and Google (`8.8.8.8`) DNS resolvers.

### Milestone 6: SSL/TLS Encryption with Let's Encrypt (HTTPS)
* Updated `frontend/nginx.conf`:
  * Port 80 server block: 301 Permanent Redirect to HTTPS + ACME challenge location.
  * Port 443 server block: SSL termination with TLS 1.2/1.3, session caching, and certificates from `/etc/letsencrypt`.
* Updated `docker-compose.prod.yml`: exposed port 443 and mounted `/etc/letsencrypt` as read-only.
* Installed Certbot on Ubuntu host and issued official certificates for `rhrony05.me` and `www.rhrony05.me` via `--standalone` challenge.
* Launched containers and verified trusted **Green Padlock** at `https://rhrony05.me`.
* Tested and verified production **Google OAuth login** live over HTTPS.

---

## 3. Real-World Problems Encountered & How We Solved Them

| # | Problem / Error Encountered | Why It Happened in the Real World | How We Diagnosed & Solved It |
|---|-----------------------------|-----------------------------------|------------------------------|
| **1** | **AWS SMS Verification Deadlock** | International SMS aggregators from AWS frequently get filtered or delayed by telecom carriers in Bangladesh. | Switched to **Microsoft Azure for Students** via the GitHub Student Pack, which uses academic email/GitHub authentication without SMS or credit card barriers. |
| **2** | **Azure Policy Error: `RequestDisallowedByAzure`** | Azure for Students applies an automated Azure Policy restricting free VMs to a specific whitelist of available global regions (excluding Central India). | Consulted Azure Policy assignments in portal, switched region to **East Asia (Hong Kong)** which had full quota for B-series VMs. |
| **3** | **OpenSSH `UNPROTECTED PRIVATE KEY FILE!` Error** | On Windows (NTFS), files inherit permissions from parent folders, allowing "Authenticated Users" read access. OpenSSH client strictly forbids keys accessible by other accounts. | Used Windows `icacls` to strip inherited permissions (`/inheritance:r`) and grant exclusive read access to current user (`/grant:r "$($env:USERNAME):(R)"`). |
| **4** | **Backend Container Crash: `EACCES: permission denied, open 'logs/app.1.log'`** | In `Dockerfile`, Node runs as non-root user `node` (UID 1000) for security. When mounting host `./backend/logs`, the host folder was owned by `azureuser` without write permissions for UID 1000. | Diagnosed using `docker logs movie_booking_prod_backend`. Fixed by running `sudo chown -R 1000:1000 backend/logs` on host and restarting container. |
| **5** | **DNS Stale Cache: `Server: GitHub.com` on `curl`** | While global DNS (Cloudflare 1.1.1.1) updated to our Azure IP, local ISP DNS resolver cached GitHub Pages' old IP with a 30-minute TTL. | Proved Nginx was ready using Host Header injection: `curl.exe -H "Host: rhrony05.me" -I http://104.208.80.230`, and flushed local cache with `ipconfig /flushdns`. |
| **6** | **Google OAuth Production Rejection** | Google OAuth security servers refuse authentication callbacks on plain HTTP URLs in production. | Resolved by issuing Let's Encrypt SSL certificates via Certbot and configuring Nginx SSL termination on port 443. |

---

## 4. Key Takeaways & Mental Models

1. **VPS is a Category, Not a Brand:** AWS EC2, Azure VM, DigitalOcean Droplets, and Linode all provide the exact same thing: a sliced virtual computer running Ubuntu Linux.
2. **VMs vs. Containers:** A VM virtualizes hardware (hypervisor, dedicated kernel). Containers virtualize processes (namespaces and cgroups sharing the single host kernel). Containers run inside the VM.
3. **Defense in Depth:** We secured our app across 3 distinct boundaries:
   * Network boundary: Azure Network Security Group + Linux UFW firewall.
   * Container boundary: PostgreSQL port 5432 closed to internet, private Docker bridge.
   * Process boundary: Node.js running as non-root `USER node` (UID 1000).
4. **DNS Caching Layers:** DNS changes propagate to authoritative nameservers in seconds, but local ISP recursive resolvers honor the TTL (Time-To-Live) cache window.
5. **SSL Automation (ACME):** Let's Encrypt requires domain ownership proof before issuance; standalone or webroot challenge automates this without paying hundreds of dollars to traditional certificate authorities.

---

## 5. The Universal Developer Playbook: The AI-Driven 2-Script Pattern

For any full-stack project (Node, Python, Go, Next.js) on any cloud provider (Azure, AWS, DigitalOcean, Hetzner), follow this exact standardized pattern:

```
[3 Human Inputs: VM IP + SSH Key, Domain Name, App Secrets]
                           │
                           ├── Script 1: setup-server.sh (Run ONCE on fresh VM)
                           │   • Hardens Ubuntu, creates 2GB Swap, sets UFW, installs Docker.
                           │
                           ├── Point DNS: Namecheap A Record -> VM Public IP
                           │
                           └── Script 2: deploy.sh (Run on first deploy & every update)
                               • Pulls latest code, requests Let's Encrypt SSL, starts Docker stack.
```

### The Division of Work (Human vs. AI)

| Phase | Human Responsibility | AI Responsibility |
| :--- | :--- | :--- |
| **Pre-Flight** | Write tests, ensure DB recovery scripts exist. | Enforce **Named Volumes** (`backend_logs:/app/logs`) instead of bind mounts so non-root users (`USER node`) never get permission errors. |
| **1. Provision** | Launch Ubuntu VM, create non-root `sudo` user (never use raw `root`), download `.pem` key, lock permissions with `icacls`, add alias to `~/.ssh/config`. | Provide exact SSH config block and `icacls` command syntax. |
| **2. Machine Setup** | SSH into server (`ssh my-server`). Run `sudo bash setup-server.sh`. | Generate idempotent `setup-server.sh` (Swap, UFW ports 22/80/443, Docker Engine & Compose). |
| **3. Domain DNS** | Buy domain (e.g. via Namecheap / Student Pack), point `A Record` to VM IP. | Provide exact DNS record parameters (`@` -> IP, `www` -> domain). |
| **4. App Deployment** | Clone repo, provide `.env` secrets, run `bash scripts/deploy.sh`. | Generate Nginx SSL configuration, update Compose port 443 + cert mounts, and write the 1-command `deploy.sh`. |
| **5. Continuous Deploy (CD)** | Push commits to `main`. | Write `.github/workflows/cd.yml` to SSH into the VM and trigger `deploy.sh` automatically. |

### Handling Private Repositories on VPS
When deploying private repositories, never use personal passwords or broad personal access tokens:
* **Industry Best Practice:** Use **GitHub Deploy Keys**.
* Generate an SSH key on the server (`ssh-keygen -t ed25519 -f ~/.ssh/github_deploy_key`).
* Add the public key to your repository under **GitHub ➔ Settings ➔ Deploy Keys** (Read-Only).
* Clone via `git clone git@github.com:user/repo.git`. The server pulls automatically forever with zero password prompts and complete isolation.
