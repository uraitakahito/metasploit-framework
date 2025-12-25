#!/bin/bash
set -e

# Generate database.yml if not exists
# Note: Dockerfileでconfig/database.ymlをコピーしても、docker-compose.dev.ymlで
# ソースコード全体をボリュームマウント(.:/usr/src/metasploit-framework)するため、
# ホストのファイルで上書きされてしまう。ホストにはconfig/database.ymlが存在しない
# (.gitignoreで除外)ため、コンテナ起動時にここで生成する必要がある。
if [ ! -f config/database.yml ]; then
  cat > config/database.yml << EOF
development: &pgsql
  adapter: postgresql
  database: ${DB_NAME:-msf}
  username: ${DB_USER:-postgres}
  host: ${DB_HOST:-db}
  port: ${DB_PORT:-5432}
  pool: 200
  timeout: 5

production:
  <<: *pgsql

test:
  <<: *pgsql
  database: ${DB_NAME:-msf}test
EOF
  echo "[entrypoint] Generated config/database.yml"
fi

# Wait for PostgreSQL if DB_HOST is set
if [ -n "$DB_HOST" ]; then
  echo "[entrypoint] Waiting for PostgreSQL at $DB_HOST:${DB_PORT:-5432}..."
  until pg_isready -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "${DB_USER:-postgres}" -q 2>/dev/null; do
    sleep 1
  done
  echo "[entrypoint] PostgreSQL is ready"

  # Create database if not exists (suppress error if already exists)
  if ! bin/rails db:version > /dev/null 2>&1; then
    echo "[entrypoint] Creating database..."
    bin/rails db:create 2>/dev/null || true
  fi
fi

exec "$@"
