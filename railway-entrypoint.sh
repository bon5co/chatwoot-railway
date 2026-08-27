#!/bin/sh
# Railway entrypoint for Chatwoot.
#
# Rails and Sidekiq run in ONE container here, deliberately. Chatwoot's
# ActiveStorage `local` service keeps every uploaded attachment, avatar and
# generated CSV export under /app/storage, and Railway volumes cannot be shared
# between services: two services mounting the same path each get their OWN
# volume. Split across a web service and a worker service, a report exported by
# Sidekiq is written to the worker's disk and then requested from the web
# service, which does not have it. One service, one volume, no split.
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

# Idempotent: creates the database and loads the schema on a first deploy, runs
# pending migrations on every deploy after that.
echo "[railway] preparing database"
bundle exec rails db:chatwoot_prepare

# Before anything binds the port. A stock production deploy has no user, and
# ENABLE_ACCOUNT_SIGNUP is false, so the signup route answers 404 — see
# seed_admin.rb. Re-applying the password on every boot also makes a redeploy
# the instance's only working password reset (Chatwoot's own reset is an
# emailed link, and a fresh deploy has no SMTP).
echo "[railway] seeding administrator"
bundle exec rails runner /usr/local/share/chatwoot/seed_admin.rb

echo "[railway] starting sidekiq"
bundle exec sidekiq -C config/sidekiq.yml &
sidekiq_pid=$!

# If the worker dies the container must die with it, otherwise Railway keeps
# reporting a healthy deploy while no background job ever runs again.
(
    wait "$sidekiq_pid"
    echo "[railway] sidekiq exited, stopping the container" >&2
    kill -TERM 1 2>/dev/null || true
) &

echo "[railway] starting rails on :${PORT}"
exec bundle exec rails s -p "$PORT" -b '::'
