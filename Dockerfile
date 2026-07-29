FROM chatwoot/chatwoot:v4.16.2-ce

# Railway wrapper around the official Chatwoot community image.
#
# Everything the platform already knows is baked in here rather than left as a
# template variable, because Railway's `templateGenerate` keeps a variable's
# default ONLY when the value is a Railway expression (${{secret(n)}},
# ${{svc.VAR}}, ${{RAILWAY_PUBLIC_DOMAIN}}). A variable holding a literal loses
# its default and publishes as "required, no value" — the deploy form then asks
# the deployer to type settings the image already knows, which is what makes a
# listing dead on arrival.
#
# What is left on the deploy form is only what genuinely belongs to the
# deployer, and each of those carries a generated default.
ENV INSTALLATION_ENV=docker \
    RAILS_ENV=production \
    NODE_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_MAX_THREADS=5 \
    LOG_LEVEL=info \
    POSTGRES_USERNAME=postgres \
    POSTGRES_PORT=5432 \
    POSTGRES_DATABASE=chatwoot_production \
    ACTIVE_STORAGE_SERVICE=local \
    ENABLE_ACCOUNT_SIGNUP=false \
    FORCE_SSL=false

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
