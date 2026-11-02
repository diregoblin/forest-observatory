extends SceneTree

var w
var output := "res://artifacts/boars-render"


func _initialize() -> void:
	create_timer(25).timeout.connect(func(): quit(1))
	_run.call_deferred()


func photo(label: String) -> void:
	w.painterly_style._process(0)
	for frame in 4:
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)


func _run() -> void:
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	DirAccess.make_dir_recursive_absolute(output)
	w = load("res://scripts/forest.gd").new()
	w.paused = true
	root.add_child(w)
	w._finish_model_work(true)
	w.set_process(false)
	w.habitat_view.paused = true
	w.hud.visible = false
	w.vegetation.visible = false
	w.fungi_view.visible = false
	w.water_view.visible = false
	Engine.max_fps = 30
	var a: ForestAnimals = w.animals
	var ids := []
	for i in a.species.size():
		if a.definitions[a.species[i]].rooting_pressure_day > 0:
			ids.append(i)
	assert(ids.size() == 4)
	var id: int = ids[0]
	var point: Vector3 = a.positions[id]
	point.y = w.land.height_at(point.x, point.z)
	# A labelled paused presentation fixture: movement remains in the model.
	a.yaw[id] = -.5
	var climate := ForestClimate.sample(0, 200)
	climate.cloud_cover = .15
	climate.wind_m_s = 2.0
	w.atmosphere.set_season(climate)
	w.atmosphere.world_env.fog_enabled = false
	w.camera.position = point + Vector3(2.4, 1.3, 2.2)
	w.camera.look_at(point + Vector3.UP * .55)
	var frames := {}
	for action in ["rest", "seek_food", "root"]:
		a.actions[id] = action
		a.elapsed_s = 0
		w.animals_view.refresh(1)
		for i in w.animals_view.batches.size():
			w.animals_view.batches[i].visible = i == id
		var before: Dictionary = a.snapshot()
		var shape: Dictionary = w.animals_view.selection_shape(id)
		assert(not shape.is_empty())
		await photo("01-" + action)
		assert(a.snapshot() == before, "Views do not run boar biology")
		a.elapsed_s = .27 * w.settings.year_speed_multiplier
		w.animals_view.refresh(1)
		assert(w.animals_view.selection_shape(id).faces != shape.faces)
		frames[action] = w.animals_view.animation_clips[id]
		await photo("02-" + action)
	assert(frames.root == "feed" and frames.seek_food == "walk")
	# Same real disturbance field rendered by the soil shader, not a decal prop.
	var p := -1
	for i in w.trees.species.size():
		if w.water.depth[w.trees.root_cells[i]] < .02 and w.trees._height(i) < 1.2:
			p = i
			break
	assert(p >= 0)
	point = w.trees.positions[p]
	w.camera.position = point + Vector3(3.4, 4.8, 4.8)
	w.camera.look_at(point)
	w.terrain.advance_ecology_display(1)
	await photo("03-ground-before")
	assert(w.habitat.root_at(point, 1.2))
	w.groundcover.refresh()
	w.terrain.refresh_ecology(w.soil, w.water, w.groundcover)
	w.terrain.advance_ecology_display(1)
	w.terrain.refresh_traffic(w.habitat)
	await photo("04-poroi-after-fixture")
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"animation_clips": frames,
		"animated_picking_geometry": true,
		"view_does_not_advance_model": true,
		"real_rooting_field": true,
		"boundary":
		"Paused isolated poses and labelled rooting fixture, no live population-stability claim"
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("BOARS_RENDER ", JSON.stringify(report))
	quit()
