extends Node

var world
var output := "res://artifacts/soil-layers-render"


func start(scene) -> void:
	world = scene
	_run.call_deferred()


func photo(label: String) -> void:
	for frame in 5:
		await RenderingServer.frame_post_draw
	assert(
		get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png")) == OK
	)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	world._finish_model_work(true)
	world.set_process(false)
	world.paused = true
	Engine.max_fps = 30
	var climate := ForestClimate.sample(0, 200)
	climate.cloud_cover = .15
	world.atmosphere.set_season(climate)
	world.painterly_style._process(0)
	var center := Vector3(256, world.land.height_at(256, 256), 256)
	world.camera.position = center + Vector3(0, 400, 260)
	world.camera.look_at(center)
	var frozen: Dictionary = world._world_snapshot().models
	await photo("00-natural")
	world._toggle_soil_layers()
	for index in ForestSoilLayers.LAYERS.size():
		# Exercise the actual selector signal, not a second rendering path.
		world.hud.soil_layers.selector.item_selected.emit(index)
		assert(world.terrain.material.get_shader_param("soil_layer_enabled"))
		var mouse := InputEventMouseMotion.new()
		mouse.position = Vector2(128, 128)
		world.hud.soil_layers._map_input(mouse)
		assert(
			(
				world.hud.soil_layers.field_texture
				== world.terrain.material.get_shader_param("soil_layer_map")
			)
		)
		await photo("%02d-layer-%02d" % [index + 1, index])
	# A local deposit must appear immediately, while the colour ceiling is unchanged.
	world._select_soil_layer(9)
	var ceiling: float = world.hud.soil_layers.limit
	var point := Vector3(255, 0, 255)
	world.soil.deposit_elements(point, 0, 1, 0, false)
	world._refresh_soil_layers()
	assert(world.hud.soil_layers.limit == ceiling)
	await photo("13-local-N-deposit-fixture")
	assert(world.soil.restore(frozen.soil))
	world._refresh_soil_layers()
	for mode in [0, 1]:
		world.painterly_style.set_mode(mode)
		await photo("14-N-style-%d" % mode)
	world.hud.soil_layers.hide_cover.button_pressed = false
	await photo("15-with-canopy")
	world._toggle_soil_layers()
	assert(world.vegetation.visible and world.water_view.visible)
	assert(world.atmosphere.world_env.fog_enabled)
	assert(world._world_snapshot().models == frozen)
	await photo("16-natural-restored")
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"layers": ForestSoilLayers.LAYERS.size(),
		"same_map_and_terrain_texture": true,
		"all_three_styles": true,
		"fixed_scale_after_deposit": true,
		"model_snapshot_unchanged_after_restoration": true,
		"boundary":
		"Paused real world; one labelled local-deposit fixture, not an ecosystem stability test"
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("SOIL_LAYERS_RENDER ", JSON.stringify(report))
	get_tree().quit()
