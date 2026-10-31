class_name ForestAnimalsView
extends Node3D

## Presentation only: common primitive builder and one MultiMesh per resource.
var model: ForestAnimals
var batches: Array[MultiMeshInstance3D] = []
var mesh_faces: Array[PackedVector3Array] = []
var displayed_transforms := {}


func configure(animals: ForestAnimals) -> void:
	model = animals
	for definition in model.definitions:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in definition.part_shapes.size():
			var mesh: PrimitiveMesh
			var dimensions: Vector3 = definition.part_dimensions[i]
			match definition.part_shapes[i]:
				"box":
					mesh = BoxMesh.new()
					mesh.size = Vector3.ONE
				"cylinder", "cone":
					mesh = CylinderMesh.new()
					mesh.top_radius = 0.0 if definition.part_shapes[i] == "cone" else .5
					mesh.bottom_radius = .5
					mesh.height = 1
					mesh.radial_segments = 8
				_:
					mesh = SphereMesh.new()
					mesh.radius = .5
					mesh.height = 1
					mesh.radial_segments = 10
					mesh.rings = 5
			var basis := Basis.from_euler(definition.part_rotations[i] * PI / 180).scaled(
				dimensions
			)
			ForestPlantMeshBuilder._append(
				surface,
				mesh,
				Transform3D(basis, definition.part_offsets[i]),
				definition.part_colors[i]
			)
		var geometry := surface.commit()
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = .95
		geometry.surface_set_material(0, material)
		mesh_faces.append(geometry.get_faces())
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.use_colors = true
		batch.multimesh.mesh = geometry
		add_child(batch)
		batches.append(batch)
	refresh()


func refresh(display_alpha := 1.0) -> void:
	for s in batches.size():
		var ids := []
		for id in model.species.size():
			if model.species[id] == s:
				ids.append(id)
		var multi := batches[s].multimesh
		multi.instance_count = ids.size()
		for index in ids.size():
			var id: int = ids[index]
			var position := model.display_position(id, display_alpha)
			var basis := Basis(Vector3.UP, model.yaw[id])
			if not model.alive[id]:
				basis *= Basis(Vector3.FORWARD, PI / 2)
				position.y += .1
			multi.set_instance_transform(index, Transform3D(basis, position))
			var parent_transform := global_transform if is_inside_tree() else transform
			displayed_transforms[id] = parent_transform * Transform3D(basis, position)
			multi.set_instance_color(index, Color.WHITE if model.alive[id] else Color(.55, .5, .45))


func selection_shape(id: int) -> Dictionary:
	if not displayed_transforms.has(id):
		return {}
	var s: int = model.species[id]
	return {
		"transform": displayed_transforms[id],
		"faces": mesh_faces[s],
		"bounds": displayed_transforms[id] * batches[s].multimesh.mesh.get_aabb()
	}
