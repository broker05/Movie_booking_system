# Database Disaster Recovery & Backups

## 1. The Core Reality: Code vs. State
* **Code & Containers are Disposable:** If a frontend or backend container dies, Docker or Kubernetes recreates it from an image in seconds.
* **Database State is Irreplaceable:** If the database volume is deleted or corrupted, customer records, tickets, and transactions are gone forever.
* **The "3-2-1" Backup Rule:**
  * **3** copies of critical data.
  * **2** different storage media (e.g. local server disk + cloud object storage).
  * **1** copy stored offsite (e.g. AWS S3 or Cloudflare R2).

---

## 2. Logical Backup (`pg_dump`) vs. Raw Volume Copy
* **Why not copy `/var/lib/postgresql/data`?** 
  PostgreSQL writes data to disk continuously. Copying raw database files while the database is running results in partial, corrupted writes.
* **What `pg_dump` does:**
  It opens a read-only transaction snapshot and exports all database tables and rows as pure, clean SQL text statements (`CREATE TABLE`, `INSERT INTO`). Even if users are booking tickets during the dump, the backup is 100% consistent.

---

## 3. The 6-Point Mental Checklist for Any Backup Script

Whenever you write or review a backup script (in Bash, PowerShell, Python, or a Docker sidecar), remember this checklist:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   THE BACKUP SCRIPT CHECKLIST                          │
│                                                                        │
│  1. Security First      ➔ Add backups/ & *.sql to .gitignore           │
│  2. Fail-Fast Check     ➔ Verify container/DB is alive before dumping  │
│  3. Unique Timestamps   ➔ backup_YYYY-MM-DD_HH-mm-ss (no overwrites)   │
│  4. Clean Overwrite     ➔ Use --clean --if-exists in pg_dump           │
│  5. Compress & Delete   ➔ gzip to .sql.gz & delete raw uncompressed    │
│  6. Auto-Retention      ➔ Prune files older than 7 (or 30) days        │
└────────────────────────────────────────────────────────────────────────┘
```

### 1. Security First (`.gitignore`)
* Database dumps contain real customer passwords, emails, and financial data.
* Ensure `backups/`, `*.sql`, and `*.sql.gz` are in `.gitignore` so they are never committed to GitHub.

### 2. Pre-Flight Fail-Fast Check
* Always check if the database container is actively running before taking a dump.
* If the database is stopped and your script continues, it will produce an empty 0-byte file and silently fool you into thinking you have a backup.

### 3. Dynamic Timestamping in Filenames
* Never name your backup `backup.sql` or `backup_latest.sql`.
* Always append dynamic date and time (`backup_2026-09-11_12-30-00.sql`). This ensures each backup is unique and historical snapshots are preserved.

### 4. Use `--clean --if-exists` with `pg_dump`
* `--clean`: Adds `DROP TABLE` before every `CREATE TABLE` statement.
* `--if-exists`: Uses `DROP TABLE IF EXISTS` so the script doesn't crash if a table is missing during restore.
* Without these flags, restoring over an existing database will fail with *"relation already exists"* errors.

### 5. Compress Immediately & Delete Raw SQL
* SQL files are plain text with massive repetition (`INSERT INTO seats...`).
* `gzip` compresses SQL dumps by **85% to 90%** (e.g. 50MB becomes ~5MB).
* Always delete the raw uncompressed `.sql` file immediately after compression to save disk space.

### 6. Automated Retention Policy (Pruning)
* A daily backup script will leave 365 files on disk after one year.
* The script must automatically find and delete backups older than a set threshold (e.g. 7 or 30 days) so disk space never runs out.

---

## 4. The Restore Procedure (Disaster Recovery)

A backup is only an assumption until you prove you can restore from it.

### Tool Difference:
* **Backup Tool:** `pg_dump` (reads database ➔ writes SQL text).
* **Restore Tool:** `psql` (reads SQL text ➔ executes into database).

### How Restore Works:
```powershell
# Windows (via restore.ps1):
# 1. Unpacks .tar.gz to temporary .sql
# 2. Streams SQL commands into psql:
docker exec -i movie_booking_prod_db psql -U admin -d movie_booking < backup.sql
```

```bash
# Linux (via restore.sh):
# Streams decompressed SQL directly into psql without touching disk:
gunzip -c backup_2026-09-11.sql.gz | docker exec -i movie_booking_prod_db psql -U admin -d movie_booking
```

### Relational Database Wipeout: `DELETE` vs `TRUNCATE CASCADE`
* `DELETE FROM table;` fails if foreign keys reference those rows (referential integrity protection).
* `TRUNCATE TABLE table CASCADE;` is PostgreSQL's DDL command to instantly wipe a table and cascade down to empty all child tables referencing it.

---

## 5. How Production Backups Are Scheduled
* Scripts do not run themselves; an operating system scheduler triggers them.
* **Linux (Cloud VPS):** Linux `cron` runs `0 2 * * * /path/to/backup.sh` every morning at 2:00 AM.
* **Windows:** Windows Task Scheduler triggers `powershell.exe -File .\scripts\backup.ps1`.
* **Docker Sidecar:** A companion container running Alpine `crond` inside `docker-compose.prod.yml`.
