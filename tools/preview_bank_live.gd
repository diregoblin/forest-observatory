extends SceneTree


func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene._finish_model_work(true)
	scene.capture_step = 8
	scene.camera.set_process(false)
	scene.hud.visible = false
	scene.painterly_style.set_mode(2)
	scene.hud.bank_relief_button.button_pressed = true
	scene._set_speed(8.0)
	var start_ticks: int = scene.ecology_clock.ticks
	var busy := 0
	var checked_while_busy := false
	Engine.max_fps = 30
	scene.paused = false
	for frame in 90:
		await RenderingServer.frame_post_draw
		if scene.model_work_active:
			busy += 1
			if not checked_while_busy:
				scene.hud.bank_relief_button.button_pressed = false
				scene.hud.bank_relief_button.button_pressed = true
				assert(scene.model_work_active, "Presentation toggle does not join/read the worker")
				checked_while_busy = true
		assert(scene.terrain.material.get_shader_param("bank_water_current") == scene.water_view.depth_texture)
		var water_alpha: float = scene.water_view.material_override.get_shader_parameter("display_alpha")
		assert(is_equal_approx(scene.terrain.material.get_shader_param("bank_water_blend"), water_alpha))
	scene.paused = true
	scene._finish_model_work(true)
	assert(checked_while_busy and scene.ecology_clock.ticks > start_ticks)
	var report := {"passed": true, "busy_frames": busy,
		"completed_ticks": scene.ecology_clock.ticks - start_ticks,
		"quality_toggle_during_worker": checked_while_busy, "water_display_alpha_matches": true,
		"boundary": "Short actual Forward+ worker/render check; no user saves, not a speed benchmark."}
	FileAccess.open("res://artifacts/bank-live.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("BANK_LIVE ", JSON.stringify(report))
	scene.free()
	quit()
