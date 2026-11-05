extends SceneTree

var scene


func _initialize() -> void:
	create_timer(45).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 600)
	Engine.max_fps = 20
	scene = load("res://scripts/forest.gd").new()
	root.add_child(scene)
	scene.capture_dir = ""
	scene.camera.set_process(false)
	scene.hud.visible = false
	scene._toggle_rain()
	var begin_ticks: int = scene.ecology_clock.ticks
	var initial_input: float = scene.water.native.metrics().input_m3
	var initial_liquid: float = scene.weather.liquid_m
	var initial_time: float = scene.water.clock
	var busy := 0
	var completions := 0
	var previous_tick: int = scene.presentation_tick
	var deck = scene.atmosphere.cloud_deck
	assert(deck.clouds != scene.weather.clouds, "View owns its trajectory cache")
	for frame in 50:
		await RenderingServer.frame_post_draw
		busy += int(scene.model_work_active)
		if scene.presentation_tick > previous_tick:
			completions += 1
			previous_tick = scene.presentation_tick
		var submitted: Dictionary = scene.atmosphere.displayed_weather
		assert(deck.last_time == submitted.weather_time_s)
		assert(deck.cloud_offset == deck.clouds.offset_at(submitted.weather_time_s))
	scene._toggle_pause()
	scene.set_process(false)
	scene._process(.02)
	await RenderingServer.frame_post_draw
	var frozen: Dictionary = scene._world_snapshot().models
	var cloud_time: float = deck.last_time
	var mask: PackedByteArray = deck.rain_mask.get_image().get_data()
	for frame in 4:
		scene._process(.02)
		await RenderingServer.frame_post_draw
	assert(scene._world_snapshot().models == frozen)
	assert(deck.last_time == cloud_time and deck.rain_mask.get_image().get_data() == mask)
	assert(busy > 0 and completions > 0 and scene.ecology_clock.ticks > begin_ticks)
	var dt: float = scene.water.clock - initial_time
	var rain: float = (
		(scene.weather.liquid_m - initial_liquid) * scene.settings.extent * scene.settings.extent
	)
	var source: float = (scene.settings.headwater_m3_s + scene.settings.spring_flow_m3_s) * dt
	var residual: float = scene.water.native.metrics().input_m3 - initial_input - rain - source
	assert(absf(residual) < 1e-8, "Actual live worker uses summed spatial liquid forcing")
	var report := {
		"passed": true,
		"busy_frames": busy,
		"completion_frames": completions,
		"completed_ticks": scene.ecology_clock.ticks - begin_ticks,
		"pause_freezes_models_and_mask": true,
		"liquid_volume_m3": rain,
		"input_residual_m3": residual,
		"display_phase_matches_clouds": true
	}
	FileAccess.open("res://artifacts/spatial-rain/live.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "\t")
	)
	print("SPATIAL_RAIN_LIVE ", JSON.stringify(report))
	scene.free()
	quit()
