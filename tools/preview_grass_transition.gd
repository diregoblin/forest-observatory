extends "res://tools/preview_ground_turf.gd"

const ANIMAL_DEFINITION = preload("res://scripts/animal_definition.gd")
const BEFORE := (
	"/run/media/pavel/Storage/tmp/forest-grass-transition-20261102/shaders/turf_cards.gdshader"
)


func _initialize() -> void:
	output = "res://artifacts/grass-transition"
	super._initialize()


func capture(label: String) -> Image:
	scene.painterly_style._process(0)
	for frame in 6:
		await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	assert(result.save_png(output.path_join(label + ".png")) == OK)
	return result


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.atmosphere.set_process(false)
	scene.hud.visible = false
	Engine.max_fps = 15
	var frozen := model_bytes()
	scene.terrain.advance_ecology_display(1)
	var cards: ForestTurfCards = scene.turf_cards
	cards.set_process(false)
	var current: Shader = cards.material.shader
	var previous := Shader.new()
	previous.code = FileAccess.get_file_as_string(BEFORE)
	assert(not previous.code.is_empty())
	var point := Vector3(200, scene.terrain.data.get_height(Vector3(200, 0, 196)), 196)
	scene.camera.position = point + Vector3(0, 1.65, 0)
	var target := point + Vector3(0, 0, -40)
	target.y = scene.terrain.data.get_height(target) + .5
	scene.camera.look_at(target)
	for frame in 45:
		cards._process(0)
	assert(cards.patches.size() <= 121)
	var patch: MultiMesh = cards.patches.values()[0].multimesh
	var anchored := patch.buffer.duplicate()
	var report := {"passed": false, "pairs": [], "view_distance_m": cards.VIEW_M}
	for lighting in ["day", "night", "cold"]:
		var climate := ForestClimate.sample(0, 155, 60, 12 if lighting != "night" else 1.35)
		climate.cloud_cover = .65 if lighting == "night" else .18
		climate.temperature_c = 4.0 if lighting == "cold" else 14.0
		climate.weather_time_s = 0.0
		scene.atmosphere.set_season(climate)
		scene.atmosphere.rain_particles.emitting = false
		scene.terrain.set_surface_season(climate)
		cards._process(0)
		for mode in ([2, 0, 1] if lighting == "day" else [2]):
			scene.painterly_style.set_mode(mode)
			cards._process(0)
			var shown_meshes := {}
			for key in cards.patches:
				shown_meshes[key] = cards.patches[key].multimesh.mesh
				cards.patches[key].multimesh.mesh = cards.card_mesh
			cards.material.shader = previous
			var old := await capture("%s-%d-before" % [lighting, mode])
			cards.material.shader = current
			for key in shown_meshes:
				cards.patches[key].multimesh.mesh = shown_meshes[key]
			var improved := await capture("%s-%d-after" % [lighting, mode])
			var delta := difference(old, improved)
			assert(delta > .0001, "Paired grass change must be visible")
			report.pairs.append({"light": lighting, "style": mode, "difference": delta})
		# An offset eye-level view catches camera-following rings/pops too.
		if lighting == "day":
			scene.camera.position.x += 4.0
			for frame in 15:
				cards._process(0)
			scene.painterly_style.set_mode(2)
			cards._process(0)
			await capture("day-offset-after")
			scene.camera.position.x -= 4.0
			for frame in 15:
				cards._process(0)
		assert(patch.buffer == anchored, "Camera/lighting must not move or randomize anchored grass")
	# Snow and scientific soil layers still suppress the decorative cards.
	scene.terrain.material.set_shader_param("snow_water_m", .03)
	cards._process(0)
	await capture("snow-after")
	scene.terrain.material.set_shader_param("snow_water_m", 0.0)
	scene.terrain.material.set_shader_param("soil_layer_enabled", true)
	cards._process(0)
	assert(not cards.visible)
	assert(model_bytes() == frozen)
	report.passed = true
	report.unchanged_models = true
	report.anchored_cards = true
	report.loaded_patches = cards.patches.size()
	report.boundary = "Short paused actual Forward+ presentation, not sustained FPS. No user saves."
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("GRASS_TRANSITION ", JSON.stringify(report))
	scene.free()
	quit()
