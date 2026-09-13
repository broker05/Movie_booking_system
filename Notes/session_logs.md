## August 21, 2026 Session Log
- **What was built:** Created the monorepo folder structure, set up a PostgreSQL database using Docker Compose, initialized a Node.js environment, and successfully executed our first database migration using `node-pg-migrate` to create the complete database schema (`users`, `movies`, `seats`, `bookings`, `otp_verifications`).
- **What was taught/learned:** Learned how Docker Compose handles networking and volumes to persist data. Learned why migrations use Unix timestamps (chronological ordering) and the concept of `exports.up` (Do) vs `exports.down` (Undo) for database version control.
- **Status/Pending:** Phase 1 is officially 100% complete! The database schema is ready.
- **Open Questions:** Think about how our Express server (which we will build next) will need to communicate with this database. We will need to learn how to route HTTP requests next!

## 2026-09-01 Session Log
- **What was built:** 
  - Completed Phase 2: Built an Express server with industry-standard logging using Pino, pino-http, and pino-roll.
  - Initialized Git and configured `.gitignore` properly. Untracked `.agents` from git.
  - Created a database seed script (`backend/src/scripts/seed.js`) to generate realistic mock data (Movies and 60 seats per movie).
  - Built the `POST /api/bookings/initiate` endpoint.
  - Wrote a concurrency test script (`simulateRace.js`) to prove the race condition vulnerability.
  - Implemented Pessimistic Locking (`SELECT ... FOR UPDATE`) and database Transactions (`BEGIN`, `COMMIT`, `ROLLBACK`) to successfully solve the race condition.
- **What was taught/learned:** 
  - The difference between `pool.query` (single queries) and `pool.connect` (dedicated clients for transactions).
  - The Event Loop, Promises, and asynchronous concurrency in Node.js (how 100 requests can fire simultaneously without `await`).
  - The theory behind ACID transactions and why Row-Level Locks are necessary for high-traffic inventory systems.
  - Foreign Key constraints and why deletion order matters.
- **Status/Pending:** 
  - Phase 3 is 100% complete. We are currently sitting at the start of Phase 4.
- **Open Questions:** 
  - When we return, we will need to set up Google OAuth. Have you ever set up a Google Cloud Console project before, or should we walk through it together step-by-step?

## September 4-5, 2026 Session Log
- **What was built:**
  - Completed Phase 5: Built full integration test suites with Jest and Supertest (`health.test.js`, `auth.test.js`, `booking.concurrency.test.js`, `booking.verify.test.js`) — 4 test suites, 12 tests, 100% green.
  - Implemented environment-aware Pino logging with silent test output for clean CI/CD reports.
  - Created standardized documentation in `docs/`: `docs/ARCHITECTURE.md` (Dev Technical Flow, Client User Flow, Database ER Diagram) and `docs/API_REFERENCE.md` (complete API contract dictionary).
  - Built custom agent skills: `.agents/skills/plan-project/SKILL.md` (interactive modular vertical slice planner) and `.agents/skills/backend-standards/SKILL.md` (production backend boilerplate standards with fail-fast DB startup, ApiError/ApiResponse/asyncHandler).
  - Created `Notes/universal_architecture_prompt_template.md` for standalone AI prompts.
- **What was taught/learned:**
  - The AAA (Arrange - Act - Assert) testing pattern and test categories (Happy Path, Validation, Auth, Concurrency).
  - Mocking external APIs (`OAuth2Client`, `global.fetch`) and the theory of Monkey Patching prototype methods in memory.
  - Why Supertest injects in-memory requests rather than using live network ports.
  - Fail-fast database architecture (verifying DB pool before `app.listen()`).
  - Database entity modeling: why `Seats` to `Bookings` is 1-to-Many for historical audit records.
- **Status/Pending:**
  - Backend is 100% complete, fully tested, and documented.
  - Phase 5 is officially complete! Ready to start Phase 6 (React + Vite Frontend).
- **Open Questions:**
  - When we start the frontend, we will build a visual seat map. Do you have any preferences on UI styling (e.g. sleek dark cinema mode with glowing seat statuses)?

