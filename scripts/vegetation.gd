class_name ForestVegetation
extends Node3D

var land: ForestLandscape
var water: ForestWatershed
var groundcover: ForestGroundcover
var rng := RandomNumberGenerator.new()
var grass: MultiMeshInstance3D
var tree_count := 0
var growth_texture: ImageTexture


func build(l: ForestLandscape, w: ForestWatershed, plants: ForestGroundcover) -> void:
	land = l
	water = w
	groundcover = plants
	rng.seed = land.settings.seed
	var settings := land.settings
	var groups := {}
	var total_weight := 0.0
	for definition in settings.plants:
		groups[definition.species_id] = []
		total_weight += definition.weight
	for attempt in settings.tree_attempts:
		var choice := rng.randf() * total_weight
		var definition: ForestPlantDefinition = settings.plants.back()
		for candidate in settings.plants:
			choice -= candidate.weight
			if choice <= 0:
				definition = candidate
				break
		var x := rng.randf_range(12, settings.extent - 12)
		var z := rng.randf_range(12, settings.extent - 12)
		var distance := absf(x - land.channel_x(z))
		var clearing := (
			Vector2(x / settings.extent - .375, z / settings.extent - .557).length() < .06
		)
		if distance < definition.minimum_channel_distance or clearing:
			continue
		if distance < 36 and rng.randf() < .65:
			continue
		if land.noise.get_noise_2d(x * .7 + 300, z * .7) < -.24 and rng.randf() < .8:
			continue
		var scale_v := (
			Vector3.ONE * rng.randf_range(definition.scale_range.x, definition.scale_range.y)
		)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(scale_v)
		groups[definition.species_id].append(
			Transform3D(basis, Vector3(x, land.height_at(x, z) - .1, z))
		)
	for definition in settings.plants:
		var spots: Array[Transform3D] = []
		spots.assign(groups[definition.species_id])
		_instance_group(
			ForestPlantMeshBuilder.build(definition), spots, Color.WHITE, definition.wind_strength
		)
		tree_count += spots.size()
	var rocks: Array[Transform3D] = []
	for i in 550:
		var z := rng.randf_range(10, settings.extent - 10)
		var x := (
			land.channel_x(z) + rng.randf_range(-19, 19)
			if i < 400
			else rng.randf_range(15, settings.extent - 15)
		)
		var size := rng.randf_range(.3, 1.5)
		var basis := Basis.from_euler(Vector3(rng.randf(), rng.randf() * TAU, rng.randf())).scaled(
			Vector3(size * 1.5, size * .75, size)
		)
		rocks.append(Transform3D(basis, Vector3(x, land.height_at(x, z) - size * .15, z)))
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 3
	rock.radius = 1
	rock.height = 2
	_instance_group(rock, rocks, Color(.42, .43, .36), 0)
	_build_grass()


func _instance_group(
	mesh: Mesh, spots: Array[Transform3D], tint: Color, wind: float
) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
		var shade := rng.randf_range(.75, 1.22)
		mm.set_instance_color(i, Color(shade, shade, shade, 1))
	node.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("base_color", tint)
	mat.set_shader_parameter("wind_strength", wind)
	node.material_override = mat
	node.extra_cull_margin = 3
	add_child(node)
	return node


func _build_grass() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 4:
		var a := j * PI / 4
		var side := Vector3(cos(a), 0, sin(a)) * .22
		for vertex in [-side, side, Vector3(.1, .9, 0)]:
			st.set_normal(Vector3.UP)
			st.set_color(Color(1, 1, 1))
			st.add_vertex(vertex)
	var spots: Array[Transform3D] = []
	for i in land.settings.grass_attempts:
		var x := rng.randf_range(8, land.settings.extent - 8)
		var z := rng.randf_range(8, land.settings.extent - 8)
		if absf(x - land.channel_x(z)) < 9:
			continue
		var pos := Vector3(x, land.height_at(x, z), z)
		var s := rng.randf_range(.5, 1.5)
		spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), pos))
	grass = _instance_group(st.commit(), spots, Color(.45, .49, .21), .12)
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func refresh_plants() -> void:
	var image := ForestFieldTexture.image(groundcover.biomass, water.resolution)
	if growth_texture == null:
		growth_texture = ImageTexture.create_from_image(image)
		grass.material_override.set_shader_parameter("growth_map", growth_texture)
		grass.material_override.set_shader_parameter("growth_enabled", true)
		grass.material_override.set_shader_parameter("world_extent", land.settings.extent)
	else:
		growth_texture.update(image)
