ARG AUTHENTIK_TAG=2026.2.4

FROM ghcr.io/goauthentik/server:${AUTHENTIK_TAG}

USER root

COPY media/branding /data/media/public/branding
COPY authentik/blueprints /blueprints/custom

COPY container/authentik/entrypoint.sh /usr/local/bin/lekkeratlas-entrypoint
COPY container/authentik/scripts /usr/local/lib/lekkeratlas

RUN chmod -R a+rX /data/media/public/branding /blueprints/custom /usr/local/lib/lekkeratlas \
  && chmod +x /usr/local/bin/lekkeratlas-entrypoint \
  && chmod +x /usr/local/lib/lekkeratlas/*.sh

USER authentik

ENTRYPOINT ["/usr/local/bin/lekkeratlas-entrypoint"]
