extends "res://tools/preview_ground_turf.gd"

var specimen_nodes := []
var studio_caption := Label.new()


func _initialize() -> void:
	output = "res://artifacts/canopy-live"
	super._initialize()


func specimen(species: int, at: Vector3) -> MultiMeshInstance3D:
	var geometry: Dictionary = scene.vegetation.selection_geometry[species]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = geometry.mesh
	mm.instance_count = 1
	var scale: float = 10.0 / geometry.bounds.size.y
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), at))
	mm.set_instance_custom_data(0, Color(1, 1, 0, 1))
	mm.set_instance_color(0, Color.WHITE)
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = scene.vegetation.tree_materials[species].duplicate()
	node.material_override.set_shader_parameter("wind_strength", 0.0)
	root.add_child(node)
	return node


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.hud.visible = false
	Engine.max_fps = 15
	var frozen := model_bytes()
	assert(scene.vegetation.impostor_assets.size() == scene.settings.plants.size())
	# Actual forest and its normal ground materials, not a standalone study shader.
	scene.camera.view(1)
	await photo("01-valley-pixel", true)
	scene.camera.view(2)
	await photo("02-creek-pixel", true)
	var subjects := {}
	for i in scene.settings.plants.size():
		subjects[str(scene.settings.plants[i].species_id)] = i
	for i in scene.trees.species.size():
		var definition: ForestPlantDefinition = scene.settings.plants[scene.trees.species[i]]
		if definition.growth_form != &"shrub" or scene.trees.fallen[i]:
			continue
		var point: Vector3 = scene.trees.positions[i]
		scene.camera.position = point + Vector3(2.2, 1.4, 3.5)
		scene.camera.look_at(point + Vector3.UP * .8)
		await photo("03-understory-pixel", true)
		break
	for mode in [0, 1]:
		scene.painterly_style.set_mode(mode)
		scene.camera.view(2)
		await photo("04-creek-style-%d" % mode, true)
	# Inspect actual near meshes/materials, normalized in height for a clear
	# silhouette comparison. No mutation of authoritative trees or climate.
	for child in [
		scene.terrain,
		scene.vegetation,
		scene.water_view,
		scene.habitat_view,
		scene.animals_view,
		scene.fungi_view,
		scene.dam_view
	]:
		child.visible = false
	scene.turf_cards.visible = false
	scene.turf_cards.set_process(false)
	scene.painterly_style.set_mode(1)
	scene.painterly_style._process(0)
	scene.atmosphere.set_process(false)
	scene.atmosphere.world_env.background_mode = Environment.BG_COLOR
	scene.atmosphere.world_env.background_color = Color("cacbb8")
	scene.atmosphere.world_env.ambient_light_energy = .55
	scene.atmosphere.sun.rotation_degrees = Vector3(-35, 55, 0)
	scene.atmosphere.sun.light_energy = 1.25
	scene.atmosphere.sun.light_color = Color("fff2d5")
	studio_caption.position = Vector2(30, 25)
	studio_caption.add_theme_font_size_override("font_size", 24)
	studio_caption.add_theme_color_override("font_color", Color("34463f"))
	root.add_child(studio_caption)
	var base := Vector3(256, 200, 256)
	scene.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	scene.camera.size = 18
	for names in [
		["birch", "oak", "hazel"],
		["grey_willow", "raspberry", "lingonberry"],
		["spruce", "pine", "juniper"]
	]:
		for node in specimen_nodes:
			node.free()
		specimen_nodes.clear()
		for i in 3:
			specimen_nodes.append(specimen(subjects[names[i]], base + Vector3((i - 1) * 10, 0, 0)))
		scene.camera.position = base + Vector3(0, 8, 35)
		scene.camera.look_at(base + Vector3(0, 5, 0))
		studio_caption.text = "%s · реальные меши/материалы, высота уравнена" % " / ".join(names)
		await photo("05-specimens-%s-summer" % names[0], true)
		for node in specimen_nodes:
			node.multimesh.set_instance_custom_data(0, Color(0, 1, 0, 1))
		if scene.settings.plants[subjects[names[0]]].deciduous:
			studio_caption.text = "%s · без листьев: проверка каркаса" % " / ".join(names)
			await photo("06-specimens-%s-winter" % names[0], true)
		for node in specimen_nodes:
			node.multimesh.set_instance_custom_data(0, Color(.8, 1, 1, 1))
			var mat: ShaderMaterial = node.material_override
			mat.set_shader_parameter("snow_load", .8)
		studio_caption.text = "%s · сезон / снег" % " / ".join(names)
		await photo("07-specimens-%s-season" % names[0], true)
	for node in specimen_nodes:
		node.free()
	assert(model_bytes() == frozen)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"unchanged_models": true,
		"impostor_species": scene.vegetation.impostor_assets.size(),
		"phases": phases,
		"boundary":
		(
			"Short paused actual-world preview plus normalized specimen inspection, not sustained FPS. "
			+ "No user saves changed."
		)
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("CANOPY_LIVE_RENDER ", JSON.stringify(report))
	scene.free()
	quit()
