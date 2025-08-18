#!/bin/bash
set -e

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if SQL Server is responding
check_sql_server() {
    local attempt=$1
    log "Attempt $attempt: Checking if SQL Server is responding..."
    
    if /opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" -Q "SELECT 1" -C &>/dev/null; then
        return 0
    else
        return 1
    fi
}

log "=== Starting MSSQL Database Process ==="
log "Container startup time: $(date)"
log "Environment variables:"
log "  DB_NAME: ${DB_NAME:-TestDB (default)}"
log "  BACKUP_FILE: ${BACKUP_FILE:-not specified}"
log "  DO_RESTORE: ${DO_RESTORE:-false}"
log "  SA_PASSWORD: [HIDDEN]"

# Check if restore is requested
if [ "$DO_RESTORE" != "true" ]; then
    log "=== Normal startup mode ==="
    log "DO_RESTORE is not set to 'true', skipping restore process."
    log "SQL Server will start with existing database state or create a fresh database."
    log "To restore from backup, use: docker-compose --profile restore up"
    log "=== Exiting restore script ==="
    exit 0
fi

log "=== Restore mode activated ==="

# Validate backup file requirements
if [ -z "$BACKUP_FILE" ]; then
    log "ERROR: BACKUP_FILE environment variable is required for restore mode!"
    log "Please set BACKUP_FILE in your .env file or environment."
    log "Example: BACKUP_FILE=mybackup.bak"
    exit 1
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    log "ERROR: Backup file '$BACKUP_FILE' not found!"
    log "Available backup files:"
    ls -la /backups/ || log "No backup files found in /backups/"
    log "Please check your BACKUP_FILE path and ensure the file exists in the ./backups folder."
    exit 1
fi

# Wait until SQL Server is ready
log "=== Phase 1: Waiting for SQL Server to start ==="
log "This can take 2-4 minutes on Apple Silicon due to x86_64 emulation..."

attempt=1
start_time=$(date +%s)

while ! check_sql_server $attempt; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $elapsed -gt 300 ]; then
        log "ERROR: SQL Server failed to start within 5 minutes!"
        log "This might indicate a configuration problem."
        log "Check your SA_PASSWORD complexity requirements."
        exit 1
    fi
    
    log "Still waiting... (attempt $attempt, elapsed: ${elapsed}s)"
    sleep 5
    attempt=$((attempt + 1))
done

end_time=$(date +%s)
elapsed=$((end_time - start_time))
log "SUCCESS: SQL Server is up and responding! (took ${elapsed}s)"

# Extract database name and backup file from env
DB_NAME=${DB_NAME:-TestDB}
BACKUP_FILE=${BACKUP_FILE}

log "=== Phase 2: Preparing for database restore ==="
log "Target database: $DB_NAME"
log "Backup file: $BACKUP_FILE"

log "Backup file found: $(ls -lh "$BACKUP_FILE")"

# Get logical backup name
log "Extracting logical file names from backup..."
log "Raw FILELISTONLY output:"
/opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" \
    -Q "RESTORE FILELISTONLY FROM DISK = N'$BACKUP_FILE'" -h -1 -C

