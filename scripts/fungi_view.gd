class_name ForestFungiView
extends Node3D

## A cell may display one body or a clump. These are representative objects;
## the conserved fruit-carbon pool, not the rounded instance count, is the state.
var model: ForestFungi
var bodies := MultiMeshInstance3D.new()
var body_count := 0
var group_count := 0
var last_tick := -1


func configure(fungi: ForestFungi) -> void:
	model = fungi
	var definition := model.land.settings.fungus
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := CylinderMesh.new()
	stem.top_radius = .013
	stem.bottom_radius = .019
	stem.height = definition.stem_height_m
	stem.radial_segments = 7
	ForestPlantMeshBuilder._append(
		surface,
		stem,
		Transform3D(Basis.IDENTITY, Vector3.UP * stem.height / 2),
		definition.stem_color
	)
	var cap := SphereMesh.new()
	cap.radius = definition.cap_radius_m
	cap.height = definition.cap_radius_m * .65
	cap.radial_segments = 12
	cap.rings = 5
	ForestPlantMeshBuilder._append(
		surface,
		cap,
		Transform3D(Basis.IDENTITY, Vector3.UP * definition.stem_height_m),
		definition.cap_color
	)
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = .87
	mesh.surface_set_material(0, material)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	bodies.multimesh = multi
	add_child(bodies)
	refresh()


func refresh() -> void:
	if last_tick == model.revision:
		return
	last_tick = model.revision
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var config := model.land.settings
	var n := config.fungi_resolution
	var dx := config.fungi_cell_m
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed + 8173
	group_count = 0
	for plot in model.plots:
		var fruit: PackedFloat64Array = plot.fields.fruit
		for k in fruit.size():
			# A per-cell seed keeps objects stable when another cell starts/stops fruiting.
			rng.seed = config.seed + 8173 + k * 7919 + int(plot.origin.x * 131)
			var expected := fruit[k] * dx * dx / config.fungus.representative_body_kg
			# Stable mixture of solitary bodies and clumps, with the same expected biomass.
			var clump := 3 if rng.randf() < .35 else 1
			var expected_objects := expected / clump
			var count := (
				mini(
					2,
					int(expected_objects) + (1 if rng.randf() < fmod(expected_objects, 1.0) else 0)
				)
				* clump
			)
			if count == 0:
				continue
			if count > 1:
				group_count += 1
			var x: float = plot.origin.x + (k % n + .5) * dx
			var z: float = plot.origin.y + (int(k / n) + .5) * dx
			for i in count:
				var px := x + rng.randf_range(-dx * .43, dx * .43)
				var pz := z + rng.randf_range(-dx * .43, dx * .43)
				var size := rng.randf_range(.7, 1.3)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
				transforms.append(
					Transform3D(basis, Vector3(px, model.land.height_at(px, pz) + .015, pz))
				)
				colors.append(Color.WHITE * rng.randf_range(.85, 1.1))
	body_count = transforms.size()
	bodies.multimesh.instance_count = body_count
	for i in body_count:
		bodies.multimesh.set_instance_transform(i, transforms[i])
		bodies.multimesh.set_instance_color(i, colors[i])
