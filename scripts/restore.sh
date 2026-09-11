#!/bin/bash
# -----------------------------------------------------------------------------
# Movie Booking System - Production Disaster Recovery Restore Script (Linux)
# -----------------------------------------------------------------------------
# Usage: ./scripts/restore.sh [optional_path_to_backup_sql_gz]
# If no argument is provided, it automatically restores the latest backup!

set -e

BACKUP_DIR="./backups"
CONTAINER_NAME="movie_booking_prod_db"
DB_USER="admin"
DB_NAME="movie_booking"

echo "=================================================="
echo "   PostgreSQL Disaster Recovery RESTORE           "
echo "=================================================="

# 1. Determine backup file
BACKUP_FILE="$1"
if [ -z "$BACKUP_FILE" ]; then
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/backup_*.sql.gz 2>/dev/null | head -n 1)
    if [ -z "$BACKUP_FILE" ]; then
        echo "ERROR: No backup archives found in $BACKUP_DIR!" >&2
        exit 1
    fi
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file not found at: $BACKUP_FILE" >&2
    exit 1
fi

echo "Target backup: $BACKUP_FILE"

# 2. Check if container is running
if ! docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "ERROR: Target container '$CONTAINER_NAME' is not running!" >&2
    exit 1
fi

echo "Decompressing and streaming SQL into container [$CONTAINER_NAME]..."

# 3. Stream decompressed SQL directly into psql inside the container
# gunzip -c decompresses to stdout without creating temporary files on disk!
gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME"

echo "=================================================="
echo "   Database Successfully Restored!                "
echo "=================================================="
