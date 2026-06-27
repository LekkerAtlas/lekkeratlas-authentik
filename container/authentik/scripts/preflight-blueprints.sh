#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/lekkeratlas/common.sh

blueprint_root="${AUTHENTIK_BLUEPRINT_VALIDATE_ROOT:-/blueprints/custom}"

if [[ ! -d "$blueprint_root" ]]; then
  log "Blueprint validation root does not exist: ${blueprint_root}"
  exit 0
fi

log "Validating blueprint YAML syntax in ${blueprint_root}"

python3 - "$blueprint_root" <<'PY'
from pathlib import Path
import os
import re
import sys
import yaml

root = Path(sys.argv[1])
check_env = os.environ.get("AUTHENTIK_BLUEPRINT_PREFLIGHT_CHECK_ENV", "false").lower() in {
    "true",
    "1",
    "yes",
    "y",
}

files = sorted(root.rglob("*.yaml")) + sorted(root.rglob("*.yml"))

if not files:
    print(f"No blueprint YAML files found in {root}", file=sys.stderr)
    raise SystemExit(0)

failed = False
required_env_vars: set[str] = set()

for path in files:
    text = path.read_text()

    try:
        # Syntax-only validation. This accepts custom YAML tags such as:
        # !Find, !Env, !KeyOf, !Format, etc.
        yaml.compose(text)
    except yaml.YAMLError as error:
        print("", file=sys.stderr)
        print(f"Invalid YAML: {path}", file=sys.stderr)
        print(error, file=sys.stderr)
        failed = True

    if check_env:
        for match in re.finditer(r"!Env\s+([A-Za-z_][A-Za-z0-9_]*)", text):
            required_env_vars.add(match.group(1))

if check_env:
    missing_env_vars = sorted(
        name for name in required_env_vars
        if os.environ.get(name) in (None, "")
    )

    if missing_env_vars:
        print("", file=sys.stderr)
        print("Missing environment variables referenced by blueprint !Env tags:", file=sys.stderr)
        for name in missing_env_vars:
            print(f"- {name}", file=sys.stderr)
        failed = True

if failed:
    raise SystemExit(1)

print(f"Validated {len(files)} blueprint YAML file(s).")
PY
