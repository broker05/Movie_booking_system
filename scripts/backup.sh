#!/bin/bash
# -----------------------------------------------------------------------------
# Movie Booking System - Production Database Backup Script (Linux / Bash)
# -----------------------------------------------------------------------------
# Usage: ./scripts/backup.sh
# Can be scheduled in Linux crontab:
# 0 2 * * * /path/to/Movie_Booking_System/scripts/backup.sh >> /var/log/mb_backup.log 2>&1

set -e # Exit immediately if any command fails

BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
CONTAINER_NAME="movie_booking_prod_db"
DB_USER="admin"
DB_NAME="movie_booking"
ARCHIVE_FILE="$BACKUP_DIR/backup_$TIMESTAMP.sql.gz"

echo "=================================================="
echo "   Automated PostgreSQL Disaster Recovery Backup  "
echo "=================================================="

# 1. Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# 2. Verify target container is running
if ! docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "ERROR: Target container '$CONTAINER_NAME' is not running!" >&2
    exit 1
fi

echo "Dumping database [$DB_NAME] from container [$CONTAINER_NAME]..."

# 3. Stream pg_dump directly into gzip compression
# --clean: Adds DROP TABLE before CREATE TABLE for clean overwrite during restore
# --if-exists: Prevents errors if tables don't exist yet
docker exec -i "$CONTAINER_NAME" pg_dump -U "$DB_USER" -d "$DB_NAME" --clean --if-exists | gzip > "$ARCHIVE_FILE"

FILE_SIZE=$(du -h "$ARCHIVE_FILE" | cut -f1)
echo "Backup created: $ARCHIVE_FILE ($FILE_SIZE)"

# 4. Retention policy: Delete backups older than 7 days
find "$BACKUP_DIR" -type f -name "backup_*.sql.gz" -mtime +7 -delete
echo "Retention check: Pruned backups older than 7 days."

echo "=================================================="
echo "   Backup Completed Successfully!                 "
echo "=================================================="
