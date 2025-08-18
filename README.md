# MSSQL Docker Backup & Restore

This project provides a Dockerized Microsoft SQL Server setup that automatically restores a database from a `.bak` backup file (file doesn't need to even have that extension). The restore process is fully automated, so the only thing you need to do is configure your environment variables and run `docker-compose up`.

---

## Features

- Fully automated database restore on container startup.
- Skips restore if the database already exists and matches the backup file.
- Automatically restores a new database if the backup file in `.env` changes.
- Uses environment variables for secure configuration.
- No manual commands needed after setup.
- **NEW**: Automatically tracks which backup was used for each database in a metadata table.
- **NEW**: Automatically drops and recreates database if backup file changes.

---

## Prerequisites

- Docker
- Docker Compose
- A `.bak` backup file stored in `./backups` folder.

## Docker Desktop Requirements

**Important**: This project requires significant resources from Docker Desktop:

- **RAM**: Allocate at least **10-12 GB** of RAM to Docker Desktop if you're restoring larger DBs
- **Disk**: Allocate at least **128 GB** of disk space to Docker Desktop if you're restoring larger DBs

### How to configure Docker Desktop resources:

1. Open Docker Desktop
2. Go to **Settings** → **Resources**
3. **Memory**: Set to 10-12 GB (or higher if available)
4. **Disk image size**: Set to 128 GB (or higher if available)
5. Click **Apply & Restart**

**Why these requirements?**

- SQL Server needs substantial memory for database operations
- Large `.bak` files require significant disk space for restore operations
- Apple Silicon emulation (x86_64) increases memory usage
- Database restore operations are memory-intensive

---

## Setup

1. Clone this repository:

```bash
git clone <repo-url>
cd <repo-folder>
```

2. Add your backup file to ./backups.
3. Create a .env file in the project root:

```bash
SA_PASSWORD=YourStrong!Passw0rd
DB_NAME=YourDatabaseName
BACKUP_FILE=YourBackupFile.bak
```

Replace:

- `YourStrong!Passw0rd` with a strong password
- `YourDatabaseName` with your desired database name (defaults to "TestDB" if not specified)
- `YourBackupFile.bak` with the backup file name

## Usage

### Normal startup (no restore):

```bash
docker-compose up
```

**What happens**: SQL Server starts with existing database state or creates a fresh database. No backup restoration occurs.

### Restore from backup:

```bash
docker-compose --profile restore up
```

**What happens**:

1. Start SQL Server 2019.
2. Restore database from the specified backup file.
3. Keep running to maintain the database connection.

**Requirements for restore mode**:

- `BACKUP_FILE` environment variable must be set
- Backup file must exist in the `./backups` folder
- `DO_RESTORE=true` (automatically set when using `--profile restore`)

### Container lifecycle options:

**Option 1: Normal startup (no restore)**

```bash
docker-compose up            # Start with existing database state
docker-compose down          # Stops and removes containers
```

**⚠️ WARNING**: `docker-compose down` **DELETES ALL DATABASE DATA**!

**Option 2: Restore from backup**

```bash
docker-compose --profile restore up    # Restore database from backup
docker-compose down                    # Stops and removes containers
```

**⚠️ WARNING**: `docker-compose down` **DELETES ALL DATABASE DATA**!

**Option 3: Reuse existing container**

```bash
docker-compose stop          # Stop containers but keep them
docker-compose start         # Start existing containers without restore
```

**Option 4: Keep container running (recommended for development)**

```bash
docker-compose up            # Start and keep running
# Use Ctrl+C to stop, then:
docker-compose start         # Resume without restore
```

**⚠️ Important Note**: This project uses a **two-service architecture**:

- **`mssql-db`**: Main SQL Server that stays running
- **`restore-db`**: Service that runs restore script and exits (only when using `--profile restore`)

**Key differences**:

- `docker-compose up` **starts normally** without restore (uses existing database state)
- `docker-compose --profile restore up` **runs restore script** and restores from backup
- `docker-compose down` **removes** containers
- `docker-compose stop` **keeps** containers (use `docker-compose start` to resume)

**🚨 CRITICAL: Database Data Persistence**

- **`docker-compose down`** → **DELETES ALL DATABASE DATA** (containers + volumes removed)
- **`docker-compose stop`** → **PRESERVES database data** (containers stopped but data kept)
- **`docker-compose start`** → **Resumes with existing data** (no data loss)

**For development**: Use `stop/start` to preserve your database between sessions.
**For fresh start**: Use `down/up` when you want to start completely clean.

## How It Works

The restore script:

- Waits for SQL Server to be ready
- Extracts logical file names from the backup file automatically
- Creates a metadata database (`RestoreMetadata`) to track which backup was used for each database
- Only restores if the database doesn't exist or if the backup file has changed
- Automatically handles the MOVE operations for data and log files

## Folder Structure

```bash
.
├── backups/            # Place your .bak files here
├── init/               # Initialization scripts (restore.sh)
├── docker-compose.yml
├── Dockerfile
└── .env
```

## Notes

• To restore from a backup, use `docker-compose --profile restore up` with `BACKUP_FILE` set in `.env`.
• For normal startup without restore, simply use `docker-compose up` (no backup file required).
• The script will automatically detect changes and recreate the database when in restore mode.
• Make sure the SQL Server password meets complexity requirements.
• The container exposes port 1433 for local connections.
• Uses SQL Server 2019 on Linux with performance optimizations for Apple Silicon.
• **Note for Apple M chips**: Startup takes 2-4 minutes due to x86_64 emulation, but includes memory and startup optimizations to improve performance.

## Best Practices

### **Data Persistence:**

- **Daily development**: Use `docker-compose stop` and `docker-compose start` to preserve your database
- **Fresh start needed**: Use `docker-compose down` and `docker-compose up` (but remember this deletes all data)
- **Backup before major changes**: Always restore from backup if you need to start fresh

### **Workflow Recommendations:**

1. **First time setup**: `docker-compose --profile restore up` (restores from backup)
2. **Daily development**: `docker-compose stop` → `docker-compose start` (preserves data)
3. **When you need fresh**: `docker-compose down` → `docker-compose --profile restore up` (restores again)
