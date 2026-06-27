#!/usr/bin/env bash
set -Eeuo pipefail

command="${1:-}"

if [[ "${AUTHENTIK_BLUEPRINT_PREFLIGHT_ENABLED:-true}" == "true" ]]; then
  # Syntax validation should run for both server and worker, because Authentik
  # can parse blueprint files during startup/migrations.
  #
  # Env validation defaults to true only for the worker, because the worker is
  # the process that actually applies the LekkerAtlas blueprints.
  if [[ "$command" == "worker" ]]; then
    export AUTHENTIK_BLUEPRINT_PREFLIGHT_CHECK_ENV="${AUTHENTIK_BLUEPRINT_PREFLIGHT_CHECK_ENV:-true}"
  else
    export AUTHENTIK_BLUEPRINT_PREFLIGHT_CHECK_ENV="${AUTHENTIK_BLUEPRINT_PREFLIGHT_CHECK_ENV:-false}"
  fi

  /usr/local/lib/lekkeratlas/preflight-blueprints.sh
fi

case "$command" in
worker)
  exec /usr/local/lib/lekkeratlas/worker-with-blueprints.sh
  ;;

server)
  exec ak "$@"
  ;;

"")
  exec ak server
  ;;

*)
  exec "$@"
  ;;
esac
