extends "res://tools/preview_ground_turf.gd"


func _initialize() -> void:
	output = "res://artifacts/animal-profiles"
	create_timer(50).timeout.connect(func(): quit(1))
	_run.call_deferred()


func capture(label: String) -> void:
	scene.painterly_style._process(0)
	for frame in 6:
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene._finish_model_work(true)
	scene.capture_step = 8
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.turf_cards.set_process(false)
	scene.camera.view(1)
	Engine.max_fps = 20
	scene.painterly_style.set_mode(2)
	var panel = scene.hud.observation_panel
	panel.show_record(scene.animals.inspect(0))
	await capture("01-live-female")
	# Actual isolated model deaths, not hand-written terminal record strings.
	# No user world/save is loaded, and every display read must remain read-only.
	for id in 2:
		scene.animals._die(id)
		var frozen := model_bytes()
		panel.show_record(scene.animals.inspect(id))
		assert(panel.state_label.text.to_lower().count("погиб") == 1)
		assert(not panel.follow_toggle.visible)
		await capture("02-dead-%d" % id)
		panel.details_toggle.button_pressed = true
		assert(panel.details.visible)
		assert("Действие:" not in panel.details.text and "Выводок:" not in panel.details.text)
		await capture("03-dead-%d-details" % id)
		panel.details_toggle.button_pressed = false
		assert(model_bytes() == frozen)
	panel.show_record(scene.trees.inspect(0))
	assert(not panel.distinctions.visible and not panel.follow_toggle.visible)
	await capture("04-plant-no-stale-animal-state")
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify({
		"passed": true, "male_female_single_death_status": true,
		"no_live_state_after_death": true, "profile_reads_do_not_mutate_models": true,
		"plant_switch_clears_animal_controls": true,
		"boundary": "Isolated actual Forward+ profile fixture; two deliberate fixture deaths, no user saves."
	}, "  "))
	print("ANIMAL_PROFILES_RENDER passed")
	scene.free()
	quit()
