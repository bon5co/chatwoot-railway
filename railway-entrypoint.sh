#!/bin/sh
# Railway entrypoint for Chatwoot.
#
# Two roles run from this one image:
#   no arguments  -> the web (Rails) service: prepares the database, then serves
#                    on Railway's injected $PORT bound to :: (Railway's private
#                    network is IPv6; binding 0.0.0.0 only would be unreachable
#                    from sibling services).
#   with arguments -> whatever Railway's start command passes, i.e. the Sidekiq
#                    worker. It waits for the web service to finish migrations
#                    first, otherwise it crash-loops on a table that does not
#                    exist yet.
set -e

: "${POSTGRES_HOST:?POSTGRES_HOST is required}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USERNAME="${POSTGRES_USERNAME:-postgres}"
POSTGRES_DATABASE="${POSTGRES_DATABASE:-chatwoot_production}"
PORT="${PORT:-3000}"

echo "[railway] waiting for postgres at ${POSTGRES_HOST}:${POSTGRES_PORT}"
tries=0
until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USERNAME" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -gt 150 ]; then
        echo "[railway] postgres never became ready after 5 minutes" >&2
        exit 1
    fi
    sleep 2
done
echo "[railway] postgres is ready"

mkdir -p /app/storage /app/tmp/pids
rm -f /app/tmp/pids/server.pid

if [ "$#" -gt 0 ]; then
    echo "[railway] waiting for the web service to finish migrations"
    tries=0
    until PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USERNAME" -d "$POSTGRES_DATABASE" \
        -tAc "select to_regclass('public.accounts')" 2>/dev/null | grep -q accounts; do
        tries=$((tries + 1))
        if [ "$tries" -gt 150 ]; then
            echo "[railway] schema still missing after 10 minutes, starting anyway" >&2
            break
        fi
        sleep 4
    done
    echo "[railway] starting: $*"
    exec "$@"
fi

# Idempotent: creates the database and loads the schema on a first deploy, runs
# pending migrations on every deploy after that.
echo "[railway] preparing database"
bundle exec rails db:chatwoot_prepare

echo "[railway] starting rails on :${PORT}"
exec bundle exec rails s -p "$PORT" -b '::'
