extends SceneTree

const PIXEL_SHADER = preload("res://shaders/pixel_foliage.gdshader")

var output := "res://artifacts/herb-shadows-after"
var atmosphere: ForestAtmosphere
var camera := Camera3D.new()
var plants: Array[MultiMeshInstance3D] = []
var records := []


func _initialize() -> void:
	create_timer(55).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _specimen(name: String, point: Vector3, low := false) -> void:
	var definition: ForestPlantDefinition = load("res://data/plants/%s.tres" % name)
	assert(definition != null)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = ForestPlantMeshBuilder.build(definition, low)
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, point))
	mm.set_instance_color(0, Color.WHITE)
	mm.set_instance_custom_data(0, Color(1, 1, 0, 1))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = PIXEL_SHADER
	mat.set_shader_parameter("base_color", Color.WHITE)
	mat.set_shader_parameter("tree_enabled", true)
	mat.set_shader_parameter("bloom_fraction", 1.0)
	mat.set_shader_parameter("wind_strength", 0.0)
	ForestPlantMeshBuilder.set_canopy_material(definition, mat)
	node.material_override = mat
	root.add_child(node)
	plants.append(node)


func _photo(label: String) -> Image:
	for frame in 4:
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.save_png(output.path_join(label + ".png")) == OK)
	records.append(
		{
			"label": label,
			"shadow_bias": atmosphere.sun.shadow_bias,
			"normal_bias": atmosphere.sun.shadow_normal_bias,
			"reverse_cull": atmosphere.sun.shadow_reverse_cull_face,
			"ssao": atmosphere.world_env.ssao_enabled
		}
	)
	return image


func _setup() -> void:
	Engine.max_fps = 20
	root.size = Vector2i(1100, 720)
	DirAccess.make_dir_recursive_absolute(output)
	atmosphere = ForestAtmosphere.new()
	root.add_child(atmosphere)
	atmosphere.configure()
	atmosphere.world_env.background_mode = Environment.BG_COLOR
	atmosphere.world_env.background_color = Color("9ba9a4")
	atmosphere.world_env.fog_enabled = false
	atmosphere.world_env.glow_enabled = false
	atmosphere.world_env.ambient_light_energy = .45
	atmosphere.world_env.ssao_intensity = .8
	atmosphere.sun.rotation_degrees = Vector3(-28, -38, 0)
	atmosphere.sun.light_color = Color("fff3d9")
	atmosphere.sun.light_energy = 1.3
	root.add_child(camera)
	camera.position = Vector3(0, 1.15, 2.3)
	camera.look_at(Vector3(0, .5, 0))
	camera.fov = 48
	camera.current = true
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_node.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("61784d")
	floor_mat.roughness = 1.0
	floor_node.material_override = floor_mat
	root.add_child(floor_node)


func _run() -> void:
	_setup()
	_specimen("meadowsweet", Vector3(-.6, 0, 0))
	_specimen("balsam", Vector3(.5, 0, 0))
	await _photo("01-original")
	atmosphere.sun.shadow_enabled = false
	await _photo("02-no-shadow-map")
	atmosphere.sun.shadow_enabled = true
	atmosphere.world_env.ssao_enabled = false
	await _photo("03-no-ssao")
	atmosphere.world_env.ssao_enabled = true
	atmosphere.sun.shadow_normal_bias = 4
	await _photo("04-normal-bias-4")
	atmosphere.sun.shadow_normal_bias = 2
	atmosphere.sun.shadow_reverse_cull_face = true
	await _photo("05-reverse-cull")
	atmosphere.sun.shadow_reverse_cull_face = false
	for plant in plants:
		plant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	await _photo("06-double-sided-caster")
	for plant in plants:
		plant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var material: ShaderMaterial = plant.material_override
		var shader := Shader.new()
		shader.code = material.shader.code.replace(
			"render_mode cull_disabled;", "render_mode cull_back;"
		)
		material.shader = shader
	await _photo("07-backface-cull")
	for plant in plants:
		plant.material_override.shader = PIXEL_SHADER
	atmosphere.sun.shadow_normal_bias = 0
	await _photo("08-no-normal-bias")
	atmosphere.sun.shadow_bias = .3
	await _photo("09-depth-bias-03")
	atmosphere.sun.shadow_bias = .7
	await _photo("10-depth-bias-07")
	FileAccess.open(output.path_join("diagnostic.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{"renderer": RenderingServer.get_current_rendering_method(), "records": records}, "  "
		)
	)
	print("HERB_SHADOW_DIAGNOSTIC ", JSON.stringify(records))
	atmosphere.rain_particles.free()
	for child in root.get_children():
		child.free()
	await process_frame
	quit()
