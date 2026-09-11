# -----------------------------------------------------------------------------
# Movie Booking System - Production Database Backup Script (Windows / PowerShell)
# -----------------------------------------------------------------------------
# Usage: .\scripts\backup.ps1

$ErrorActionPreference = "Stop"

$BACKUP_DIR = "./backups"
$TIMESTAMP = (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
$CONTAINER_NAME = "movie_booking_prod_db"
$DB_USER = "admin"
$DB_NAME = "movie_booking"
$RAW_SQL_FILE = "$BACKUP_DIR/backup_$TIMESTAMP.sql"
$ARCHIVE_FILE = "$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Automated PostgreSQL Disaster Recovery Backup  " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Ensure backup directory exists
if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null
    Write-Host "Created directory: $BACKUP_DIR" -ForegroundColor Yellow
}

# 2. Verify the production container is running
$containerRunning = docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" --format "{{.Names}}"
if (-not $containerRunning) {
    Write-Host "ERROR: Target container '$CONTAINER_NAME' is not running!" -ForegroundColor Red
    Write-Host "Please start the production stack first: docker compose -f docker-compose.prod.yml up -d" -ForegroundColor Yellow
    exit 1
}

Write-Host "Dumping database [$DB_NAME] from container [$CONTAINER_NAME]..." -ForegroundColor Green

# 3. Execute pg_dump and capture output
# --clean: Adds DROP TABLE before CREATE TABLE for clean overwrite during restore
# --if-exists: Prevents errors if tables don't exist yet
# Use cmd /c redirection to ensure raw UTF-8 byte stream without PowerShell 5 string alterations
cmd /c "docker exec -i $CONTAINER_NAME pg_dump -U $DB_USER -d $DB_NAME --clean --if-exists > $RAW_SQL_FILE"

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: pg_dump failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

# 4. Compress the dump file with native tar (gzip)
tar -czf $ARCHIVE_FILE -C $BACKUP_DIR "backup_$TIMESTAMP.sql"
Remove-Item $RAW_SQL_FILE

$fileSize = (Get-Item $ARCHIVE_FILE).Length / 1KB
Write-Host "Backup created: $ARCHIVE_FILE ($([Math]::Round($fileSize, 2)) KB)" -ForegroundColor Green

# 5. Retention policy: Prune backups older than 7 days
$threshold = (Get-Date).AddDays(-7)
$oldFiles = Get-ChildItem -Path $BACKUP_DIR -Filter "backup_*.tar.gz" | Where-Object { $_.CreationTime -lt $threshold }

if ($oldFiles) {
    $oldFiles | Remove-Item
    Write-Host "Pruned $($oldFiles.Count) backup(s) older than 7 days." -ForegroundColor Yellow
} else {
    Write-Host "Retention check: No backups older than 7 days to prune." -ForegroundColor Gray
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Backup Completed Successfully!                 " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
