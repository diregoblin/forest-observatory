#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$project_root/artifacts"
exec "$project_root/tools/run.sh" --audio-driver Dummy "$@" -- --capture="$project_root/artifacts"
