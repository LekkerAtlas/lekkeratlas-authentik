# container/authentik/Dockerfile
ARG AUTHENTIK_TAG=2026.2.4

FROM ghcr.io/goauthentik/server:${AUTHENTIK_TAG}

USER root

COPY media/branding /data/media/public/branding
COPY authentik/blueprints/*.yaml /blueprints/custom/

RUN chmod -R a+rX /data/media/public/branding /blueprints/custom

USER authentik