## September 8-9, 2026 Session Log
- **What was built:**
  - **Phase 7 Step 1 (Multi-Environment DB Isolation):** Created dedicated `movie_booking_test` database inside PostgreSQL Docker container. Updated `src/config/db.js` for dynamic `NODE_ENV` connection switching. Configured npm lifecycle hook `"pretest": "npm run migrate:test"` to automatically synchronize test database schema before Jest runs. Audited and completed teardown cleanup across all 6 test suites.
  - **Phase 7 Step 2 (Frontend Multi-Stage Dockerfile):** Created `frontend/Dockerfile` using two-stage architecture (Stage 1: `node:20-alpine` builder running `npm run build` -> `dist/`; Stage 2: `nginx:alpine` production runner). Created `frontend/nginx.conf` with SPA `try_files` routing fallback and static asset caching. Created `frontend/.dockerignore`. Built and verified `movie_booking_frontend:latest`.
  - **Phase 7 Step 3 (Backend Multi-Stage Hardened Dockerfile):** Refactored `backend/Dockerfile` into production multi-stage build. Stage 1 installs clean production dependencies (`npm ci --omit=dev`). Stage 2 sets `USER node` (unprivileged, non-root user) with `chown -R node:node /app` for least-privilege security hardening. Verified via `whoami`.
  - **Phase 7 Step 4 (Nginx Reverse Proxy & Full-Stack Orchestration):** Updated `frontend/nginx.conf` with `/api/` reverse proxy (`proxy_pass http://backend:5000` with real client IP headers). Created root `docker-compose.prod.yml` orchestrating `postgres` (with healthcheck and persistent volume `pgdata_prod`), `migration` (one-shot runner executing before backend), `backend`, and `frontend` on private `movie_network`. Exposed prod DB to port `5433` for DBeaver inspection. Tested full-stack flow live with Google OAuth authentication and seeded movie catalog.
  - **Documentation & Educational Notes:** Created comprehensive educational guide `Notes/multi_environment_db_isolation.md`.
- **What was taught/learned:**
  - **Database Instance vs Logical Database:** How a single PostgreSQL server container hosts multiple isolated databases (`movie_booking`, `movie_booking_test`).
  - **NPM Lifecycle Prefix Conventions:** How `pre<script>` and `post<script>` execute automatically (the pre-flight checklist pattern).
  - **Browser to Nginx Real-World Lifecycle:** Why React runs in the browser, why JSX compiles down to 3 static files (`index.html`, `.js`, `.css`), and why browsers cache hashed assets for 1 year (`Cache-Control`).
  - **Single Page Application (SPA) Routing Problem:** Why refreshing on `/my-bookings` returns 404 without Nginx's `try_files $uri $uri/ /index.html;`.
  - **Multi-Stage Docker Builds (Scaffolding vs Finished Building):** Why Node.js should never run in production for React apps, and how copying only `/dist` into Nginx reduces image size from ~1GB to ~25MB.
  - **Container Security & Least Privilege:** The danger of running containers as `root`, and how `USER node` restricts attack surfaces.
  - **Forward Proxy vs. Reverse Proxy:** How Nginx acts as a reverse proxy to eliminate CORS, hide internal services, and forward client IP headers.
  - **Docker Compose Pillars & Gotchas:** Service discovery via internal DNS (using service name `backend` instead of `localhost`), host vs container port mapping (`Host:Container`), ephemeral containers vs named persistent volumes (`pgdata` vs `pgdata_prod`), and how `healthcheck` (`pg_isready`) prevents startup race conditions.
  - **Migrations vs Seeds:** Why migrations are safe to automate on startup via one-shot tasks, but destructive seed scripts (`DELETE FROM ...`) must never run blindly on production restarts.
  - **Browser DevTools & Network Tab:** How to filter by `Fetch/XHR`, disable cache, inspect headers and JSON responses, and understand HTTP 304 (Not Modified).
- **Status/Pending:**
  - Phase 7 Steps 1 through 4 are **100% complete and verified live**!

