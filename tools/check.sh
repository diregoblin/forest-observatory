#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
mkdir -p artifacts
./tools/build_hydro.sh > artifacts/native-build.log 2>&1
native/build/hydro_checks > artifacts/native-check.json
native/build/hydro_checks --benchmark > artifacts/native-benchmark.json
native/build/fungi_checks > artifacts/fungi-native-check.json
./tools/run.sh --headless --editor --import --quit > artifacts/import.log 2>&1
python - <<'PY'
from pathlib import Path
for name in ('water-check.json', 'contracts.json', 'controls.json', 'ecology-check.json', 'fungi-check.json'):
    Path('artifacts', name).unlink(missing_ok=True)
PY
timeout 90 ./tools/run.sh --headless --script res://tools/check_water.gd > artifacts/water-check.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_contracts.gd > artifacts/contracts.log 2>&1
timeout 90 ./tools/run.sh --headless --script res://tools/check_ecology.gd > artifacts/ecology-check.log 2>&1
timeout 90 ./tools/run.sh --headless --script res://tools/check_fungi.gd > artifacts/fungi-check.log 2>&1
timeout 30 ./tools/run.sh --headless -- --check-controls > artifacts/smoke.log 2>&1
python - <<'PY'
import json
from pathlib import Path
root = Path('artifacts')
for name in ('native-check', 'water-check', 'contracts', 'ecology-check', 'fungi-native-check', 'fungi-check', 'controls'):
    result = json.loads((root / (name + '.json')).read_text())
    assert result.get('passed') is True, (name, result)
for name in ('water-check.log', 'contracts.log', 'ecology-check.log', 'fungi-check.log', 'smoke.log'):
    log = (root / name).read_text()
    assert 'ERROR:' not in log, (name, log[-4000:])
editor_log = (root / 'import.log').read_text()
assert 'SCRIPT ERROR' not in editor_log and 'Failed to load' not in editor_log
print('PASS: water, fungi, extension contracts, scene/control signals')
PY
