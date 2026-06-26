#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/lekkeratlas/common.sh

blueprint_root="/blueprints/custom/parts"
blueprint_path_prefix="custom/parts"

get_blueprint_files() {
  find "$blueprint_root" -maxdepth 1 -type f -name "*.yaml" -exec basename {} \; |
    LC_ALL=C sort
}

dump_blueprint_status() {
  log "Current custom BlueprintInstance status:"

  ak shell -c '
from authentik.blueprints.models import BlueprintInstance

for blueprint in BlueprintInstance.objects.filter(path__startswith="custom/").order_by("path"):
    print(f"- {blueprint.path}: {blueprint.status}")
' || true
}

get_blueprint_status() {
  local blueprint_path="$1"

  BLUEPRINT_PATH="$blueprint_path" ak shell -c '
import os
from authentik.blueprints.models import BlueprintInstance

path = os.environ["BLUEPRINT_PATH"]
blueprint = BlueprintInstance.objects.filter(path=path).first()

if blueprint is None:
    print("missing")
else:
    print(blueprint.status)
'
}

run_apply_blueprint_debug() {
  local blueprint_path="$1"
  local output_file

  output_file="$(mktemp)"

  log "Running: ak apply_blueprint ${blueprint_path} --traceback -v 3"

  set +e
  ak apply_blueprint "$blueprint_path" --traceback -v 3 2>&1 | tee "$output_file"
  local apply_status="${PIPESTATUS[0]}"
  set -e

  log "apply_blueprint exit status for ${blueprint_path}: ${apply_status}"

  if [[ "$apply_status" != "0" ]]; then
    log "apply_blueprint failed directly for ${blueprint_path}."
    log "Captured apply_blueprint output:"
    sed 's/^/[apply_blueprint] /' "$output_file" >&2
    rm -f "$output_file"
    return "$apply_status"
  fi

  rm -f "$output_file"
  return 0
}

assert_blueprint_successful() {
  local blueprint_path="$1"
  local status
  local status_command_exit

  log "Inspecting BlueprintInstance status for ${blueprint_path}"

  set +e
  status="$(get_blueprint_status "$blueprint_path" | tail -n 1 | tr -d '\r')"
  status_command_exit="$?"
  set -e

  log "Status command exit code for ${blueprint_path}: ${status_command_exit}"
  log "Observed BlueprintInstance status for ${blueprint_path}: ${status:-<empty>}"

  if [[ "$status_command_exit" != "0" ]]; then
    log "Could not read BlueprintInstance status for ${blueprint_path}"
    dump_blueprint_status
    return 1
  fi

  case "$status" in
  successful)
    log "BlueprintInstance status is successful: ${blueprint_path}"
    return 0
    ;;

  error)
    log "BlueprintInstance status is error: ${blueprint_path}"
    log "Re-running with traceback and verbosity level 3 for debug output..."
    run_apply_blueprint_debug "$blueprint_path" || true
    dump_blueprint_status
    return 1
    ;;

  missing)
    log "No BlueprintInstance row exists for ${blueprint_path}."
    log "This is acceptable for explicit filename-based apply because apply_blueprint already exited successfully."
    return 0
    ;;

  unknown)
    log "BlueprintInstance is still unknown after explicit apply: ${blueprint_path}"
    dump_blueprint_status
    return 1
    ;;

  "")
    log "Blueprint status output was empty for ${blueprint_path}"
    dump_blueprint_status
    return 1
    ;;

  *)
    log "BlueprintInstance status is not successful: ${blueprint_path}: ${status}"
    dump_blueprint_status
    return 1
    ;;
  esac
}

assert_runtime_state() {
  if ! is_true "${AUTHENTIK_BLUEPRINT_ASSERT_RUNTIME_STATE:-true}"; then
    log "Skipping runtime state assertion."
    return 0
  fi

  log "Checking LekkerAtlas runtime state..."

  ak shell -c '
from authentik.core.models import Application
from authentik.brands.models import Brand
from authentik.flows.models import Flow

app = Application.objects.get(slug="lekker-atlas")
flow = Flow.objects.get(slug="lekkeratlas-authentication-flow")
brand = Brand.objects.get(domain="authentik-default")

assert app.provider is not None, "LekkerAtlas application has no provider"
assert brand.default_application_id == app.pk, "Brand does not point to LekkerAtlas application"
assert brand.flow_authentication_id == flow.pk, "Brand does not point to LekkerAtlas authentication flow"

print("Runtime state is valid")
print("Application:", app.slug, app.provider)
print("Flow:", flow.slug)
print("Brand:", brand.domain, brand.flow_authentication)
'
}

main() {
  if [[ ! -d "$blueprint_root" ]]; then
    log "Blueprint root does not exist: ${blueprint_root}"
    exit 1
  fi

  mapfile -t blueprint_files < <(get_blueprint_files)

  if [[ "${#blueprint_files[@]}" -eq 0 ]]; then
    log "No blueprint files found in ${blueprint_root}"
    exit 1
  fi

  log "Applying blueprints by filename:"
  for file in "${blueprint_files[@]}"; do
    log "- ${blueprint_path_prefix}/${file}"
  done

  for file in "${blueprint_files[@]}"; do
    local blueprint_path="${blueprint_path_prefix}/${file}"

    log "Applying ${blueprint_path}"

    if ! run_apply_blueprint_debug "$blueprint_path"; then
      log "Stopping because apply_blueprint failed directly: ${blueprint_path}"
      dump_blueprint_status
      exit 1
    fi

    if ! assert_blueprint_successful "$blueprint_path"; then
      log "Stopping because BlueprintInstance status is not successful: ${blueprint_path}"
      exit 1
    fi
  done

  assert_runtime_state

  log "All blueprints applied successfully."
}

main "$@"
