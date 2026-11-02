#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
redot_bin="${REDOT_BIN:-/home/pavel/.local/opt/redot-26.3/redot.linuxbsd.editor.x86_64}"
output_dir="$project_root/artifacts/water-gpu-preview"
mkdir -p "$output_dir"
# A bounded, visible laboratory assay. Does not load or save the user's world.
# Fixed guard ceiling; no thermal soak or unattended interactive run.
exec timeout --foreground 35s python3 "$project_root/tools/gpu_guard.py" \
  --limit-c 65 --log "$output_dir/guard.jsonl" -- \
  "$redot_bin" --path "$project_root" --audio-driver Dummy \
  --script res://tools/probe_gpu_water.gd -- \
  --closeup --samples=120 --counts=8192,16384,32768,40000 \
  --output=res://artifacts/water-gpu-preview "$@"
