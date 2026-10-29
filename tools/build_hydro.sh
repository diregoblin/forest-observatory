#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
redot_bin="${REDOT_BIN:-/home/pavel/.local/opt/redot-26.3/redot.linuxbsd.editor.x86_64}"
bindings_commit=ef6e110918198417521d87335a1bb9d883f5a5a4
cd "$project_root"
mkdir -p native/api native/deps
if [[ ! -d native/deps/redot-cpp/.git ]]; then
  git clone --depth 1 --branch redot-26.3-stable https://github.com/Redot-Engine/redot-cpp.git native/deps/redot-cpp
fi
[[ "$(git -C native/deps/redot-cpp rev-parse HEAD)" == "$bindings_commit" ]] || {
  printf 'Unexpected redot-cpp revision; not modifying existing checkout.\n' >&2
  exit 1
}
engine_version="$("$redot_bin" --version)"
if [[ ! -f native/api/extension_api.json || ! -f native/api/gdextension_interface.h ||
      ! -f native/api/engine-version.txt || "$(cat native/api/engine-version.txt)" != "$engine_version" ]]; then
  (cd native/api && "$redot_bin" --headless --dump-extension-api --dump-gdextension-interface)
  printf '%s\n' "$engine_version" > native/api/engine-version.txt
fi
if [[ ! -f native/build/CMakeCache.txt ]]; then
  cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Release
fi
cmake --build native/build --parallel "${HYDRO_BUILD_JOBS:-4}"
# Atomic replacement preserves any library already mapped by a running game.
mkdir -p addons/forest_hydro/bin
if ! cmp -s native/build/lib/libforest_hydro.so addons/forest_hydro/bin/libforest_hydro.so; then
  staged_lib="addons/forest_hydro/bin/.libforest_hydro.$$.so"
  trap 'rm -f -- "$staged_lib"' EXIT
  cp native/build/lib/libforest_hydro.so "$staged_lib"
  mv -f -- "$staged_lib" addons/forest_hydro/bin/libforest_hydro.so
fi
