class_name ForestBarrierView
extends Node3D


## Visualizes the SAME span and crest used by the solver; no hydraulic rules.
func configure(barrier: ForestBarrier, height: float) -> void:
	var center := (barrier.start + barrier.end) / 2
	var span := barrier.end - barrier.start
	var direction := Vector3(span.x, 0, span.y).normalized()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.23, .15, .09)
	material.roughness = 1
	var count := 9
	for i in count:
		var log_mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.height = span.length()
		cylinder.top_radius = .18
		cylinder.bottom_radius = .24
		cylinder.radial_segments = 7
		log_mesh.mesh = cylinder
		log_mesh.material_override = material
		log_mesh.basis = Basis(Quaternion(Vector3.UP, direction))
		log_mesh.position = Vector3(
			center.x, barrier.crest - height + float(i) / float(count - 1) * height, center.y
		)
		add_child(log_mesh)
	visible = false
