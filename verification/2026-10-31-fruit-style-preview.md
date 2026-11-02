# Fruit geometry and isolated style preview

- Four heads × seven berries replace rowan/guelder-rose horizontal rings, using the shared data-driven mesh builder. No added stem geometry remains.
- Pre-change vs final built vertices: rowan 5208/5208, guelder rose 6072/6072. Equal triangles do not establish equal FPS.
- Final `tools/check_contracts.gd`: passed, including third-species shared builder and read-only cover.
- Actual Forward+ `tools/preview_fruit.gd`: screenshots inspected in artifacts/fruit-*-budget.png; vertex measurements in artifacts/fruit-geometry-budget.json.
- `tools/preview_style.gd`: isolated static project-mesh grove A/B + restored original sky/material checks passed. Prototype sky is 2D sheets. Full-valley validation is outstanding; initial full scene capture crashed before style activation with a thread-access error/signal 11.
- All captures used CPU llvmpipe due to an NVIDIA module/userspace mismatch after a system update. No hardware FPS claim.
- The painterly hook is NOT in normal forest startup; scripts/forest.gd is unchanged by this task. Prototype only has the separate preview entry point.
- Full details and exact pre-task dirty rollback copies: /run/media/pavel/Storage/Yandex.Disk/OpenClaw-workspace/output/forest-render-style-20261031/README.md.

Reproduce isolated morphology: `./tools/preview_isolated.sh --script res://tools/preview_fruit.gd -- --fruit-label=after`.
For the optional geometry comparison, append `--fruit-baseline=/absolute/path/to/pre-change/data/plants`.
Reproduce isolated style: `./tools/preview_isolated.sh --script res://tools/preview_style.gd`.
Do not run more performance previews until the NVIDIA backend is restored.
