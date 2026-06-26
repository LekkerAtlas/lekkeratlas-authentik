#!/usr/bin/env bash
set -euo pipefail

compose_file="${1:-docker-compose.ci.yml}"
service_name="${2:-worker}"

echo "== Active custom blueprint files =="
docker compose -f "$compose_file" exec -T "$service_name" sh -lc '
find /blueprints/custom -maxdepth 1 -type f -name "*.yaml" -print | sort
'

echo
echo "== BlueprintInstance status =="
docker compose -f "$compose_file" exec -T "$service_name" ak shell -c '
from authentik.blueprints.models import BlueprintInstance

for bp in BlueprintInstance.objects.filter(path__startswith="custom/").order_by("path"):
    print("path=", bp.path)
    print("name=", bp.name)
    print("status=", bp.status)
    print("last_applied=", bp.last_applied)
    print("last_applied_hash=", bp.last_applied_hash)
    print("managed_models=", bp.managed_models)
    print()
'

echo
echo "== Dependency check for 00-lekkeratlas-minimal.yaml =="
docker compose -f "$compose_file" exec -T "$service_name" ak shell -c '
from authentik.flows.models import Flow
from authentik.providers.oauth2.models import ScopeMapping

required_flows = [
    "default-provider-authorization-implicit-consent",
    "default-provider-invalidation-flow",
]

required_scopes = [
    "openid",
    "email",
    "profile",
]

print("Required flows:")
for slug in required_flows:
    exists = Flow.objects.filter(slug=slug).exists()
    print(f"- {slug}: {exists}")

print()
print("Required OAuth scope mappings:")
for scope_name in required_scopes:
    exists = ScopeMapping.objects.filter(scope_name=scope_name).exists()
    print(f"- {scope_name}: {exists}")
'

echo
echo "== Re-apply failed custom blueprints with traceback =="

failed_paths="$(
  docker compose -f "$compose_file" exec -T "$service_name" ak shell -c '
from authentik.blueprints.models import BlueprintInstance

for bp in BlueprintInstance.objects.filter(path__startswith="custom/", status="error").order_by("path"):
    print(bp.path)
' | grep '^custom/' || true
)"

if [[ -z "$failed_paths" ]]; then
  echo "No failed custom blueprints to re-apply."
else
  while IFS= read -r path; do
    echo
    echo "Re-applying ${path}"
    docker compose -f "$compose_file" exec -T "$service_name" \
      ak apply_blueprint "$path" --traceback -v 3
  done <<<"$failed_paths"
fi
