extends "res://tools/check_animals.gd"

const FAUNA = ["hare", "fox", "bank_vole", "thrush", "boar"]


func specimen(name: String, gene := .5) -> Dictionary:
	var state := chamber()
	var a: ForestAnimals = state.animals
	var d: ForestAnimalDefinition = load("res://data/animals/%s.tres" % name).duplicate(true)
	d.validate()
	a.definitions[0] = d
	a.biomass_c[0] = d.initial_elements.x
	a.positions[0] = Vector3.ZERO
	a.previous_positions[0] = Vector3.ZERO
	a.path_history[0] = {
		"points": PackedVector3Array([Vector3.ZERO]), "times": PackedFloat64Array([0])
	}
	a.actions[0] = "rest"
	a.yaw[0] = 0
	for key in a.phenotypes[0]:
		a.phenotypes[0][key] = gene
	var view := ForestAnimalsView.new()
	root.add_child(view)
	view.configure(a)
	return {"model": a, "view": view, "definition": d, "state": state}


func verify(s: Dictionary) -> Dictionary:
	var a: ForestAnimals = s.model
	var view: ForestAnimalsView = s.view
	var frozen := a.snapshot()
	var geometry: Mesh = view.batches[0].multimesh.mesh
	var arrays := geometry.surface_get_arrays(0)
	assert(view.face_tags[0].size() == geometry.get_faces().size())
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		assert(arrays[Mesh.ARRAY_VERTEX][i].is_finite())
		assert(arrays[Mesh.ARRAY_NORMAL][i].is_normalized())
	var examined := 0
	for clip in view.motion_library.get_animation_list():
		for fraction in [0.0, .13, .37, .69, .91]:
			view._animate(0, clip, view.motion_library.get_animation(clip).length * fraction)
			var shape := view.selection_shape(0)
			var conservative := view.display_shape(0).bounds as AABB
			for i in range(0, shape.faces.size(), 19):
				var point: Vector3 = shape.transform * shape.faces[i]
				assert(conservative.grow(.00001).has_point(point))
				assert(shape.bounds.grow(.00001).has_point(point))
			for c in ForestAnimalMotion.curves.channels.size():
				var uniform: String = "pose_" + ForestAnimalMotion.curves.channels[c]
				assert(
					(
						absf(
							(
								view.batches[0].get_instance_shader_parameter(uniform)
								- view.animation_poses[0][c]
							)
						)
						< .00001
					)
				)
			examined += 1
	assert(a.snapshot() == frozen)
	# Renderers must consume morphology, not the species identifier.
	var before := var_to_bytes(arrays)
	s.definition.species_id = &"unseen_resource_only_animal"
	view.rebuild()
	assert(var_to_bytes(view.batches[0].multimesh.mesh.surface_get_arrays(0)) == before)
	# Every lining shares the actual ear base, not its own mesh centre.
	var hinges := {}
	for i in s.definition.part_roles.size():
		if s.definition.part_roles[i] == "ear":
			var p: Vector3 = s.definition.part_pivots[i]
			hinges[p] = hinges.get(p, 0) + 1
	for count in hinges.values():
		assert(count >= 2)
	return {
		"triangles": geometry.get_faces().size() / 3,
		"poses": examined,
		"parts": s.definition.part_shapes.size()
	}


func _run() -> void:
	if not _check_ear_connection():
		quit(1)
		return
	for shape in ["barrel", "taper", "leaf", "plume", "feather"]:
		var mesh := ForestAnimalGeometry.build(shape)
		var arrays := mesh.surface_get_arrays(0)
		var rightmost := 0
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			if arrays[Mesh.ARRAY_VERTEX][i].x > arrays[Mesh.ARRAY_VERTEX][rightmost].x:
				rightmost = i
		assert(
			arrays[Mesh.ARRAY_NORMAL][rightmost].x > .5, "Loft normals must point outward: " + shape
		)
	var records := []
	for name in FAUNA:
		for gene in [.1, .5, .9]:
			var s := specimen(name, gene)
			var record := verify(s)
			record["species"] = name
			record["gene"] = gene
			records.append(record)
			s.view.free()
	var report := {
		"passed": true,
		"species": 5,
		"records": records,
		"unchanged_models": true,
		"resource_only_geometry": true,
		"posed_bounds_and_shader_cpu_channels": true
	}
	FileAccess.open("res://artifacts/fauna-geometry-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("FAUNA_GEOMETRY PASS ", JSON.stringify(report))
	quit()


func _check_ear_connection() -> bool:
	# Two touching boxes form one ear. Changing its genes must preserve contact,
	# independently of how the renderer computes the transformation.
	var maximum_gap := 0.0
	for gene in [.1, .5, .9]:
		var s := specimen("hare")
		var d: ForestAnimalDefinition = s.definition
		var hinge := Vector3(.1, .2, .1)
		var rotation := Vector3(-7, 0, -15)
		var axis := Basis.from_euler(rotation * PI / 180)
		d.part_shapes = PackedStringArray(["box", "box"])
		d.part_dimensions = [Vector3(.1, .2, .05), Vector3(.1, .2, .05)]
		d.part_offsets = [hinge + axis * Vector3.UP * .1, hinge + axis * Vector3.UP * .3]
		d.part_rotations = [rotation, rotation]
		d.part_colors = [Color.WHITE, Color.WHITE]
		d.part_roles = PackedStringArray(["ear", "ear"])
		d.part_pivots = [hinge, hinge]
		s.model.phenotypes[0].ears = gene
		s.model.phenotypes[0].ear_angle = 1 - gene
		s.view.rebuild()
		var faces: PackedVector3Array = s.view.mesh_faces[0]
		assert(faces.size() == 72)
		var gap := INF
		for i in 36:
			for j in range(36, 72):
				gap = minf(gap, faces[i].distance_to(faces[j]))
		maximum_gap = maxf(maximum_gap, gap)
		s.view.free()
	print("SHARED_EAR_CONTACT maximum gap ", maximum_gap)
	return maximum_gap < .00001
