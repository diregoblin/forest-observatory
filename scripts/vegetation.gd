class_name ForestVegetation
extends Node3D

var land: ForestLandscape
var water: ForestWatershed
var groundcover: ForestGroundcover
var rng := RandomNumberGenerator.new()
var tree_count := 0
var trees: ForestTrees
var tree_groups := {}
var tree_members := {}
var displayed_tick := -1
var displayed_day := -1.0
var membership_count := -1
var selection_geometry: Dictionary = {}
var displayed_shapes: Dictionary = {}


func build(
	l: ForestLandscape, w: ForestWatershed, plants: ForestGroundcover, model: ForestTrees
) -> void:
	land = l
	water = w
	groundcover = plants
	trees = model
	var settings := land.settings
	rng.seed = land.settings.seed + 71
	_rebuild_membership()
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


func _rebuild_membership() -> void:
	for node in tree_groups.values():
		node.queue_free()
	displayed_shapes.clear()
	tree_groups.clear()
	tree_members.clear()
	tree_count = 0
	for s in land.settings.plants.size():
		var definition: ForestPlantDefinition = land.settings.plants[s]
		var spots: Array[Transform3D] = []
		var members: Array[int] = []
		for i in trees.species.size():
			if trees.species[i] != s:
				continue
			members.append(i)
			spots.append(
				Transform3D(
					Basis(Vector3.UP, trees.yaw[i]).scaled(Vector3.ONE * trees.size[i]),
					trees.positions[i]
				)
			)
		var node := _instance_group(
			ForestPlantMeshBuilder.build(definition),
			spots,
			Color.WHITE,
			definition.wind_strength,
			true
		)
		node.material_override.set_shader_parameter("autumn_color", definition.autumn_color)
		tree_groups[s] = node
		tree_members[s] = members
		tree_count += members.size()
		var mesh: Mesh = node.multimesh.mesh
		var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var foliage := PackedByteArray()
		for j in range(0, colors.size(), 3):
			foliage.append(1 if colors[j].a < .5 else 0)
		selection_geometry[s] = {
			"faces": mesh.get_faces(), "foliage": foliage, "bounds": mesh.get_aabb()
		}
	membership_count = trees.species.size()
	displayed_tick = -1


func _instance_group(
	mesh: Mesh, spots: Array[Transform3D], tint: Color, wind: float, tree_enabled := false
) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = tree_enabled
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
	mat.set_shader_parameter("tree_enabled", tree_enabled)
	node.material_override = mat
	node.extra_cull_margin = 3
	add_child(node)
	return node


func refresh_trees(climate: Dictionary) -> void:
	if membership_count != trees.species.size():
		_rebuild_membership()
	if displayed_tick == trees.ticks and is_equal_approx(displayed_day, climate.day):
		return
	displayed_tick = trees.ticks
	displayed_day = climate.day
	for s in tree_groups:
		var definition: ForestPlantDefinition = land.settings.plants[s]
		var node: MultiMeshInstance3D = tree_groups[s]
		var members: Array = tree_members[s]
		for j in members.size():
			var i: int = members[j]
			var leaf := ForestClimate.leaves(definition, climate.day)
			leaf *= (1.0 - trees.stress[i] * .7) if trees.alive[i] else 0.0
			node.multimesh.set_instance_custom_data(
				j,
				Color(
					leaf,
					1.0 - trees.stress[i],
					ForestClimate.autumn(definition, climate.day),
					trees.alive[i]
				)
			)
			var transform := Transform3D(
				Basis(Vector3.UP, trees.yaw[i]).scaled(Vector3.ONE * trees.size[i]),
				trees.positions[i]
			)
			node.multimesh.set_instance_transform(j, transform)
			var geometry: Dictionary = selection_geometry[s]
			displayed_shapes[i] = {
				"transform": transform,
				"faces": geometry.faces,
				"foliage": geometry.foliage,
				"leaves": leaf,
				"bounds": transform * geometry.bounds
			}


func selection_shape(id: int) -> Dictionary:
	# Pick exactly the last submitted MultiMesh state, never future model growth.
	return displayed_shapes.get(id, {})
