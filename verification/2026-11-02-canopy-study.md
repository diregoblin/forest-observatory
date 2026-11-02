# Canopy / palette / light study — 2026-11-02

## Reference and source boundary

Pavel's reference: https://x.com/WrongNebula/status/2117235538713559052/photo/1
Public demo linked by that post: https://tokyo2100.vercel.app/ (Kirizakadai 2100).
The post describes combining a procedural Japanese city, Ghibli textures and a
plant grower in Three.js. The photo was actually inspected; the demo's page text
was fetched through Firecrawl, **not interactively explored**.

An exact-source repository was **not confirmed**. GitHub repository search for
`tokyo 2100` found `ashleyURSx/tokyonodes`, but commit
`066d474e370f618b66349921dba418696408b44f` contained only an unrelated DOCX
instruction document, not this demo. It is a false match and must not be cited
as the author's implementation. Direct local TLS access to the demo failed;
the available browser host was unavailable. Do not infer any exact shader,
normal technique or license from the screenshot. No external code was copied
or executed; the prototype below is an independent visual interpretation.

## Bounded experiment

New isolated files only:

- `shaders/study_canopy.gdshader`
- `tools/preview_canopy_study.gd`

The normal world is not wired to these files. Its materials, species resources,
model code and user saves are unchanged. Source species are deep-copied, and
rebuilding the originals after the variant must produce identical mesh bytes.

Three columns show the same birch/oak definition under the same environment:

1. Existing painterly shader and original geometry.
2. Original geometry with a new palette/light/painted-leaf treatment.
3. The same new material plus mildly lobed volumes and fixed leaf-shaped plates.

This separates the **combined material treatment** from added geometry; it does
not isolate palette alone from lighting alone. The plates are world-fixed, not
camera-facing, and their normals mostly follow the volume of the crown. A
coarser shadows-only body supplies the crown's shadow instead of hundreds of
small plates casting noisy pinhole shadows. Study SSAO is off, MSAA is 4×;
these are local study settings, not changes to the live forest environment.

The shader uses object-anchored triplanar elliptical marks with derivative
fading. Its warm/cool direct-light response depends on the actual normal and
light direction; golden marks are attenuated in shade instead of being yellow
emissive dots. This is a hypothesis for reproducing the **look**, not a reverse
engineering claim about WrongNebula's shader.

Success/falsifier chosen for the functional study: directional light changes
must visibly affect the crown; replacing its normal field with one uniform
world normal must remove/change the volume-dependent lighting. An unchanged
picture would fail. Both controls ran through the same Forward+ pipeline.
Image difference is only a smoke check, not a style-similarity score.

## Results and judgement

Eight Forward+ images captured after `RenderingServer.frame_post_draw`:
left/right light, flat-normal control and an oblique camera for each species.
`artifacts/canopy-study/report.json` passed functional checks; latest execution
log: `artifacts/canopy-study-finish.log`. GDScript formatting/lint passed.

- [Birch comparison](../artifacts/canopy-study/birch-01-left-light.png)
- [Oak comparison](../artifacts/canopy-study/oak-02-right-light.png)
- [Oak flat-normal control](../artifacts/canopy-study/oak-03-flat-normal-control.png)
- [Oak oblique view](../artifacts/canopy-study/oak-04-oblique.png)

Observed: the palette/material variant is more muted in the cool areas and has
warm leaf marks on lit parts. The geometrical plates roughen the silhouette.
**It does not yet match the reference**: the few large original lobes remain
obvious, and the plate variant still looks too ragged. Do not promote this as
a finished Ghibli canopy or silently replace the main forest's materials.

Geometry counts (not performance measurements): birch 1,816 → 8,088 triangles;
oak 392 → 4,392, plus the separate coarse shadow proxy. The specimen study is
small. It proves neither forest-wide cost nor adequate close/far LoD behavior.
Before production adoption: species-specific silhouettes, phenology/snow/wind,
shared near/mid materials, rebaked far impostors, picking and pixel-style
readability would need relevant checks. No live-world integration was attempted.

### Reference colour observations

A selected crown crop of the downloaded photo (RGB screenshot, not linear
material albedo) gave rough median colour families after explicit colour masks:

| Family | Approximate displayed sRGB |
|---|---|
| Cool green/shadow | `#5b6b59` |
| Green midtone | `#65735b` |
| Golden foliage | `#a0965c` |

These are crop/mask-dependent observations, not recovered source uniforms.
Screenshot colours already contain lighting, exposure and grading. Copying
these values into material albedo without balancing the environment would
apply lighting twice. For a full palette, develop coordinated sky/fill/shadow,
foliage, soil and stone colour families rather than a single global tint.

## Reproduce and limits

```
GPU_GUARD_LOG=artifacts/canopy-study-finish-gpu.jsonl \
  ./tools/preview_isolated.sh --script res://tools/preview_canopy_study.gd
```

All render launches retained the 75 °C fail-closed guard. Final run max 60 °C, normal exit 0. Short, stationary
specimen previews only; no sustained FPS, temperature, physical/ecological
validation or identical-author-technique claim. No new runtime dependencies,
services, active-world changes or user-save writes.
