#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
mkdir -p artifacts
./tools/run.sh --headless --editor --import --quit > artifacts/import.log 2>&1
python - <<'PY'
from pathlib import Path
for name in ('water-check.json', 'contracts.json', 'controls.json'):
    Path('artifacts', name).unlink(missing_ok=True)
PY
timeout 90 ./tools/run.sh --headless --script res://tools/check_water.gd > artifacts/water-check.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_contracts.gd > artifacts/contracts.log 2>&1
timeout 30 ./tools/run.sh --headless -- --check-controls > artifacts/smoke.log 2>&1
python - <<'PY'
import json
from pathlib import Path
root = Path('artifacts')
for name in ('water-check', 'contracts', 'controls'):
    result = json.loads((root / (name + '.json')).read_text())
    assert result.get('passed') is True, (name, result)
for name in ('water-check.log', 'contracts.log', 'smoke.log'):
    log = (root / name).read_text()
    assert 'ERROR:' not in log, (name, log[-4000:])
editor_log = (root / 'import.log').read_text()
assert 'SCRIPT ERROR' not in editor_log and 'Failed to load' not in editor_log
print('PASS: water, extension contracts, scene/control signals')
PY