## September 10-11, 2026 Session Log
- **What was built:**
  - **Phase 7 Step 5 (GitHub Actions CI Pipeline):** Created `.github/workflows/ci.yml` triggering on push/PR to `main`. Configured isolated job running Oxlint linter, frontend Vite production build check, and backend Jest integration tests against an ephemeral `postgres:15-alpine` service container with automatic healthchecks and migrations. Tested and verified passing 100% green on GitHub.
  - **Phase 7 Step 6 (Automated Database Disaster Recovery):** Created cross-platform backup and restore scripts ([scripts/backup.ps1](file:///d:/Projects/Movie_Booking_System/scripts/backup.ps1), [scripts/backup.sh](file:///d:/Projects/Movie_Booking_System/scripts/backup.sh), [scripts/restore.ps1](file:///d:/Projects/Movie_Booking_System/scripts/restore.ps1), [scripts/restore.sh](file:///d:/Projects/Movie_Booking_System/scripts/restore.sh)). Added `backups/` and `*.sql` to `.gitignore`. Successfully executed live Disaster Recovery Drill: simulated catastrophic data wipe via `TRUNCATE TABLE movies CASCADE;` (0 movies, 0 seats) and fully restored to 4 movies and 240 seats using `restore.ps1`.
  - **Educational Notes:** Created [Notes/ci.md](file:///d:/Projects/Movie_Booking_System/Notes/ci.md) and [Notes/backup.md](file:///d:/Projects/Movie_Booking_System/Notes/backup.md).
- **What was taught/learned:**
  - **CI Ephemeral Environments vs Local Environments:** Why tests run on sterile GitHub Linux VMs to catch "it works on my machine" and forgotten unpushed files.
  - **Docker on Windows vs Linux:** Why Windows requires Docker Desktop / WSL2 (lack of native Linux kernel namespaces/cgroups) while Linux runs native background systemd daemons.
  - **The 4 Pillars of Backups:** Security (`.gitignore`), fail-fast pre-flight checks, unique dynamic timestamps, `--clean --if-exists` flags, and gzip compression.
  - **Automated Retention:** Pruning backups older than 7 days to prevent disk exhaustion.
  - **`DELETE` vs `TRUNCATE CASCADE`:** How relational foreign keys block blind deletes unless cascaded.
- **Status/Pending:**
  - Phase 7 Steps 1 through 6 are **100% complete and verified**!
  - Next task: **Phase 7 Step 7 — Deployment Track A (Self-Hosted VPS)**.

## September 12-13, 2026 Session Log
- **What was built:**
  - **Phase 7 Step 7.1 (Cloud Infrastructure Provisioning):** Provisioned an Ubuntu 24.04 LTS VM on Microsoft Azure for Students (`movie-booking-server`) in East Asia with Public IP `104.208.80.230`, 2 vCPUs, and secured RSA SSH key pair.
  - **Phase 7 Step 7.2 (Server Hardening & Firewall):** Hardened server with UFW firewall (ports 22, 80, 443 open; port 5432 shielded). Configured Windows `icacls` permissions and created global SSH shortcut `ssh movie-server` in `~/.ssh/config`.
  - **Phase 7 Step 7.3 (Production Runtime & Optimization):** Configured 2GB Linux Swap Space on SSD. Installed official Docker Engine v29.8 and Docker Compose v5.5. Created automated provisioning script [scripts/setup-server.sh](file:///d:/Projects/Movie_Booking_System/scripts/setup-server.sh).
  - **Phase 7 Step 7.4 (Application Orchestration):** Cloned repo to VPS, configured production environment variables, spun up production container stack via `docker-compose.prod.yml`, diagnosed and resolved host volume permissions for non-root container logging (`USER node`), seeded database with 4 movies and 240 seats, verified live via public IP.
  - **Phase 7 Step 7.5 (Domain Name & DNS):** Claimed custom domain `rhrony05.me` via GitHub Student Pack (Namecheap). Mapped DNS `A Record` to `104.208.80.230` and `CNAME` for `www`. Verified global DNS propagation via Cloudflare and Google resolvers.
  - **Phase 7 Step 7.6 (SSL/TLS Encryption with Let's Encrypt):** Configured Nginx with HTTP-to-HTTPS 301 redirection on port 80 and SSL termination on port 443. Mounted `/etc/letsencrypt` in Docker Compose. Issued official certificates via Certbot for `rhrony05.me` and `www.rhrony05.me`. Verified live trusted HTTPS green padlock and successful production Google OAuth login!
  - **Architecture & Automation Artifacts:** Created [scripts/deploy.sh](file:///d:/Projects/Movie_Booking_System/scripts/deploy.sh) for 1-command deployments and created comprehensive reference guide [Notes/vps_deployment_and_ssl.md](file:///d:/Projects/Movie_Booking_System/Notes/vps_deployment_and_ssl.md) detailing the AI-driven 2-script pattern and developer playbook.
- **What was taught/learned:**
  - **VPS vs Brand:** VPS as a technical category (virtualized slice) vs AWS/Azure/DigitalOcean marketing names.
  - **VMs vs Containers:** Hardware virtualization with dedicated kernel vs process virtualization sharing the host kernel.
  - **The Universal 2-Script Pattern:** Separation between base machine hardening (`setup-server.sh`, run once) and application deployment (`deploy.sh`, run on every release).
  - **Bind Mounts vs Named Volumes:** Why bind mounts fail with non-root containers (`USER node`) and why named volumes manage permissions automatically.
  - **DNS Resolution & Caching:** Authoritative nameservers vs local ISP recursive resolvers, TTL caching, and testing host headers with `curl -H`.
  - **ACME Protocol & SSL:** Automated certificate issuance via Let's Encrypt and Certbot standalone verification.
- **Status/Pending:**
  - Phase 7 Steps 7.1 through 7.6 are **100% complete and verified live** at `https://rhrony05.me`!
  - Up next: **Phase 7 Step 7.7 (Automated Continuous Deployment - CD Pipeline via GitHub Actions)**.
- **Open Questions:**
  - For the CD pipeline, we will store our VPS SSH private key and IP inside GitHub Secrets. Have you ever configured GitHub Actions Secrets before?

