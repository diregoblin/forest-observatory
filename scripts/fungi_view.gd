class_name ForestFungiView
extends Node3D

## A cell may display one body or a clump. These are representative objects;
## the conserved fruit-carbon pool, not the rounded instance count, is the state.
var model: ForestFungi
var bodies := MultiMeshInstance3D.new()
var batches: Array[MultiMeshInstance3D] = []
var body_count := 0
var group_count := 0
var last_tick := -1
var pending_tick := -1
var pending_plots: Array[Dictionary] = []
var pending_transforms: Array = []
var pending_colors: Array = []
var pending_groups := 0
var pending_cell := 0
var pending_plot := 0
var last_batch_cells := 0
var display_rng := RandomNumberGenerator.new()
var mesh_faces: Array[PackedVector3Array] = []
var displayed_shapes := {}
var pending_shapes := {}
var body_material := StandardMaterial3D.new()


func _init() -> void:
	body_material.vertex_color_use_as_albedo = true
	body_material.roughness = .87


func configure(fungi: ForestFungi) -> void:
	model = fungi
	for plot in model.plots:
		batches.append(_make_batch(plot.definition))
	bodies.free()
	bodies = batches[0]
	refresh()


func _make_batch(definition: ForestFungusDefinition) -> MultiMeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := CylinderMesh.new()
	stem.top_radius = definition.stem_radius_m * .7
	stem.bottom_radius = definition.stem_radius_m
	stem.height = definition.stem_height_m
	stem.radial_segments = 7
	ForestPlantMeshBuilder._append(
		surface,
		stem,
		Transform3D(Basis.IDENTITY, Vector3.UP * stem.height / 2),
		definition.stem_color
	)
	var cap: Mesh = _cap_mesh(definition)
	ForestPlantMeshBuilder._append(
		surface,
		cap,
		Transform3D(Basis.IDENTITY, Vector3.UP * definition.stem_height_m),
		definition.cap_color
	)
	var mesh := ForestPlantMeshBuilder.commit_indexed(surface)
	mesh_faces.append(mesh.get_faces())
	mesh.surface_set_material(0, body_material)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multi
	add_child(batch)
	return batch


func _cap_mesh(definition: ForestFungusDefinition) -> Mesh:
	if definition.cap_profile == &"dome":
		var cap := SphereMesh.new()
		cap.radius = definition.cap_radius_m
		cap.height = definition.cap_radius_m * definition.cap_height_ratio
		cap.radial_segments = 12
		cap.rings = 5
		return cap
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := definition.cap_radius_m
	for segment in 12:
		var a := segment * TAU / 12
		var b := (segment + 1) * TAU / 12
		var vertices := [
			Vector3(0, -radius * .25, 0),
			Vector3(cos(a) * radius, radius * .12, sin(a) * radius),
			Vector3(cos(b) * radius, radius * .12, sin(b) * radius)
		]
		for vertex in vertices:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
	return ForestPlantMeshBuilder.commit_indexed(surface)


func refresh() -> void:
	# Explicit instant refresh for startup, load and read-only preview captures.
	if pending_tick >= 0:
		pending_tick = -1
	_begin_refresh()
	while pending_tick >= 0:
		_advance_refresh(0)


func advance_display() -> void:
	if pending_tick < 0:
		_begin_refresh()
	last_batch_cells = 0
	if pending_tick >= 0:
		_advance_refresh(1000)


func _begin_refresh() -> void:
	if last_tick == model.revision:
		return
	pending_tick = model.revision
	pending_plots.clear()
	# Packed arrays are COW: finish a consistent generation even if biology advances.
	for index in model.plots.size():
		var plot: Dictionary = model.plots[index]
		pending_plots.append(
			{
				"origin": plot.origin,
				"fruit": plot.fields.fruit,
				"definition": plot.definition,
				"batch": index
			}
		)
	pending_shapes.clear()
	pending_transforms.clear()
	pending_colors.clear()
	for _batch in batches:
		pending_transforms.append([])
		pending_colors.append([])
	pending_groups = 0
	pending_cell = 0
	pending_plot = 0


func _advance_refresh(budget_usec: int) -> void:
	var started := Time.get_ticks_usec()
	while pending_plot < pending_plots.size():
		var plot: Dictionary = pending_plots[pending_plot]
		var fruit: PackedFloat64Array = plot.fruit
		_display_cell(pending_cell, plot, fruit[pending_cell])
		pending_cell += 1
		last_batch_cells += 1
		if pending_cell >= fruit.size():
			pending_cell = 0
			pending_plot += 1
		if budget_usec > 0 and last_batch_cells % 64 == 0:
			if Time.get_ticks_usec() - started >= budget_usec:
				return
	body_count = 0
	group_count = pending_groups
	for index in batches.size():
		var transforms: Array = pending_transforms[index]
		var colors: Array = pending_colors[index]
		var multi := batches[index].multimesh
		body_count += transforms.size()
		if multi.instance_count != transforms.size():
			multi.instance_count = transforms.size()
		for i in transforms.size():
			multi.set_instance_transform(i, transforms[i])
			multi.set_instance_color(i, colors[i])
	displayed_shapes = pending_shapes.duplicate()
	last_tick = pending_tick
	pending_tick = -1


func _display_cell(k: int, plot: Dictionary, carbon: float) -> void:
	if carbon <= 0:
		return
	var config := model.land.settings
	var n := config.fungi_resolution
	var dx := config.fungi_cell_m
	# A per-cell seed keeps objects stable when another cell starts/stops fruiting.
	display_rng.seed = config.seed + 8173 + k * 7919 + int(plot.origin.x * 131)
	var expected: float = carbon * dx * dx / plot.definition.representative_body_kg
	# Stable mixture of solitary bodies and clumps, with the same expected biomass.
	var clump := 3 if display_rng.randf() < .35 else 1
	var expected_objects := expected / clump
	var count := (
		mini(
			2,
			int(expected_objects) + (1 if display_rng.randf() < fmod(expected_objects, 1.0) else 0)
		)
		* clump
	)
	if count == 0:
		return
	if count > 1:
		pending_groups += 1
	var x: float = plot.origin.x + (k % n + .5) * dx
	var z: float = plot.origin.y + (int(k / n) + .5) * dx
	for i in count:
		var px := x + display_rng.randf_range(-dx * .43, dx * .43)
		var pz := z + display_rng.randf_range(-dx * .43, dx * .43)
		var size := display_rng.randf_range(.7, 1.3)
		var basis := Basis(Vector3.UP, display_rng.randf() * TAU).scaled(Vector3.ONE * size)
		var local := Transform3D(basis, Vector3(px, model.land.height_at(px, pz) + .015, pz))
		pending_transforms[plot.batch].append(local)
		var submitted := (global_transform if is_inside_tree() else self.transform) * local
		var bounds: AABB = submitted * batches[plot.batch].multimesh.mesh.get_aabb()
		var id: int = plot.batch * n * n + k
		var part := {"transform": submitted, "bounds": bounds, "faces": mesh_faces[plot.batch]}
		if not pending_shapes.has(id):
			pending_shapes[id] = {"bounds": bounds, "parts": []}
		pending_shapes[id].bounds = pending_shapes[id].bounds.merge(bounds)
		pending_shapes[id].parts.append(part)
		pending_colors[plot.batch].append(Color.WHITE * display_rng.randf_range(.85, 1.1))


func selection_ids() -> Array:
	return displayed_shapes.keys()


func selection_shape(id: int) -> Dictionary:
	return displayed_shapes.get(id, {})
