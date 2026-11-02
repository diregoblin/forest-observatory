extends "res://tools/preview_ground_turf.gd"


func _initialize() -> void:
	output = "res://artifacts/plant-lighting-render"
	super._initialize()


func specimen(mesh: Mesh, mat: ShaderMaterial, point: Vector3) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.8), point))
	mm.set_instance_custom_data(0, Color(1, 1, 0, 1))
	mm.set_instance_color(0, Color.WHITE)
	node.multimesh = mm
	node.material_override = mat
	root.add_child(node)
	return node


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.turf_cards.set_process(false)
	scene.turf_cards.visible = false
	scene.hud.visible = false
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
	Engine.max_fps = 30
	var frozen := model_bytes()
	var species := -1
	var budget := {}
	for s in scene.vegetation.mid_geometry:
		var definition: ForestPlantDefinition = scene.settings.plants[s]
		budget[str(definition.species_id)] = {
			"full_triangles": scene.vegetation.selection_geometry[s].faces.size() / 3,
			"mid_triangles": scene.vegetation.mid_geometry[s].faces.size() / 3
		}
		if definition.species_id == &"male_fern":
			species = s
	assert(species >= 0)
	var geometry: Dictionary = scene.vegetation.selection_geometry[species]
	var middle: Dictionary = scene.vegetation.mid_geometry[species]
	var asset: Dictionary = scene.vegetation.impostor_assets[species]
	var near_mat: ShaderMaterial = scene.vegetation.tree_materials[species].duplicate()
	var far_mat: ShaderMaterial = asset.material.duplicate()
	near_mat.set_shader_parameter("wind_strength", 0.0)
	var base := Vector3(250, 200, 250)
	var objects := [
		specimen(geometry.mesh, near_mat, base + Vector3(-1.65, 0, 0)),
		specimen(middle.mesh, near_mat, base),
		specimen(asset.mesh, far_mat, base + Vector3(1.65, 0, 0))
	]
	scene.camera.position = base + Vector3(0, 1.8, 7.0)
	scene.camera.look_at(base + Vector3(0, .65, 0))
	scene.camera.fov = 45
	scene.atmosphere.set_process(false)
	scene.atmosphere.world_env.background_mode = Environment.BG_COLOR
	scene.atmosphere.world_env.background_color = Color(.11, .14, .12)
	scene.atmosphere.world_env.ambient_light_energy = .25
	scene.atmosphere.sun.shadow_enabled = false
	scene.atmosphere.sun.light_energy = 1.5
	scene.atmosphere.sun.light_color = Color(1, .94, .83)
	var changes := []
	for mode in 3:
		scene.painterly_style.set_mode(mode)
		near_mat.shader = [
			load("res://shaders/foliage.gdshader"),
			load("res://shaders/painterly_foliage.gdshader"),
			load("res://shaders/pixel_foliage.gdshader")
		][mode]
		far_mat.set_shader_parameter("presentation_style", mode)
		far_mat.set_shader_parameter("normal_atlas_enabled", true)
		scene.atmosphere.sun.rotation_degrees = Vector3(-30, -60, 0)
		await photo("01-left-light-style-%d" % mode, true)
		scene.atmosphere.sun.rotation_degrees = Vector3(-30, 60, 0)
		var correct := await photo("02-right-light-style-%d" % mode, true)
		far_mat.set_shader_parameter("normal_atlas_enabled", false)
		var flat := await photo("03-flat-normal-control-style-%d" % mode, true)
		var change := difference(correct, flat)
		assert(change > .0001, "The normal atlas must change real lighting, not just metadata")
		changes.append(change)
	for object in objects:
		object.free()
	# Inspect the actual valley's adjacent primary surfaces, not studio swatches.
	for child in [
		scene.terrain,
		scene.vegetation,
		scene.water_view,
		scene.habitat_view,
		scene.animals_view,
		scene.fungi_view,
		scene.dam_view
	]:
		child.visible = true
	scene.atmosphere.world_env.background_mode = Environment.BG_SKY
	scene.atmosphere.set_season(scene._display_climate())
	scene.painterly_style.set_mode(2)
	scene.camera.fov = 64
	scene.turf_cards.set_process(true)
	scene.camera.view(2)
	await photo("04-materials-creek", true)
	var rock: Transform3D
	for slot in scene.vegetation.rock_batch.multimesh.instance_count:
		rock = scene.vegetation.rock_batch.multimesh.get_instance_transform(slot)
		var p := rock.origin
		if scene.water.depth[scene.water.index_at(p.x, p.z)] < .001:
			break
	var top := rock.origin + Vector3.UP * rock.basis.y.length() * .6
	scene.camera.position = top + Vector3(1.7, 1.0, 2.4)
	scene.camera.look_at(top)
	await photo("05-materials-stone", true)
	for id in scene.trees.species.size():
		if (
			scene.settings.plants[scene.trees.species[id]].growth_form != &"tree"
			or scene.trees.fallen[id]
		):
			continue
		var point: Vector3 = scene.trees.positions[id]
		scene.camera.position = point + Vector3(2, 1.8, 3)
		scene.camera.look_at(point + Vector3.UP * 1.5)
		await photo("06-materials-bark", true)
		break
	var generation_usec := []
	var steady_usec := []
	scene.turf_cards.set_process(false)
	scene.turf_cards.cached_parameters.clear()
	for node in scene.turf_cards.patches.values():
		node.free()
	scene.turf_cards.patches.clear()
	for frame in 10:
		var start := Time.get_ticks_usec()
		scene.turf_cards._process(0)
		generation_usec.append(Time.get_ticks_usec() - start)
	for frame in 30:
		var start := Time.get_ticks_usec()
		scene.turf_cards._process(0)
		steady_usec.append(Time.get_ticks_usec() - start)
	assert(model_bytes() == frozen)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"left_to_right": ["full mesh", "mid 3D", "far cutout"],
		"normal_control_difference": changes,
		"triangle_budgets": budget,
		"cards_generation_usec": generation_usec,
		"cards_steady_usec": steady_usec,
		"unchanged_models": true,
		"boundary": "Isolated side-by-side light fixture, not in-game FPS."
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("PLANT_LIGHTING_RENDER ", JSON.stringify(report))
	scene.free()
	quit()
