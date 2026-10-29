#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
xvfb_bin="${XVFB_BIN:-$project_root/.preview-tools/usr/bin/Xvfb}"
if [[ ! -x "$xvfb_bin" ]]; then
  printf 'Set XVFB_BIN to an existing Xvfb binary. No system packages are installed by this script.\n' >&2
  exit 1
fi
mkdir -p artifacts
display_file="$(mktemp "$project_root/artifacts/.xvfb-display.XXXXXX")"
"$xvfb_bin" -displayfd 3 -screen 0 1440x900x24 -nolisten tcp -noreset -ac 3> "$display_file" > artifacts/xvfb.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -f -- "$display_file"' EXIT
for attempt in {1..100}; do
  [[ -s "$display_file" ]] && break
  kill -0 "$server_pid" 2>/dev/null || { cat artifacts/xvfb.log >&2; exit 1; }
  sleep .05
done
[[ -s "$display_file" ]]
preview_display=":$(cat "$display_file")"
DISPLAY="$preview_display" XAUTHORITY=/dev/null "$project_root/tools/preview.sh" --display-driver x11 "$@"
