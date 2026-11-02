extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: ForestSettings = load("res://data/forest.tres").duplicate(true)
	settings.terrain_resolution = 32
	settings.water_resolution = 16
	settings.extent = 64
	var land := ForestLandscape.new(settings)
	var water := ForestWatershed.new(land)
	water.depth.fill(0)
	var view := ForestWaterView.new()
	root.add_child(view)
	view.configure(water)
	assert(view.mesh == null and view.chunk_grid == 8 and view.chunks.size() == 64)
	for chunk in view.chunks:
		assert(not chunk.visible)
		assert(chunk.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert(chunk.mesh == view.chunks[0].mesh)
		assert(chunk.material_override == view.material_override)
	# Bilinear wet support on a chunk seam must keep both neighbouring chunks.
	water.depth[7 * 16 + 7] = 1
	view.refresh()
	assert(view.chunks[3 * 8 + 3].visible and view.chunks[4 * 8 + 4].visible)
	view.advance_display(.1)
	water.depth.fill(0)
	view.refresh()
	assert(view.chunks[3 * 8 + 3].visible, "Previous sample still supports interpolated water")
	view.advance_display(5)
	view.refresh()
	for chunk in view.chunks:
		assert(not chunk.visible, "No stale wet chunks after both endpoints become dry")
	# Interrupt an unfinished blend: its next previous endpoint must be exactly
	# the displayed surface, not the old target. Try irregular upload intervals.
	for interval in [.7, .19, 1.2]:
		water.depth.fill(.25)
		view.refresh(true)
		water.depth.fill(1.0)
		view.refresh()
		view.advance_display(interval)
		var alpha: float = view.material_override.get_shader_parameter("display_alpha")
		assert(alpha > 0.0 and alpha < 1.0)
		var displayed := lerpf(.25, 1.0, alpha)
		view.advance_display(0.0)
		assert(view.material_override.get_shader_parameter("display_alpha") == alpha)
		water.depth.fill(2.0)
		view.refresh()
		assert(absf(view.previous_image.get_pixel(0, 0).r - displayed) < .000001)
		assert(is_equal_approx(view.sample_interval, interval))
		assert(view.material_override.get_shader_parameter("display_alpha") == 0.0)
		view.advance_display(interval * .99)
		var nearly: float = view.material_override.get_shader_parameter("display_alpha")
		view.advance_display(interval * .01)
		var later: float = view.material_override.get_shader_parameter("display_alpha")
		assert(later > nearly and later < 1.0, "No early plateau before the next upload")
	# A restored/paused world must display its own depth immediately.
	water.depth.fill(.4)
	view.refresh(true)
	assert(view.previous_image.get_pixel(0, 0) == view.current_image.get_pixel(0, 0))
	assert(view.material_override.get_shader_parameter("display_alpha") == 1.0)
	# Independent reference: sample the actual positive bilinear stencil through
	# several temporal blends, including edges, rather than repeating the halo rule.
	var current := PackedFloat64Array()
	var previous := PackedFloat64Array()
	current.resize(16 * 16)
	previous.resize(16 * 16)
	for i in current.size():
		current[i] = .7 if i % 23 == 0 else 0
		previous[i] = .2 if i % 37 == 0 else 0
	var mask := ForestWaterView.wet_chunks(
		ForestWaterView._support(current), ForestWaterView._support(previous), 16, 8
	)
	var checked := 0
	for alpha in [0.0, .25, 1.0]:
		for z in 64:
			for x in 64:
				var q := Vector2((x + .37) / 4, (z + .61) / 4) - Vector2(.5, .5)
				var cell := Vector2i(q.floor())
				var f := q - q.floor()
				var support := 0.0
				for dz in 2:
					for dx in 2:
						var i := clampi(cell.y + dz, 0, 15) * 16 + clampi(cell.x + dx, 0, 15)
						var d := lerpf(previous[i], current[i], alpha)
						if d >= .001:
							support += (f.x if dx == 1 else 1 - f.x) * (f.y if dz == 1 else 1 - f.y)
				if support > .001:
					assert(
						mask[(z / 8) * 8 + x / 8] == 1, "Chunk culling removed wet bilinear support"
					)
				checked += 1
	view.free()
	FileAccess.open("res://artifacts/water-chunks-check.json", FileAccess.WRITE).store_string(
		JSON.stringify({"passed": true, "stencil_samples": checked, "irregular_blends": 3})
	)
	print(
		"WATER_CHUNKS passed: shared lattice/material, dry cull, temporal/seam halo; samples=",
		checked
	)
	quit()
