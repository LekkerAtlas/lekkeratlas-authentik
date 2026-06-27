#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/lekkeratlas/common.sh

worker_pid=""

shutdown() {
  log "Received shutdown signal."

  if [[ -n "$worker_pid" ]] && kill -0 "$worker_pid" 2>/dev/null; then
    kill "$worker_pid" 2>/dev/null || true
    wait "$worker_pid" 2>/dev/null || true
  fi

  exit 143
}

wait_for_authentik_ready() {
  local max_attempts="${AUTHENTIK_READY_ATTEMPTS:-60}"
  local sleep_seconds="${AUTHENTIK_READY_SLEEP_SECONDS:-5}"

  log "Waiting for Authentik healthcheck..."

  for attempt in $(seq 1 "$max_attempts"); do
    if ak healthcheck >/dev/null 2>&1; then
      log "Authentik healthcheck is passing."
      return 0
    fi

    log "Authentik is not ready yet (${attempt}/${max_attempts}). Waiting ${sleep_seconds}s..."
    sleep "$sleep_seconds"
  done

  log "Timed out waiting for Authentik readiness."
  return 1
}

stop_worker_and_exit() {
  local exit_code="$1"

  if [[ -n "$worker_pid" ]] && kill -0 "$worker_pid" 2>/dev/null; then
    log "Stopping Authentik worker."
    kill "$worker_pid" 2>/dev/null || true
    wait "$worker_pid" 2>/dev/null || true
  fi

  exit "$exit_code"
}

trap shutdown TERM INT

log "Starting Authentik worker..."
ak worker &
worker_pid="$!"

if is_true "${AUTHENTIK_BLUEPRINT_APPLY_ENABLED:-true}"; then
  if ! wait_for_authentik_ready; then
    log "Stopping because Authentik did not become ready."
    stop_worker_and_exit 1
  fi

  log "Applying LekkerAtlas blueprints."

  if ! /usr/local/lib/lekkeratlas/apply-blueprints-by-filename.sh; then
    log "Stopping because blueprint deployment failed."
    stop_worker_and_exit 1
  fi

  log "Blueprint deployment completed successfully."
else
  log "Blueprint applier is disabled."
fi

wait "$worker_pid"
worker_status="$?"

log "Authentik worker exited with status ${worker_status}."
exit "$worker_status"
