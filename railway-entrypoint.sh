#!/bin/sh
# Pastefy for Railway: validate the variables, start the server on $PORT, then (once the app has created its tables)
# make sure the administrator and the API key exist. Anonymous creation is already refused by
# PASTEFY_LOGIN_REQUIRED_CREATE, so there is no moment at which the instance is writable without the key.
set -eu

fail() { echo "railway-entrypoint: $*" >&2; exit 1; }

K="${PASTEFY_API_KEY:-}"
[ "${#K}" -ge 32 ] || fail "PASTEFY_API_KEY is required (32 characters or more)"
[ "${#K}" -le 60 ] || fail "PASTEFY_API_KEY must be at most 60 characters (database column limit)"
case "$K" in *[!A-Za-z0-9]*) fail "PASTEFY_API_KEY must be letters and digits only" ;; esac
[ -n "${DATABASE_HOST:-}" ] || fail "DATABASE_HOST is required"
[ -n "${DATABASE_PASSWORD:-}" ] || fail "DATABASE_PASSWORD is required"

export HTTP_SERVER_PORT="${PORT:-8080}"
export DATABASE_NAME="${DATABASE_NAME:-pastefy}"
export DATABASE_USER="${DATABASE_USER:-pastefy}"
export MYSQL_PWD="$DATABASE_PASSWORD"
# the JVM reads the container limit, not the host, but leaves 75% of it as heap by default; keep room for metaspace
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--XX:MaxRAMPercentage=70}"

sql() { mariadb --protocol=tcp -h "$DATABASE_HOST" -P "${DATABASE_PORT:-3306}" -u "$DATABASE_USER" "$DATABASE_NAME" -N -e "$1"; }

echo "railway-entrypoint: port=$HTTP_SERVER_PORT db=$DATABASE_HOST:${DATABASE_PORT:-3306}/$DATABASE_NAME"

# the database service may still be initialising its volume
i=0
until sql "SELECT 1" >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -le 120 ] || fail "database $DATABASE_HOST not reachable after 240s"
  sleep 2
done

java -jar /usr/local/lib/backend.jar start &
APP=$!
trap 'kill -TERM "$APP" 2>/dev/null || true' TERM INT

# wait for the app's own migration to create the tables, then seed
i=0
until sql "SELECT 1 FROM pastefy_users LIMIT 1" >/dev/null 2>&1 && sql "SELECT 1 FROM pastefy_auth_keys LIMIT 1" >/dev/null 2>&1; do
  kill -0 "$APP" 2>/dev/null || fail "server exited before creating its tables"
  i=$((i + 1)); [ "$i" -le 180 ] || { kill -TERM "$APP" 2>/dev/null || true; fail "tables not created after 360s"; }
  sleep 2
done

if ! sql "
INSERT INTO pastefy_users (id, name, unique_name, email, auth_id, auth_provider, type, created_at, updated_at)
  SELECT 'railway0', 'admin', 'admin', 'admin@localhost', 'railway-admin', 'OIDC', 'ADMIN', NOW(), NOW() FROM DUAL
  WHERE NOT EXISTS (SELECT 1 FROM pastefy_users WHERE id = 'railway0');
DELETE FROM pastefy_auth_keys WHERE user_id = 'railway0' AND type = 'API' AND \`key\` <> '$K';
INSERT INTO pastefy_auth_keys (\`key\`, user_id, type, created_at, updated_at)
  SELECT '$K', 'railway0', 'API', NOW(), NOW() FROM DUAL
  WHERE NOT EXISTS (SELECT 1 FROM pastefy_auth_keys WHERE \`key\` = '$K');
"; then
  kill -TERM "$APP" 2>/dev/null || true
  fail "could not seed the administrator and API key"
fi
echo "railway-entrypoint: administrator and API key present"

rc=0
wait "$APP" || rc=$?
if [ "$rc" -gt 128 ]; then wait "$APP" || rc=$?; fi   # a forwarded TERM interrupts the first wait; let the JVM finish
exit "$rc"
