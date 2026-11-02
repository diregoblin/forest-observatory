#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
mkdir -p artifacts
./tools/build_hydro.sh > artifacts/native-build.log 2>&1
native/build/hydro_checks > artifacts/native-check.json
native/build/hydro_checks --benchmark > artifacts/native-benchmark.json
native/build/fungi_checks > artifacts/fungi-native-check.json
native/build/soil_checks > artifacts/soil-native-check.json
./tools/run.sh --headless --editor --import --quit > artifacts/import.log 2>&1
python - <<'PY'
from pathlib import Path
for name in ('fungi-maps/report.json', 'fungi-maps/headless-report.json', 'spring-check.json', 'water-chunks-check.json', 'timeline-debt-check.json', 'animal-fastpath-check.json', 'native-plant-light-check.json', 'herb-geometry-check.json', 'fauna-geometry-check.json', 'bird-flight-check.json', 'terrain-upgrade-check.json'):
    Path('artifacts', name).unlink(missing_ok=True)
for name in ('water-check.json', 'contracts.json', 'controls.json', 'ecology-check.json', 'fungi-check.json', 'understory-check.json', 'animals-check.json', 'population-check.json', 'animal-behaviour-check.json', 'fungus-pick-check.json', 'observation-check.json', 'world-check.json', 'ecosystem-check.json', 'worker-check.json', 'weather-habitat-check.json', 'initial-deadwood-check.json', 'animal-motion-check.json', 'food-web-check.json', 'place-memory-check.json', 'soil-layers-check.json', 'soil-layers-controls.json', 'boars-check.json', 'detail-distance-check.json', 'site-surface-check.json'):
    Path('artifacts', name).unlink(missing_ok=True)
PY
timeout 45 ./tools/run.sh --headless --script res://tools/check_spring.gd > artifacts/spring-check.log 2>&1
timeout 90 ./tools/run.sh --headless --script res://tools/check_water.gd > artifacts/water-check.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_water_chunks.gd > artifacts/water-chunks-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_native_plant_light.gd > artifacts/native-plant-light-check.log 2>&1
timeout 90 ./tools/run.sh --headless --script res://tools/check_timeline_debt.gd > artifacts/timeline-debt-check.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_contracts.gd > artifacts/contracts.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_terrain_upgrade.gd > artifacts/terrain-upgrade-check.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_canopy.gd > artifacts/canopy-check.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_herb_geometry.gd > artifacts/herb-geometry-check.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_plant_lod.gd > artifacts/plant-lod-check.log 2>&1
timeout 90 ./tools/run.sh --headless --script res://tools/check_ecology.gd > artifacts/ecology-check.log 2>&1
timeout 90 ./tools/run.sh --headless --script res://tools/check_fungi.gd > artifacts/fungi-check.log 2>&1
timeout 90 ./tools/run.sh --headless --script res://tools/check_understory.gd > artifacts/understory-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_ecosystem.gd > artifacts/ecosystem-check.log 2>&1
timeout 25 ./tools/run.sh --headless --script res://tools/check_bird_flight.gd > artifacts/bird-flight-check.log 2>&1
timeout 40 ./tools/run.sh --headless --script res://tools/check_fauna_geometry.gd > artifacts/fauna-geometry-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_animals.gd > artifacts/animals-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_animal_fastpath.gd > artifacts/animal-fastpath-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_animal_spawn.gd > artifacts/animal-spawn-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_population.gd > artifacts/population-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_animal_behaviour.gd > artifacts/animal-behaviour-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_weather_habitat.gd > artifacts/weather-habitat-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_initial_deadwood.gd > artifacts/initial-deadwood-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_place_memory.gd > artifacts/place-memory-check.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_soil_layers.gd > artifacts/soil-layers-check.log 2>&1
timeout 90 ./tools/run.sh --headless --script res://tools/check_fungi_maps.gd -- --check-fungi-maps > artifacts/fungi-maps-check.log 2>&1
timeout 45 ./tools/run.sh --headless -- --check-soil-layers > artifacts/soil-layers-controls.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_detail_distance.gd > artifacts/detail-distance-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_site_surface.gd > artifacts/site-surface-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_smooth_motion.gd > artifacts/smooth-motion-headless.log 2>&1
timeout 20 ./tools/run.sh --headless --script res://tools/check_animal_motion.gd > artifacts/animal-motion-check.log 2>&1
timeout 25 ./tools/run.sh --headless --script res://tools/check_short_animal_motion.gd > artifacts/short-animal-motion-check.log 2>&1
timeout 45 ./tools/run.sh --headless --script res://tools/check_fungus_pick.gd > artifacts/fungus-pick-check.log 2>&1
timeout 30 ./tools/run.sh --headless --script res://tools/check_observation.gd > artifacts/observation-check.log 2>&1
timeout 45 ./tools/run.sh --headless -- --check-worker > artifacts/worker-check.log 2>&1
timeout 90 ./tools/run.sh --headless -- --check-boars > artifacts/boars-check.log 2>&1
timeout 90 ./tools/run.sh --headless -- --check-food-web > artifacts/food-web-check.log 2>&1
timeout 90 ./tools/run.sh --headless -- --check-world > artifacts/world-check.log 2>&1
timeout 90 ./tools/run.sh --headless -- --check-controls > artifacts/smoke.log 2>&1
python - <<'PY'
import json
from pathlib import Path
root = Path('artifacts')
for name in ('canopy-check', 'plant-lod-check', 'animal-spawn-check', 'short-animal-motion-check', 'water-chunks-check', 'timeline-debt-check', 'animal-fastpath-check', 'native-plant-light-check', 'herb-geometry-check', 'fauna-geometry-check', 'bird-flight-check', 'terrain-upgrade-check'):
    assert json.loads((root / (name + '.json')).read_text()).get('passed') is True
    assert 'ERROR:' not in (root / (name + '.log')).read_text()