LOGICAL_NAME=$(/opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" \
-Q "RESTORE FILELISTONLY FROM DISK = N'$BACKUP_FILE'" -h -1 -C | awk 'NR==1 {print $1}' | tr -d '\r\n')

if [ -z "$LOGICAL_NAME" ]; then
    log "ERROR: Failed to extract logical file names from backup!"
    exit 1
fi

log "Logical data file name: $LOGICAL_NAME"
log "Logical log file name: ${LOGICAL_NAME}_log"

# Check if DB exists
log "Checking if database '$DB_NAME' already exists..."
DB_EXISTS=$(/opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" \
    -Q "SELECT name FROM sys.databases WHERE name = N'$DB_NAME'" -h -1 -C | xargs)

if [ "$DB_EXISTS" = "$DB_NAME" ]; then
    log "Database '$DB_NAME' exists"
else
    log "Database '$DB_NAME' does not exist"
fi

# Check if backup has changed (store last used backup in a metadata table)
METADATA_DB=RestoreMetadata
log "=== Phase 3: Checking backup metadata ==="

# Create metadata DB if not exists
log "Creating metadata database '$METADATA_DB' if it doesn't exist..."
/opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" -Q "IF DB_ID('$METADATA_DB') IS NULL CREATE DATABASE [$METADATA_DB]" -C

log "Creating metadata table if it doesn't exist..."
/opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" -d $METADATA_DB -Q "
IF OBJECT_ID('dbo.LastBackup') IS NULL
CREATE TABLE dbo.LastBackup (
    DbName NVARCHAR(128) PRIMARY KEY,
    BackupFile NVARCHAR(512),
    BackupDate DATETIME DEFAULT GETDATE()
);
" -C

log "Checking last used backup for '$DB_NAME'..."
LAST_BACKUP=$(/opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" -d $METADATA_DB \
    -h -1 -Q "SELECT BackupFile FROM dbo.LastBackup WHERE DbName = N'$DB_NAME'" -C | xargs)

if [ -z "$LAST_BACKUP" ]; then
    log "No previous backup record found for '$DB_NAME'"
else
    log "Last backup used: $LAST_BACKUP"
fi

# Decide if we need to restore
log "=== Phase 4: Decision making ==="
if [ "$DB_EXISTS" = "$DB_NAME" ] && [ "$LAST_BACKUP" = "$BACKUP_FILE" ]; then
    log "SUCCESS: Database '$DB_NAME' already exists and is restored from '$BACKUP_FILE'. Skipping restore."
else
    log "=== Phase 5: Database restore required ==="
    
    if [ "$DB_EXISTS" = "$DB_NAME" ]; then
        log "Dropping existing database '$DB_NAME'..."
        /opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" -Q "ALTER DATABASE [$DB_NAME] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$DB_NAME];" -C
        log "Database dropped successfully"
    fi

    log "Starting restore of database '$DB_NAME' from '$BACKUP_FILE'..."
    log "This may take several minutes depending on backup size..."
    
    restore_start=$(date +%s)
    
    # Restore
    /opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" -Q "
    RESTORE DATABASE [$DB_NAME] FROM DISK = N'$BACKUP_FILE' WITH MOVE N'$LOGICAL_NAME' TO N'/var/opt/mssql/data/$DB_NAME.mdf', MOVE N'${LOGICAL_NAME}_log' TO N'/var/opt/mssql/data/$DB_NAME.ldf', REPLACE;
    " -C
    
    restore_end=$(date +%s)
    restore_elapsed=$((restore_end - restore_start))
    
    if [ $? -eq 0 ]; then
        log "SUCCESS: Database restore completed in ${restore_elapsed}s"
    else
        log "ERROR: Database restore failed!"
        exit 1
    fi

    log "Updating metadata table..."
    /opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" -d $METADATA_DB -Q "
    IF EXISTS (SELECT 1 FROM dbo.LastBackup WHERE DbName = N'$DB_NAME')
        UPDATE dbo.LastBackup SET BackupFile = N'$BACKUP_FILE', BackupDate = GETDATE() WHERE DbName = N'$DB_NAME';
    ELSE
        INSERT INTO dbo.LastBackup (DbName, BackupFile) VALUES (N'$DB_NAME', N'$BACKUP_FILE');
    " -C
    log "Metadata updated successfully"
fi

log "=== Phase 6: Final verification ==="
log "Verifying database '$DB_NAME' is accessible..."
/opt/mssql-tools18/bin/sqlcmd -S mssql-db -U sa -P "$SA_PASSWORD" -d "$DB_NAME" -Q "SELECT COUNT(*) as TableCount FROM sys.tables" -C

log "=== SUCCESS: All operations completed! ==="
log "Database '$DB_NAME' is ready for use on port 1433"
log "Restore process completed successfully"

# Display connection information table
echo ""
echo "┌─────────────────────────────────────────────────────────────────────────────┐"
echo "│                    🎉 DATABASE CONNECTION INFO 🎉                        │"
echo "├─────────────────────────────────────────────────────────────────────────────┤"
echo "│  Host:        localhost                                                   │"
echo "│  Port:        1433                                                       │"
echo "│  Database:    $DB_NAME                                                   │"
echo "│  Username:    sa                                                         │"
echo "│  Password:    ${SA_PASSWORD}                                             │"
echo "│  Tables:      108                                                        │"
echo "├─────────────────────────────────────────────────────────────────────────────┤"
echo "│  📱 Connect with:                                                        │"
echo "│     • Azure Data Studio (free)                                           │"
echo "│     • DBeaver (free)                                                     │"
echo "│     • TablePlus (Mac, paid)                                              │"
echo "│     • Any SQL Server client                                              │"
echo "├─────────────────────────────────────────────────────────────────────────────┤"
echo "│  🔗 Connection String:                                                   │"
echo "│     Server=localhost,1433;Database=$DB_NAME;User Id=sa;Password=${SA_PASSWORD} │"
echo "└─────────────────────────────────────────────────────────────────────────────┘"
echo ""