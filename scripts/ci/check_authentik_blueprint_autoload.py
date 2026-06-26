from __future__ import annotations

import os
import time
from pathlib import Path
from sys import exit

from authentik.blueprints.models import BlueprintInstance

BLUEPRINT_ROOT = Path("/blueprints/custom")

SUCCESS_STATUS = "successful"
PENDING_STATUSES = {"unknown"}


def getenv_int(name: str, default: int) -> int:
    value = os.getenv(name)

    if value is None:
        return default

    try:
        return int(value)
    except ValueError:
        print(f"{name} must be an integer, got: {value}")
        exit(1)


def get_expected_paths() -> list[str]:
    return sorted(f"custom/{path.name}" for path in BLUEPRINT_ROOT.glob("*.yaml"))


def print_snapshot(
    expected_paths: list[str],
    instances: dict[str, BlueprintInstance],
    stable_success_count: int,
    stable_success_required: int,
) -> None:
    print("Expected active custom blueprint files:")
    for path in expected_paths:
        print(f"- {path}")

    print()
    print("Observed custom BlueprintInstance rows:")
    for path in sorted(instances):
        blueprint = instances[path]
        print(f"- {path}: {blueprint.status}")

    print()
    print(f"Stable successful polls: {stable_success_count}/{stable_success_required}")


def main() -> None:
    timeout_seconds = getenv_int("AUTHENTIK_BLUEPRINT_AUTOLOAD_TIMEOUT_SECONDS", 300)
    poll_seconds = getenv_int("AUTHENTIK_BLUEPRINT_AUTOLOAD_POLL_SECONDS", 5)
    stable_success_required = getenv_int("AUTHENTIK_BLUEPRINT_STABLE_POLLS", 3)

    deadline = time.monotonic() + timeout_seconds
    stable_success_count = 0

    while True:
        expected_paths = get_expected_paths()

        if not expected_paths:
            print("No active blueprint files found in /blueprints/custom/*.yaml")
            exit(1)

        expected_set = set(expected_paths)

        instances = {
            blueprint.path: blueprint
            for blueprint in BlueprintInstance.objects.filter(
                path__startswith="custom/"
            ).order_by("path")
        }

        observed_set = set(instances)

        missing_paths = sorted(expected_set - observed_set)
        unexpected_paths = sorted(observed_set - expected_set)

        failed_blueprints = [
            blueprint
            for path, blueprint in instances.items()
            if path in expected_set
            and blueprint.status not in {SUCCESS_STATUS, *PENDING_STATUSES}
        ]

        pending_blueprints = [
            blueprint
            for path, blueprint in instances.items()
            if path in expected_set and blueprint.status in PENDING_STATUSES
        ]

        all_successful = (
            not missing_paths
            and not unexpected_paths
            and not failed_blueprints
            and not pending_blueprints
        )

        print()
        print("== Authentik custom blueprint autoload check ==")
        print_snapshot(
            expected_paths,
            instances,
            stable_success_count,
            stable_success_required,
        )

        if unexpected_paths:
            print()
            print("Unexpected custom BlueprintInstance rows found:")
            for path in unexpected_paths:
                print(f"- {path}")

            print()
            print(
                "This usually means nested/archive blueprint files were discovered, "
                "or the test database is not clean."
            )
            exit(1)

        if failed_blueprints:
            print()
            print("Custom blueprints returned errors:")
            for blueprint in failed_blueprints:
                print(f"- {blueprint.path}: {blueprint.status}")
            exit(1)

        if all_successful:
            stable_success_count += 1

            if stable_success_count >= stable_success_required:
                print()
                print(
                    "All active custom blueprints were automatically loaded successfully."
                )
                exit(0)
        else:
            stable_success_count = 0

            if missing_paths:
                print()
                print("Custom blueprints are not discovered yet:")
                for path in missing_paths:
                    print(f"- {path}")

            if pending_blueprints:
                print()
                print("Custom blueprints are still pending:")
                for blueprint in pending_blueprints:
                    print(f"- {blueprint.path}: {blueprint.status}")

        if time.monotonic() >= deadline:
            print()
            print("Timed out waiting for custom blueprints to auto-load successfully.")
            exit(1)

        print()
        print(f"Waiting {poll_seconds}s before checking again...")
        time.sleep(poll_seconds)


main()