for name in ('native-check', 'water-check', 'contracts', 'ecology-check', 'fungi-native-check', 'fungi-check', 'soil-native-check', 'understory-check', 'animals-check', 'observation-check', 'world-check', 'controls', 'ecosystem-check', 'worker-check'):
    result = json.loads((root / (name + '.json')).read_text())
    assert result.get('passed') is True, (name, result)
for name in ('spring-check', 'population-check', 'animal-behaviour-check', 'fungus-pick-check', 'weather-habitat-check', 'animal-motion-check', 'food-web-check', 'place-memory-check', 'soil-layers-check', 'soil-layers-controls', 'boars-check', 'detail-distance-check', 'site-surface-check'):
    result = json.loads((root / (name + '.json')).read_text())
    assert result.get('passed') is True, (name, result)
    assert 'ERROR:' not in (root / (name + '.log')).read_text()
for name in ('water-check.log', 'contracts.log', 'ecology-check.log', 'fungi-check.log', 'understory-check.log', 'animals-check.log', 'observation-check.log', 'world-check.log', 'smoke.log', 'ecosystem-check.log', 'worker-check.log'):
    log = (root / name).read_text()
    assert 'ERROR:' not in log, (name, log[-4000:])
editor_log = (root / 'import.log').read_text()
assert json.loads((root / 'fungi-maps/headless-report.json').read_text()).get('passed') is True
assert 'FUNGI_MAPS ' in (root / 'fungi-maps-check.log').read_text()
assert 'ERROR:' not in (root / 'fungi-maps-check.log').read_text()
assert json.loads((root / 'initial-deadwood-check.json').read_text()).get('passed') is True
assert 'ERROR:' not in (root / 'initial-deadwood-check.log').read_text()
assert 'SCRIPT ERROR' not in editor_log and 'Failed to load' not in editor_log
assert json.loads((root / 'smooth-motion/headless-report.json').read_text()).get('passed') is True
assert 'ERROR:' not in (root / 'smooth-motion-headless.log').read_text()
print('PASS: hydrology, shared soil, plant/fungi/animal models, observer, whole-world save and controls')
PY
