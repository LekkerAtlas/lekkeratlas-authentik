#!/usr/bin/env bash
set -euo pipefail

compose_file="${1:-docker-compose.ci.yml}"
service_name="${2:-worker}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="$script_dir/check_authentik_blueprint_autoload.py"

timeout_seconds="${AUTHENTIK_BLUEPRINT_AUTOLOAD_TIMEOUT_SECONDS:-300}"
poll_seconds="${AUTHENTIK_BLUEPRINT_AUTOLOAD_POLL_SECONDS:-5}"
stable_polls="${AUTHENTIK_BLUEPRINT_STABLE_POLLS:-3}"

docker compose -f "$compose_file" exec -T \
  -e AUTHENTIK_BLUEPRINT_AUTOLOAD_TIMEOUT_SECONDS="$timeout_seconds" \
  -e AUTHENTIK_BLUEPRINT_AUTOLOAD_POLL_SECONDS="$poll_seconds" \
  -e AUTHENTIK_BLUEPRINT_STABLE_POLLS="$stable_polls" \
  "$service_name" \
  ak shell -c "$(cat "$check_script")"
