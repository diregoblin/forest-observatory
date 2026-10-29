#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
redot_bin="${REDOT_BIN:-/home/pavel/.local/opt/redot-26.3/redot.linuxbsd.editor.x86_64}"
for arg in "$@"; do
  if [[ "$arg" == "--editor" || "$arg" == "--import" ]]; then
    redot_bin="${REDOT_BIN:-/home/pavel/.local/opt/redot-26.3/redot.linuxbsd.editor.x86_64}"
  fi
done
if [[ ! -x "$redot_bin" ]]; then
  printf 'Redot not found: %s\nSet REDOT_BIN to a Redot 26.3+ editor.\n' "$redot_bin" >&2
  exit 1
fi
if [[ ! -f "$project_root/addons/forest_hydro/bin/libforest_hydro.so" ]]; then
  printf 'Native hydrology is not built. Run: %s/tools/build_hydro.sh\n' "$project_root" >&2
  exit 1
fi
exec "$redot_bin" --path "$project_root" "$@"
