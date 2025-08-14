FROM mcr.microsoft.com/mssql/server:2019-latest

# Copy the restore script
COPY init/restore.sh /usr/src/app/restore.sh

# Use the default SQL Server entrypoint and add our script to run after startup
CMD ["/opt/mssql/bin/sqlservr"]