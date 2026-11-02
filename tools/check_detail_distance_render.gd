extends "res://tools/check_weather_habitat.gd"

var output := "res://artifacts/detail-distance-render"


func _run() -> void:
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	Engine.max_fps = 30
	DirAccess.make_dir_recursive_absolute(output)
	var w := fixture(true)
	var climate := ForestClimate.sample(0, 160)
	climate.wind_m_s = 2.0
	climate.rain_fraction = 0.0
	w.habitat.step(ForestClimate.DAY_S, climate)
	var camera := Camera3D.new()
	camera.fov = 20
	root.add_child(camera)
	var view := ForestHabitatView.new()
	root.add_child(view)
	view.paused = true
	view.configure(w.habitat, camera)
	view.refresh(climate)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.035, .055, .08)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1
	root.add_child(env)
	# One actual finite-pool representative isolated for a readable render check.
	var record: Array = view._candidates[view.bugs][0]
	view._candidates = {
		view.bugs: [record], view.footprints: [], view.homes: [], view.rootplates: []
	}
	view._display_dirty = true
	var point: Vector3 = record[0].origin
	var phase: float = record[2].r
	var radius: float = record[2].g
	var aim := (
		point + Vector3(sin(phase) * radius, sin(phase) * radius * .22, cos(phase) * radius * .8)
	)
	view.set_weather_time(0)
	var frozen: Dictionary = w.habitat.snapshot()
	var counts := []
	for distance in [2.0, 16.5, 22.0]:
		camera.position = aim + Vector3(0, 0, distance)
		camera.look_at(aim)
		view.advance_display()
		counts.append(view.bugs.multimesh.visible_instance_count)
		for frame in 4:
			await RenderingServer.frame_post_draw
		assert(
			(
				root.get_texture().get_image().save_png(
					output.path_join("insect-%s-m.png" % distance)
				)
				== OK
			)
		)
	assert(counts == [1, 1, 0])
	assert(w.habitat.snapshot() == frozen)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"distances_m": [2, 16.5, 22],
		"submitted_insects": counts,
		"model_unchanged": true,
		"boundary": "Single actual representative, paused rendering; no whole-game FPS claim"
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("DETAIL_DISTANCE_RENDER ", JSON.stringify(report))
	view.free()
	camera.free()
	env.free()
	quit()
