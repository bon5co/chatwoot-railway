# chatwoot-railway

Railway-tuned [Chatwoot](https://github.com/chatwoot/chatwoot) image: baked env defaults,
`$PORT` + IPv6 bind, first-boot database prepare, and one image that runs both the Rails web
service and the Sidekiq worker.

Image: `ghcr.io/bon5co/chatwoot-railway:latest` — wraps `chatwoot/chatwoot:v4.16.2-ce`.

## Why a wrapper image exists

Railway's `templateGenerate` keeps a template variable's default **only when the live value is
a Railway expression** (`${{secret(n)}}`, `${{svc.VAR}}`, `${{RAILWAY_PUBLIC_DOMAIN}}`).
A variable holding a literal loses its default and publishes as *required, with no value*, so
the marketplace deploy form opens asking the deployer to type settings the image already knows
(`RAILS_ENV`, `INSTALLATION_ENV`, `POSTGRES_USERNAME`, …). Baking those into the image removes
them from the form entirely; what is left is only what genuinely belongs to the deployer, each
with a generated default.

## What the entrypoint does

- Waits for Postgres (`pg_isready`) before touching Rails.
- **Web role** (no arguments): runs `rails db:chatwoot_prepare` — idempotent, creates and
  seeds on the first deploy, migrates on later ones — then serves on Railway's injected
  `$PORT`, bound to `::`. Railway's private network is IPv6-only, so a `0.0.0.0`-only bind is
  unreachable from sibling services.
- **Worker role** (Railway start command `bundle exec sidekiq -C config/sidekiq.yml`): waits
  for the web service to create the schema (`select to_regclass('public.accounts')`) before
  starting, so it does not crash-loop through the first deploy.

## Baked defaults

`INSTALLATION_ENV=docker`, `RAILS_ENV=production`, `NODE_ENV=production`,
`RAILS_LOG_TO_STDOUT=true`, `RAILS_SERVE_STATIC_FILES=true`, `RAILS_MAX_THREADS=5`,
`LOG_LEVEL=info`, `POSTGRES_USERNAME=postgres`, `POSTGRES_PORT=5432`,
`POSTGRES_DATABASE=chatwoot_production`, `ACTIVE_STORAGE_SERVICE=local`,
`ENABLE_ACCOUNT_SIGNUP=false`, `FORCE_SSL=false`.

`ENABLE_ACCOUNT_SIGNUP=false` closes public sign-ups on a fresh install. It does **not** block
the first administrator: `/installation/onboarding` is a separate route, gated on a Redis flag
set during `db:chatwoot_prepare`, so the deployer still creates the super admin on first visit.

## Variables the deployer still supplies

| Variable | Value |
| --- | --- |
| `SECRET_KEY_BASE` | `${{secret(64)}}` |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | `${{secret(32)}}` |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | `${{secret(32)}}` |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | `${{secret(32)}}` |
| `FRONTEND_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| `POSTGRES_HOST` / `POSTGRES_PASSWORD` | references to the Postgres service |
| `REDIS_URL` / `REDIS_PASSWORD` | references to the Redis service |

Setting all three `ACTIVE_RECORD_ENCRYPTION_*` keys is what turns on Chatwoot's MFA/2FA
support (`Chatwoot.mfa_enabled?` requires all three).

## Related

- Railway template + notes: [bon5co/railwaytemplate2](https://github.com/bon5co/railwaytemplate2) (`chatwoot/`)
- Same pattern: [bon5co/hermes-agent-railway](https://github.com/bon5co/hermes-agent-railway)
