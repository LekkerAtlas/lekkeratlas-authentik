# LekkerAtlas Authentik local development

Custom Authentik image for LekkerAtlas.

This repository contains the Authentik configuration-as-code setup for LekkerAtlas. It builds a custom Authentik Docker image that includes:

Authentik blueprints
LekkerAtlas branding media
A custom single-screen username/password login flow
Notification/webhook configuration for syncing Authentik users to LekkerAtlas

The image is published to GitHub Container Registry only when a versioned GitHub Release is created.

## What is included

- `docker-compose.yml` starts a local Authentik stack:
  - `postgresql`
  - `server`
  - `worker`
- `authentik/blueprints/*.yaml` contains the split blueprint files.
- `.env.example` documents every required local secret/config value.
- `custom-templates/` is mounted into Authentik at `/templates`.
- `certs/` is mounted into the worker at `/certs`.

The old `config-runner` scaffold has intentionally been removed.

## Quick start

```bash
cp .env.example .env
```

Generate real local values and put them in `.env`:

```bash
openssl rand -base64 36 | tr -d '\n'
openssl rand -base64 60 | tr -d '\n'
```

Use the first value for `PG_PASS` and the second value for `AUTHENTIK_SECRET_KEY`.

Start the stack:

```bash
docker compose up -d
```

Follow the worker logs while blueprints are discovered/applied:

```bash
docker compose logs -f worker
```

Open Authentik locally:

```text
http://localhost:9000
https://localhost:9443
```

## Blueprint secrets

Some blueprint values are intentionally not committed. They are loaded from environment variables with `!Env`.

Required variables:

```env
AUTHENTIK_WEBHOOK_SYNC_LEKKERATLAS_DB_HEADER_EXPRESSION=...
AUTHENTIK_PROVIDER_FOR_LEKKERATLAS_CLIENT_SECRET=...
AUTHENTIK_RABBITMQ_CLIENT_SECRET=...
```

These are passed to the `worker` service in `docker-compose.yml`, because local blueprint files are mounted into the worker container at `/blueprints/custom`.

## Reset local development state

To destroy the local database and Authentik runtime data:

```bash
docker compose down -v
rm -rf data
```

Then start again:

```bash
docker compose up -d
```

## Useful commands

Validate the final Compose config:

```bash
docker compose config
```

Check Authentik's resolved runtime config:

```bash
docker compose run --rm worker ak dump_config
```

Export the current local Authentik config again:

```bash
docker compose exec -T worker ak export_blueprint > current-export.yaml
```

## Notes

- Do not commit `.env`.
- Do not commit local database or uploaded-file data from `data/`.
- The worker mounts `/var/run/docker.sock` so Authentik can manage Docker outposts locally. Remove that mount if you want to manage outposts manually.
- The exported blueprints still contain production-ish domains such as `lekkeratlas.nl`. That is fine for config review, but provider callback URLs may need local overrides for full end-to-end app login testing.
