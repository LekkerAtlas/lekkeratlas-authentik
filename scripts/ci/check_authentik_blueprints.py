from pathlib import Path
from sys import exit

from authentik.blueprints.models import BlueprintInstance

BLUEPRINT_ROOT = Path("/blueprints/custom")

expected_paths = sorted(f"custom/{path.name}" for path in BLUEPRINT_ROOT.glob("*.yaml"))

if not expected_paths:
    print("No active blueprint files found in /blueprints/custom/*.yaml")
    exit(2)

blueprints = {
    blueprint.path: blueprint
    for blueprint in BlueprintInstance.objects.filter(path__in=expected_paths)
}

print("Expected blueprint files:")
for path in expected_paths:
    print(f"- {path}")

print()
print("Blueprint status:")
for path in expected_paths:
    blueprint = blueprints.get(path)
    status = blueprint.status if blueprint else "missing"
    print(f"- {path}: {status}")

missing = [path for path in expected_paths if path not in blueprints]

unknown = [
    blueprint for blueprint in blueprints.values() if blueprint.status == "unknown"
]

failed = [
    blueprint
    for blueprint in blueprints.values()
    if blueprint.status not in ["successful", "unknown"]
]

if missing:
    print()
    print("Blueprints are not discovered yet:")
    for path in missing:
        print(f"- {path}")
    exit(2)

if unknown:
    print()
    print("Blueprints are still pending:")
    for blueprint in unknown:
        print(f"- {blueprint.path}: {blueprint.status}")
    exit(2)

if failed:
    print()
    print("Failing blueprints:")
    for blueprint in failed:
        print(f"- {blueprint.path}: {blueprint.status}")
    exit(1)

print()
print("All active custom blueprints are successful.")
exit(0)
