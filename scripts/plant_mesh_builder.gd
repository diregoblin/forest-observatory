class_name ForestPlantMeshBuilder
extends RefCounted


static func build(definition: ForestPlantDefinition) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for module in definition.modules:
		assert(module.mesh != null, "Plant module needs a mesh")
		for i in module.count:
			var angle := float(i) * module.turn
			var offset := module.offset + module.step * float(i)
			offset += Vector3(cos(angle), 0, sin(angle)) * module.radial_offset
			var scale_v := module.scale_start + module.scale_step * float(i)
			assert(scale_v.x > 0 and scale_v.y > 0 and scale_v.z > 0)
			var rotation := (
				Basis(Vector3.UP, angle) * Basis.from_euler(module.rotation_degrees * PI / 180.0)
			)
			var transform := Transform3D(rotation.scaled(scale_v), offset)
			var color := module.color
			color.a = 0.0 if module.foliage else 1.0  # Geometry tag, not transparency.
			_append(surface, module.mesh, transform, color)
	return surface.commit()


static func _append(surface: SurfaceTool, mesh: Mesh, transform: Transform3D, color: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_transform := transform.basis.inverse().transposed()
	for index in indices:
		surface.set_color(color)
		surface.set_normal((normal_transform * normals[index]).normalized())
		surface.add_vertex(transform * vertices[index])
