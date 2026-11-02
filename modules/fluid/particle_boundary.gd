extends Node3D
var settings: FluidSettings


@export_file("*.glb") var source_scene_path: String
@export_range(16, 20000, 16) var particle_count: int = 1600
@export_range(1, 4, 1) var surface_layers: int = 1
@export var particle_spacing: float = 0.10
@export var particle_radius: float = 0.055
@export var surface_inset: float = 0.0006
@export var particle_color := Color(1.0, 0.03, 0.01, 1.0)
@export var animate_test_motion := true
@export var boundary_velocity_scale: float = 1.0

var surface_particles: PackedVector3Array
var multimesh_instance: MultiMeshInstance3D
var source_root: Node3D
var _phase := 0.0
var _base_transform: Transform3D
var _previous_global_transform: Transform3D
var linear_velocity := Vector3.ZERO
var angular_velocity := Vector3.ZERO

func _ready() -> void:
	process_physics_priority = -10
	_base_transform = global_transform
	_previous_global_transform = _base_transform
	_build_source()
	_build_surface_particles()
	_build_particle_visual()
	print("ParticleRigidBody3D: generated %d surface particles from %s (%d layers)" % [surface_particles.size(), source_scene_path, surface_layers])

func _build_source() -> void:
	if source_scene_path.is_empty():
		return
	var packed := load(source_scene_path) as PackedScene
	if packed == null:
		push_error("ParticleRigidBody3D: cannot load " + source_scene_path)
		return
	source_root = packed.instantiate()
	source_root.name = "SourceMesh"
	source_root.visible = true
	add_child(source_root)

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)

func _build_surface_particles() -> void:
	surface_particles.clear()
	if source_root == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(source_root, meshes)
	var triangles: Array[Dictionary] = []
	var total_area := 0.0
	var vertex_sum := Vector3.ZERO
	var vertex_count := 0
	for mesh_node in meshes:
		var mesh_to_body: Transform3D = global_transform.affine_inverse() * mesh_node.global_transform
		var array_mesh := mesh_node.mesh as ArrayMesh
		if array_mesh == null:
			continue
		for surface in array_mesh.get_surface_count():
			var arrays := array_mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices = PackedInt32Array(range(vertices.size()))
			for i in range(0, indices.size() - 2, 3):
				var a: Vector3 = mesh_to_body * vertices[indices[i]]
				var b: Vector3 = mesh_to_body * vertices[indices[i + 1]]
				var c: Vector3 = mesh_to_body * vertices[indices[i + 2]]
				vertex_sum += a + b + c
				vertex_count += 3
				var area := (b - a).cross(c - a).length() * 0.5
				if area > 0.000001:
					triangles.append({"a": a, "b": b, "c": c, "area": area})
					total_area += area
	if triangles.is_empty():
		return
	particle_count = settings.boundary_sample_count(total_area)
	var surface_center := vertex_sum / float(maxi(vertex_count, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = settings.seed_value
	var per_layer := maxi(1, int(ceil(float(particle_count) / float(surface_layers))))
	for layer in range(surface_layers):
		for n in per_layer:
			var pick := rng.randf() * total_area
			var tri: Dictionary = triangles[triangles.size() - 1]
			for candidate in triangles:
				pick -= candidate.area
				if pick <= 0.0:
					tri = candidate
					break
			var u := rng.randf()
			var v := rng.randf()
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			var p: Vector3 = tri.a + (tri.b - tri.a) * u + (tri.c - tri.a) * v
			var normal: Vector3 = (tri.b - tri.a).cross(tri.c - tri.a).normalized()
			if normal.dot(p - surface_center) < 0.0:
				normal = -normal
			var inward_offset := surface_inset + float(layer) * particle_spacing
			surface_particles.append(p - normal * inward_offset)
			if surface_particles.size() >= particle_count:
				return

func _build_particle_visual() -> void:
	multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.name = "SurfaceParticles"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = surface_particles.size()
	var sphere := SphereMesh.new()
	sphere.radius = particle_radius
	sphere.height = particle_radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3
	mm.mesh = sphere
	for i in surface_particles.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, surface_particles[i]))
		mm.set_instance_color(i, particle_color)
	multimesh_instance.multimesh = mm
	var debug_material := StandardMaterial3D.new()
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_material.albedo_color = Color(1.0, 0.0, 0.0, 1.0)
	debug_material.emission_enabled = true
	debug_material.emission = Color(1.0, 0.0, 0.0, 1.0)
	debug_material.emission_energy_multiplier = 2.0
	multimesh_instance.material_override = debug_material
	multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(multimesh_instance)

func _physics_process(delta: float) -> void:
	if animate_test_motion:
		_phase += delta
		var t := _base_transform
		t.origin += Vector3(sin(_phase * 0.8) * 1.5, sin(_phase * 1.3) * 0.35, 0.0)
		t.basis = Basis(Vector3.UP, sin(_phase * 0.55) * 0.22) * _base_transform.basis
		global_transform = t
	update_motion(delta)

## Call after scripted/interactive motion, before the fluid step. Angular
## velocity is in WORLD coordinates, matching omega cross world-space lever.
func update_motion(delta: float) -> void:
	if delta > 0.0:
		linear_velocity = (global_transform.origin - _previous_global_transform.origin) / delta
		var dq := global_transform.basis.get_rotation_quaternion() * _previous_global_transform.basis.get_rotation_quaternion().inverse()
		if dq.w < 0.0: dq = -dq
		angular_velocity = dq.get_axis() * dq.get_angle() / delta
	_previous_global_transform = global_transform

func get_world_particle_positions() -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(surface_particles.size())
	for i in surface_particles.size():
		result[i] = global_transform * surface_particles[i]
	return result

func get_world_particle_velocities() -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(surface_particles.size())
	for i in surface_particles.size():
		var r := (global_transform * surface_particles[i]) - global_transform.origin
		result[i] = (linear_velocity + angular_velocity.cross(r)) * boundary_velocity_scale
	return result

func get_world_particle_radius() -> float:
	return particle_radius * max(global_transform.basis.get_scale().x, max(global_transform.basis.get_scale().y, global_transform.basis.get_scale().z))

func set_boundary_particles_visible(visible_state: bool) -> void:
	if is_instance_valid(multimesh_instance):
		multimesh_instance.visible = visible_state
