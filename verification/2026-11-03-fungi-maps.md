# Nearest fungal plot and multiscale soil diagnostics

Pavel requested that G follow the nearest fungal plot, and that V show the
actual 25 × 25 cm soil cells under fungi alongside the surrounding 4 × 4 m grid.
No separate plot outline was requested: only the change in grid spacing.

## Implementation

- G selects the nearest plot centre in horizontal XZ distance to the observer
  camera, including on pause. Its heading identifies the plot and species.
  Camera-only changes use submitted display dictionaries, never native models
  owned by an in-flight worker. Scale for R comes from the selected definition.
- All nine soil-stock layers of V show actual coarse remainder densities outside
  fine patches and actual fine-owner densities inside. The existing coarse
  aggregate remains available for area-integral checks, but is NOT used as a
  partially covered coarse cell's displayed background.
- A sparse 128 × 384 colour atlas holds the three shipped fine patches (49,152
  pixels), with a tiny floating-point layout texture. There is no 2048 × 2048
  whole-world expansion and no interpolated substitute for a fine reserve.
- Terrain and HUD share `shaders/soil_diagnostic.gdshaderinc`, one fixed colour
  scale, nearest-cell sampling, and a distance-faded grid. No outline or added
  colour band is drawn at plot boundaries. Subpixel grid lines fade out.
- Water layers remain on their actual 4 m solver grid. Hover reports the real
  owner's stock in g/m² and actual cell size; fine and coarse values are sampled
  from submitted copies. Soil C/N/P ownership, kinetics and save format do not
  change. Existing saves remain compatible; an existing live window is not reset.

## Checks

- `tools/check_soil_layers.gd`: independent area-integral checks against native
  saved stocks for all nine fields; fine atlas/hover versus owner sampling;
  rejects coarse averaging as a fine-cell value; verifies partial coarse
  remainders outside patches, plus water/no-refinement control.
- `tools/check_fungi_maps.gd`: all three species, camera-only switching on pause,
  actual biomass texture values, sparse atlas size, native labile-C samples,
  water fallback, byte-identical model snapshots before/after viewing, and a
  camera-only switch during an active worker. Runs headless in `tools/check.sh`
  and separately in real Forward+ for screenshots.
- Forward+ images/reports: `artifacts/fungi-maps/`; no user saves, application
  window, engine installation or unrelated project is modified. Run via
  `tools/preview_isolated.sh` and its normal GPU watchdog.

## Results

- Targeted soil-layer test: PASS for all nine stock fields, fine-owner colours and
  samples, partial coarse remainders, conservation and water/no-refinement control.
- Full set: 39 engine invocations and three native cores completed successfully;
  `artifacts/fine-grid-final-validation.log` records the final collector PASS.
  The first collector correctly rejected the new headless probe's premature exit.
  Its lifetime was fixed with explicit `--check-fungi-maps`; reports are now
  removed before the suite and the collector requires a fresh headless report and
  the probe's own success marker. That probe and the collector were repeated,
  rather than rerunning the unaffected numerical suites.
- Dummy is not a GPU readback: subsequent `ImageTexture.update` contents and
  Terrain3D shader uniforms are checked only in real Forward+. Headless still
  checks all nearest-plot labels, fine sampling, submitted copies, byte-identical
  model state and an explicitly enabled worker. Reports record `display_server`
  and `gpu_texture_checks` so a configured rendering method is not mistaken for
  an actual Vulkan run.
- `gdlint` for the four touched/new leaf scripts and `git diff --check`: PASS.
  Documentation links resolve. The soil-grid image is a real read-only capture.

- Final real Forward+ rerun: PASS with GPU texture/uniform checks, all three
  plots, pause, busy-worker and unchanged model snapshots. Receipt:
  `artifacts/fungi-maps/render-report.json`; screenshots inspected visually.
