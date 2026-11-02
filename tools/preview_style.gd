extends SceneTree

## Isolated grove using project meshes/materials, not an ecosystem simulation.
## Same camera and geometry for A/B. Never opens or writes a user save.
func _initialize() -> void:
	_run.call_deferred()


func _capture(filename: String) -> void:
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + filename)


func _run() -> void:
	root.size = Vector2i(1100, 690)
	var stage := Node3D.new()
	root.add_child(stage)
	var atmosphere := ForestAtmosphere.new()
	stage.add_child(atmosphere)
	atmosphere.configure()
	atmosphere.set_season(ForestClimate.sample(0, 200, 60))
	var vegetation := ForestVegetation.new()
	stage.add_child(vegetation)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4081
	for identity in ["birch", "spruce", "rowan", "guelder_rose", "male_fern"]:
		var definition: ForestPlantDefinition = load("res://data/plants/%s.tres" % identity)
		var spots: Array[Transform3D] = []
		for i in 26:
			var x := rng.randf_range(-42, 42)
			var z := rng.randf_range(-55, 16)
			if absf(x) < 7 and z > -20:
				x += 12
			var scale := rng.randf_range(.75, 1.25)
			spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale), Vector3(x, 0, z)))
		var batch := vegetation._instance_group(ForestPlantMeshBuilder.build(definition), spots, Color.WHITE, 0.0, true)
		for i in spots.size():
			batch.multimesh.set_instance_custom_data(i, Color(1, 1, 0, 1))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	ground.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(.28, .40, .13)
	floor_material.roughness = 1
	ground.material_override = floor_material
	stage.add_child(ground)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.position = Vector3(12, 9, 37)
	camera.look_at(Vector3(0, 8, -12))
	await _capture("style-baseline.png")
	var style = load("res://scripts/painterly_style.gd").new()
	stage.add_child(style)
	style.configure(atmosphere, vegetation)
	await _capture("style-painterly.png")
	style.set_enabled(false)
	await _capture("style-restored.png")
	assert(atmosphere.world_env.sky.sky_material == style.original_sky)
	for material in style.original_shaders:
		assert(material.shader == style.original_shaders[material])
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"simulation_instantiated": false,
		"original_sky_and_materials_restored": true,
		"boundary": "Isolated static project-mesh grove; not full-valley rendering, GPU performance or volumetric-cloud validation."
	}
	FileAccess.open("res://artifacts/style-check.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("STYLE_CHECK ", JSON.stringify(report))
	quit()
