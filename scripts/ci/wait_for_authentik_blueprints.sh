#!/usr/bin/env bash
set -euo pipefail

compose_file="${1:-docker-compose.ci.yml}"
service_name="${2:-worker}"

timeout_seconds="${AUTHENTIK_BLUEPRINT_TIMEOUT_SECONDS:-240}"
sleep_seconds="${AUTHENTIK_BLUEPRINT_POLL_SECONDS:-5}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="$script_dir/check_authentik_blueprints.py"

deadline=$((SECONDS + timeout_seconds))

while true; do
  set +e

  docker compose -f "$compose_file" exec -T "$service_name" \
    ak shell -c "$(cat "$check_script")"

  status="$?"

  set -e

  if [[ "$status" == "0" ]]; then
    exit 0
  fi

  if [[ "$status" == "1" ]]; then
    echo "A blueprint failed permanently."
    docker compose -f "$compose_file" logs --no-color --tail=160 "$service_name"
    exit 1
  fi

  if [[ "$SECONDS" -ge "$deadline" ]]; then
    echo "Timed out waiting for blueprints to become successful."
    docker compose -f "$compose_file" logs --no-color --tail=240 "$service_name"
    exit 1
  fi

  echo "Blueprints are not ready yet. Waiting ${sleep_seconds}s..."
  docker compose -f "$compose_file" logs --no-color --tail=80 "$service_name"
  sleep "$sleep_seconds"
done
