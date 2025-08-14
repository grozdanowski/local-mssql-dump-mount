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

### Starting the container:

```bash
docker-compose up --build
```

**⚠️ Important**: The container will **always restore the database** on startup, even if it was restored before. This ensures your database is always in a fresh, consistent state.

### What happens on startup:

1. Start SQL Server 2019.
2. Check if the database exists and matches the backup file.
3. **Always restore** the database from the backup file (drops existing if present).
4. Keep running to maintain the database connection.

### Container lifecycle options:

**Option 1: Fresh start (always restores)**

```bash
docker-compose up --build    # Restores database every time
docker-compose down          # Stops and removes container
```

**Option 2: Reuse existing container (no restore) - DOES NOT WORK YET - IN PROGRESS**

```bash
docker-compose start         # Start existing containers without restore
docker-compose stop          # Stop containers but keep them
```

**⚠️ Important Note**: This project uses a **two-service architecture**:

- **`mssql-db`**: Main SQL Server that stays running
- **`restore-db`**: Service that runs restore script and exits

The `restore-db` service runs the restore script every time you use `docker-compose up` (with or without `--build`). To avoid re-restoring, use `docker-compose start` instead.

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

• To restore a new backup, simply update `BACKUP_FILE` in `.env` and restart the container.
• The script will automatically detect changes and recreate the database.
• Make sure the SQL Server password meets complexity requirements.
• The container exposes port 1433 for local connections.
• Uses SQL Server 2022 on Linux with performance optimizations for Apple Silicon.
• **Note for Apple M chips**: Startup takes 2-4 minutes due to x86_64 emulation, but includes memory and startup optimizations to improve performance.
