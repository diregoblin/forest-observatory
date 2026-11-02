extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func sum_field(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values:
		result += value
	return result


func owned_total(state: Dictionary, key: String) -> float:
	var result := sum_field(state.cells[key])
	for patch in state.patches:
		result += sum_field(patch[key])
	return result


static func run_world(world) -> void:
	world.paused = true
	world.water_view.visible = false  # Restore an unusual pre-existing visibility too.
	var frozen: Dictionary = world._world_snapshot().models
	var fog: bool = world.atmosphere.world_env.fog_enabled
	var v := InputEventKey.new()
	v.pressed = true
	v.physical_keycode = KEY_V
	world._unhandled_input(v)
	assert(world.hud.soil_layers.visible and not world.vegetation.visible)
	assert(not world.atmosphere.world_env.fog_enabled)
	for index in ForestSoilLayers.LAYERS.size():
		world.hud.soil_layers.selector.item_selected.emit(index)
		assert(world.hud.soil_layers.selected == index)
		assert(world.hud.soil_layers.field_texture != null)
	assert(
		world._world_snapshot().models == frozen, "Switching layers cannot advance/change models"
	)
	world.hud.soil_layers.hide_cover.button_pressed = false
	assert(world.vegetation.visible and not world.water_view.visible)
	world.hud.soil_layers.hide_cover.button_pressed = true
	assert(not world.vegetation.visible)
	world._toggle_soil_layers()
	assert(not world.hud.soil_layers.visible)
	assert(world.vegetation.visible and not world.water_view.visible)
	assert(not world.terrain.material.get_shader_param("soil_layer_enabled"))
	assert(world.atmosphere.world_env.fog_enabled == fog)
	world._toggle_soil_layers()
	world.hud.toggle_fungi_map()
	assert(not world.hud.soil_layers.visible and world.hud.fungi_map.visible)
	world.hud.toggle_fungi_map()
	world.use_model_worker = true
	world.paused = false
	world._process(world.settings.ecology_step_s)
	assert(world.model_work_active)
	world._toggle_soil_layers()
	assert(not world.model_work_active, "Layer open joins the in-flight tick")
	world._check_clock_alignment()
	world.paused = true
	var saved: Dictionary = world._world_snapshot()
	world._advance_world(world.settings.ecology_step_s)
	assert(world._restore_world(saved))
	var index: int = world.hud.soil_layers.selected
	assert(
		(
			world.hud.soil_layers.values
			== ForestSoilLayers.field_values(index, world.soil, world.water)
		)
	)
	world._toggle_soil_layers()
	world.water_view.visible = true
	var report := {
		"passed": true,
		"layer_controls": true,
		"worker_join": true,
		"view_visibility_restored": true,
		"maps_mutually_exclusive": true,
		"save_load_refreshes_layer": true,
		"model_state_unchanged_by_view": true
	}
	FileAccess.open("res://artifacts/soil-layers-controls.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("SOIL_LAYERS_CONTROLS ", JSON.stringify(report))


func _run() -> void:
	var config: ForestSettings = load("res://data/forest.tres").duplicate(true)
	config.water_resolution = 8
	config.headwater_length = config.extent
	config.headwater_width = config.extent
	var water := ForestWatershed.new(ForestLandscape.new(config))
	var soil := ForestSoil.new(water)
	var dx := water.cell_size
	# Partial coarse-cell coverage, with fine cells away from its centre.
	var before: PackedFloat64Array = soil.native.diagnostic_field(6)
	assert(soil.native.add_patch(4, dx / 4, dx * .25, dx * .25) == 0)
	var after: PackedFloat64Array = soil.native.diagnostic_field(6)
	for k in before.size():
		assert(absf(before[k] - after[k]) < 1e-12, "Refinement must not erase/double reserves")
	var point := Vector3(dx * .375, 0, dx * .375)
	soil.deposit_elements(point, 0, 7, .7, false)
	var changed: PackedFloat64Array = soil.native.diagnostic_field(6)
	assert(absf((changed[0] - after[0]) * water.cell_area - 7) < 1e-10)
	assert(soil.native.diagnostic_field(-1).is_empty())
	assert(soil.native.diagnostic_field(9).is_empty())
	var saved := soil.snapshot()
	var water_saved: Dictionary = water.native.snapshot()
	var top_before := water.top_water_m.duplicate()
	for index in ForestSoilLayers.LAYERS.size():
		var layer: Dictionary = ForestSoilLayers.LAYERS[index]
		var values := ForestSoilLayers.field_values(index, soil, water)
		assert(values.size() == water.resolution * water.resolution)
		if layer.has("water"):
			var original: PackedFloat64Array = water.get(layer.water)
			for k in values.size():
				assert(values[k] == original[k] * 1000, "Metres to mm, never saturation")
		elif layer.has("rate"):
			for k in values.size():
				assert(values[k] == water.seepage_m_s[k] * 3600000.0)
		elif layer.has("sources"):
			assert(
				absf(sum_field(values) / 1000 - water.native.snapshot().options.source_m3_s) < 1e-12
			)
		else:
			var expected := owned_total(saved, layer.key)
			var actual := sum_field(values) / 1000 * water.cell_area
			assert(absf(expected - actual) < 1e-8, "Map integral equals every actual owner")
			# Checker must reject a tempting wrong implementation: coarse only.
			if layer.field == 6:
				var wrong := sum_field(saved.cells.mineral_n)
				assert(absf(wrong - expected) > 7)
	assert(water.top_water_m == top_before)
	assert(soil.snapshot() == saved and water.native.snapshot() == water_saved)
	assert(is_equal_approx(ForestSoilLayers.scale_limit(0, config.soil_profile), 67.5))
	assert(is_equal_approx(ForestSoilLayers.scale_limit(1, config.soil_profile), 270))
	assert(is_equal_approx(ForestSoilLayers.scale_limit(2, config.soil_profile), 270))
	assert(ForestSoilLayers.color_for(0, 1) == ForestSoilLayers.LOW)
	assert(ForestSoilLayers.color_for(.5, 1) == ForestSoilLayers.MID)
	assert(ForestSoilLayers.color_for(99, 1) == ForestSoilLayers.HIGH)
	var panel := ForestSoilLayers.new()
	root.add_child(panel)
	panel.configure()
	panel.visible = true
	panel.selected = 9
	panel.refresh(soil, water)
	panel.map.size = Vector2(256, 256)
	var hover := InputEventMouseMotion.new()
	hover.position = Vector2(1, 1)
	panel._map_input(hover)
	assert(panel.hovered_cell == 0 and panel.sample_label.text.contains("г/м²"))
	assert(panel.values[0] == changed[0] * 1000)
	var pixel := panel.field_texture.get_image().get_pixel(0, 0)
	var expected_color := ForestSoilLayers.color_for(panel.values[0], panel.limit)
	assert(absf(pixel.r - expected_color.r) <= 1.0 / 255)
	assert(absf(pixel.g - expected_color.g) <= 1.0 / 255)
	assert(absf(pixel.b - expected_color.b) <= 1.0 / 255)
	assert(soil.snapshot() == saved and water.native.snapshot() == water_saved)
	panel.free()
	var report := {
		"passed": true,
		"layers": ForestSoilLayers.LAYERS.size(),
		"fine_owner_projection_integral": true,
		"coarse_only_wrong_case_rejected": true,
		"water_unit_conversion_read_only": true,
		"fixed_scales": true,
		"hover_and_cell_colour": true
	}
	FileAccess.open("res://artifacts/soil-layers-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("SOIL_LAYERS_CHECK ", JSON.stringify(report))
	quit()
