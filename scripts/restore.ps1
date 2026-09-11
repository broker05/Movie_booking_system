# -----------------------------------------------------------------------------
# Movie Booking System - Production Disaster Recovery Restore Script (PowerShell)
# -----------------------------------------------------------------------------
# Usage: .\scripts\restore.ps1 [optional_path_to_backup_tar_gz]
# If no argument is provided, it automatically restores the latest backup!

param (
    [string]$BackupPath = ""
)

$ErrorActionPreference = "Stop"

$BACKUP_DIR = "./backups"
$CONTAINER_NAME = "movie_booking_prod_db"
$DB_USER = "admin"
$DB_NAME = "movie_booking"

Write-Host "==================================================" -ForegroundColor Red
Write-Host "   PostgreSQL Disaster Recovery RESTORE           " -ForegroundColor Red
Write-Host "==================================================" -ForegroundColor Red

# 1. Determine which backup file to restore
if (-not $BackupPath) {
    $latestBackup = Get-ChildItem -Path $BACKUP_DIR -Filter "backup_*.tar.gz" | Sort-Object CreationTime -Descending | Select-Object -First 1
    if (-not $latestBackup) {
        Write-Host "ERROR: No backup archives found in $BACKUP_DIR!" -ForegroundColor Red
        exit 1
    }
    $BackupPath = $latestBackup.FullName
}

if (-not (Test-Path $BackupPath)) {
    Write-Host "ERROR: Backup file not found at: $BackupPath" -ForegroundColor Red
    exit 1
}

Write-Host "Target backup file: $BackupPath" -ForegroundColor Yellow

# 2. Check if target container is running
$containerRunning = docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" --format "{{.Names}}"
if (-not $containerRunning) {
    Write-Host "ERROR: Target container '$CONTAINER_NAME' is not running!" -ForegroundColor Red
    exit 1
}

# 3. Extract the SQL file to a temporary location
$tempExtractDir = "$BACKUP_DIR/_temp_restore"
if (Test-Path $tempExtractDir) { Remove-Item -Recurse -Force $tempExtractDir }
New-Item -ItemType Directory -Path $tempExtractDir | Out-Null

Write-Host "Decompressing archive..." -ForegroundColor Yellow
tar -xzf $BackupPath -C $tempExtractDir

$sqlFile = (Get-ChildItem -Path $tempExtractDir -Filter "*.sql" | Select-Object -First 1).FullName
if (-not $sqlFile) {
    Write-Host "ERROR: No .sql file found inside the archive!" -ForegroundColor Red
    Remove-Item -Recurse -Force $tempExtractDir
    exit 1
}

Write-Host "Restoring database [$DB_NAME] in container [$CONTAINER_NAME]..." -ForegroundColor Yellow

# 4. Stream the SQL commands into psql inside the container
# Use cmd /c redirection to feed raw SQL into docker exec -i stdin
cmd /c "docker exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME < `"$sqlFile`""

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Database restore encountered an error (exit code $LASTEXITCODE)" -ForegroundColor Red
    Remove-Item -Recurse -Force $tempExtractDir
    exit 1
}

# 5. Clean up temporary extracted file
Remove-Item -Recurse -Force $tempExtractDir

Write-Host "==================================================" -ForegroundColor Green
Write-Host "   Database Successfully Restored!                " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
