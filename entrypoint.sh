#!/bin/sh
set -e

DATA_DIR="/home/node"

if [ -d /app/scripts ] && [ ! -d "$DATA_DIR/scripts" ]; then
  echo "Copying scripts to $DATA_DIR/scripts..."
  cp -r /app/scripts "$DATA_DIR/scripts"
fi

if [ -d /app/workflows ] && [ ! -d "$DATA_DIR/workflows" ]; then
  echo "Copying workflows to $DATA_DIR/workflows..."
  cp -r /app/workflows "$DATA_DIR/workflows"
fi

if [ -d /app/tests ] && [ ! -d "$DATA_DIR/tests" ]; then
  echo "Copying tests to $DATA_DIR/tests..."
  cp -r /app/tests "$DATA_DIR/tests"
fi

if [ -d /app/databases ] && [ ! -d "$DATA_DIR/databases" ]; then
  echo "Copying databases to $DATA_DIR/databases..."
  cp -r /app/databases "$DATA_DIR/databases"
fi

if [ "$DB_TYPE" = "postgresdb" ]; then
  echo "Waiting for PostgreSQL..."
  until PGPASSWORD=$DB_POSTGRESDB_PASSWORD psql -h "$DB_POSTGRESDB_HOST" -U "$DB_POSTGRESDB_USER" -d "postgres" -c '\q' 2>/dev/null; do
    echo "PostgreSQL is unavailable - sleeping"
    sleep 1
  done

  echo "PostgreSQL is up - checking if database exists"

  PGPASSWORD=$DB_POSTGRESDB_PASSWORD psql -h "$DB_POSTGRESDB_HOST" -U "$DB_POSTGRESDB_USER" -d "postgres" -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_POSTGRESDB_DATABASE'" | grep -q 1 || \
  PGPASSWORD=$DB_POSTGRESDB_PASSWORD psql -h "$DB_POSTGRESDB_HOST" -U "$DB_POSTGRESDB_USER" -d "postgres" -c "CREATE DATABASE $DB_POSTGRESDB_DATABASE"

  echo "PostgreSQL database ready"
else
  echo "Using SQLite database"
fi

BOOTSTRAP_MARKER="$DATA_DIR/.bootstrapped"
BOOTSTRAP_ENV="/tmp/credentials/bootstrap.env"
if [ -f "$BOOTSTRAP_ENV" ] && [ -f "$DATA_DIR/scripts/bootstrap.sh" ] && [ ! -f "$BOOTSTRAP_MARKER" ]; then
  echo "Running bootstrap..."
  sh "$DATA_DIR/scripts/bootstrap.sh"
fi

echo "Starting n8n..."

exec "$@"
