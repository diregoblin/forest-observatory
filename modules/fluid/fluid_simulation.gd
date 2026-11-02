extends Node3D
const SettingsType = preload("res://modules/fluid/fluid_settings.gd")

@export var settings: FluidSettings
## Assign the scene's native GPUParticlesCollisionSDF3D, baked in the editor.
@export var collision_sdf: NodePath
var sdf_node: GPUParticlesCollisionSDF3D
var derived: Dictionary
var profiler_mode := false
var world_particle_radius: float
var radius: float
var smoothing_radius: float
var viscosity_multiplier: float
var count: int
var length: float
var width: float
var height: float
var shader_local_size := 256
var int_size := 4
var hash_oversizing := 2
var owned_rids: Array[RID] = []
var diagnostic_positions: RID
var diagnostic_velocities: RID
var elapsed_simulation := 0.0
var last_substeps := 0
var liquid_profile: FluidLiquid

var positions: PackedVector4Array = []
var pipeline :RID
var sum_pipeline: RID
var uniform_set :RID
var compute_uniforms: Array[RDUniform] = []
var neighbor_count_buffer: RID
var neighbor_index_buffer: RID
var boundary_bounds_buffer: RID
var bucket_bounds_buffer: RID
var _scan_constants: Array[PackedByteArray] = []
var _boundary_local_bounds := AABB()
var first_step_sum_uniform_set: RID
var second_step_sum_uniform_set: RID
var boundary_body: Node
var boundary_positions_buffer: RID
var boundary_velocities_buffer: RID
var boundary_count: int = 0
var boundary_radius: float = 0.0
var use_collision_sdf := false
var _boundary_cache_key: Array = []
var _boundary_cached_surface := PackedVector3Array()
var boundary_upload_batches := 0
var boundary_cache_hits := 0
var boundary_gpu_enabled := true
var boundary_cache_enabled := true
var _boundary_local_buffer: RID
var _boundary_metadata: RID
var _boundary_pipeline: RID
var _boundary_set: RID
var _boundary_capacity := 0
const BoundaryType = preload("res://modules/fluid/particle_boundary.gd")

var gravity: float
var default_density: float
var pressure_multiply: float
var damping: float
var rows = 20

#not used
var mass: float = 100:
	set(val):
		mass = val

var rd := RenderingServer.get_rendering_device()

var hash_count: PackedInt32Array
var pref_sum_hash_count: PackedInt32Array
var hash_indexes: PackedInt32Array

func _ready() -> void:
	if settings == null:
		push_error("Assign FluidSettings to FluidSimulation")
		return
	# Runtime controls must not mutate a shared on-disk preset or another scene.
	settings = settings.duplicate()
	derived = settings.derive()
	if derived.is_empty(): return
	radius = derived.radius
	world_particle_radius = radius
	smoothing_radius = derived.h
	default_density = derived.density
	pressure_multiply = derived.pressure
	viscosity_multiplier = derived.viscosity
	gravity = settings.gravity
	damping = SettingsType.RESTITUTION
	count = derived.count
	length = settings.room_size.x
	height = settings.room_size.y
	width = settings.room_size.z
	sdf_node = get_node_or_null(collision_sdf) as GPUParticlesCollisionSDF3D if not collision_sdf.is_empty() else null
	use_collision_sdf = sdf_node != null and sdf_node.texture != null
	if sdf_node != null and sdf_node.texture == null:
		push_warning("Static collision texture is empty. Select CollisionSDF and Bake SDF after adding static meshes.")
	set_particles()

func set_particles():
	positions.clear()
	var gap: float = derived.spacing
	var side: int = ceili(pow(float(count), 1.0 / 3.0))
	var extent: float = (side - 1) * gap
	var origin := Vector3(length * 0.5 - extent * 0.5, height * 0.55, width * 0.5 - extent * 0.5)
	assert(extent + 2.0 * radius < minf(length, width), "Initial fluid block does not fit room")
	for i in range(count):
		var p := origin + Vector3(i % side, (i / side) % side, i / (side * side)) * gap
		positions.append(Vector4(p.x, p.y, p.z, 0.0))
	rebuild_buffers()

func sim_step(delta: float):
	last_substeps = 1
	_update_boundary_buffers()
	_sim_substep(delta)
	elapsed_simulation += delta

## Live material change: no allocation/reset/readback and no lost momentum.
func apply_liquid(liquid: FluidLiquid) -> bool:
	if liquid == null or not liquid.valid() or derived.is_empty(): return false
	settings.viscosity = liquid.viscosity
	derived = settings.derive()
	viscosity_multiplier = derived.viscosity
	liquid_profile = liquid
	return true

func diagnostics() -> Dictionary:
	var p := rd.buffer_get_data(diagnostic_positions).to_float32_array()
	var v := rd.buffer_get_data(diagnostic_velocities).to_float32_array()
	var vmax := 0.0
	var sum_v2 := 0.0
	var ymax := 0.0
	var invalid := 0
	var outside := 0
	for i in range(count):
		var speed := Vector3(v[4*i], v[4*i+1], v[4*i+2]).length()
		var point := Vector3(p[4*i],p[4*i+1],p[4*i+2])
		if point.x < -1e-6 or point.y < -1e-6 or point.z < -1e-6 or point.x > length+1e-6 or point.y > height+1e-6 or point.z > width+1e-6: outside += 1
		if not is_finite(speed) or not point.is_finite():
			invalid += 1
		vmax = maxf(vmax, speed)
		sum_v2 += speed * speed
		ymax = maxf(ymax, p[4*i+1])
	return {"time": elapsed_simulation, "count": count, "invalid": invalid,
		"outside_room":outside,"max_speed": vmax, "rms_speed": sqrt(sum_v2 / count), "max_y": ymax, "substeps": last_substeps}

func register_boundary_body(body: Node) -> void:
	boundary_body = body
	boundary_count = body.surface_particles.size() if "surface_particles" in body else 0
	boundary_radius = body.get_world_particle_radius() / max(global_transform.basis.get_scale().x, 0.0001)
	rebuild_buffers()

func _boundary_gpu_update(surface: PackedVector3Array) -> bool:
	# Upload the local samples only when geometry changes. Moving rigid poses
	# transform the same samples on GPU, including angular wall velocity.
	if surface.size() != _boundary_capacity and _boundary_local_buffer.is_valid():
		push_error("Boundary sample count changed; register/rebuild at a scene reset before stepping")
		return false
	if not _boundary_local_buffer.is_valid():
		_boundary_capacity = surface.size()
		_boundary_local_buffer = rd.storage_buffer_create(maxi(1, surface.size()) * 16)
		_boundary_metadata = rd.storage_buffer_create(160)
		var file: RDShaderFile = preload("res://modules/fluid/compute_shader.gd").load_file("res://modules/fluid/shaders/boundary_transform.glsl")
		var spirv := file.get_spirv()
		if not spirv.compile_error_compute.is_empty():
			push_error(spirv.compile_error_compute)
			return false
		var shader := rd.shader_create_from_spirv(spirv)
		_boundary_pipeline = rd.compute_pipeline_create(shader)
		var uniforms: Array[RDUniform] = [get_buffer_uniform(0, _boundary_local_buffer), get_buffer_uniform(1, boundary_positions_buffer), get_buffer_uniform(2, boundary_velocities_buffer), get_buffer_uniform(3, _boundary_metadata)]
		_boundary_set = rd.uniform_set_create(uniforms, shader, 0)
		owned_rids.append_array([_boundary_local_buffer, _boundary_metadata, shader])
	if surface != _boundary_cached_surface or _boundary_cache_key.is_empty():
		var local := PackedVector4Array()
		local.resize(surface.size())
		if not surface.is_empty(): _boundary_local_bounds = AABB(surface[0],Vector3.ZERO)
		for i in surface.size():
			local[i] = Vector4(surface[i].x, surface[i].y, surface[i].z, 1.0)
			_boundary_local_bounds = _boundary_local_bounds.expand(surface[i])
		var bytes := local.to_byte_array()
		if not bytes.is_empty(): rd.buffer_update(_boundary_local_buffer, 0, bytes.size(), bytes)
	var inverse := global_transform.affine_inverse()
	var body_transform: Transform3D = boundary_body.global_transform
	var body_projection := Projection(body_transform)
	var inverse_projection := Projection(inverse)
	var linear: Vector3 = boundary_body.linear_velocity
	var angular: Vector3 = boundary_body.angular_velocity
	var metadata := PackedVector4Array([body_projection.x,body_projection.y,
		body_projection.z,body_projection.w,inverse_projection.x,inverse_projection.y,
		inverse_projection.z,inverse_projection.w,
		Vector4(linear.x,linear.y,linear.z,boundary_body.boundary_velocity_scale),
		Vector4(angular.x,angular.y,angular.z,0)]).to_byte_array()
	rd.buffer_update(_boundary_metadata, 0, metadata.size(), metadata)
	if not surface.is_empty():
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, _boundary_pipeline)
		rd.compute_list_bind_uniform_set(list, _boundary_set, 0)
		rd.compute_list_set_push_constant(list, PackedInt32Array([surface.size(),0,0,0]).to_byte_array(), 16)
		rd.compute_list_dispatch(list, ceili(surface.size()/256.0), 1, 1)
		rd.compute_list_end()
	# Transform a conservative local box, with an outward float32 margin. This
	# avoids scanning thousands of boundary candidates for distant fluid points.
	var relative := inverse * body_transform
	var box: AABB = relative * _boundary_local_bounds
	var world_box: AABB = body_transform * _boundary_local_bounds
	var world_magnitude := maxf(1.0, world_box.position.length()+world_box.size.length())
	# Include intermediate-world rounding, even when large translations cancel.
	var inverse_norm := inverse.basis.x.length()+inverse.basis.y.length()+inverse.basis.z.length()
	var margin := maxf(1.,world_magnitude*inverse_norm+inverse.origin.length()+box.end.length())*2e-5
	box = box.grow(margin)
	var valid := 1.0 if box.position.is_finite() and box.end.is_finite() else 0.0
	var bounds := PackedFloat32Array([box.position.x,box.position.y,box.position.z,valid,box.end.x,box.end.y,box.end.z,0.]).to_byte_array()
	rd.buffer_update(boundary_bounds_buffer,0,bounds.size(),bounds)
	boundary_count = surface.size()
	boundary_radius = boundary_body.get_world_particle_radius() / maxf(global_transform.basis.get_scale().x, 0.0001)
	boundary_upload_batches += 1
	return true

func _update_boundary_buffers() -> void:
	if boundary_body == null or boundary_positions_buffer == RID():
		return
	# Cache only the owned provider whose complete inputs are known. Other
	# providers retain the original update path. Snapshot the packed surface:
	# GDScript packed-array references otherwise share in-place mutations.
	var cacheable: bool = boundary_cache_enabled and boundary_body.get_script() == BoundaryType
	var key: Array = []
	var surface := PackedVector3Array()
	if cacheable:
		surface = boundary_body.surface_particles
		key = [boundary_body.get_instance_id(), global_transform,
			boundary_body.global_transform, boundary_body.particle_radius,
			boundary_body.linear_velocity, boundary_body.angular_velocity,
			boundary_body.boundary_velocity_scale]
		if key == _boundary_cache_key and surface == _boundary_cached_surface:
			boundary_cache_hits += 1
			return
	if cacheable and boundary_gpu_enabled:
		if _boundary_gpu_update(surface):
			_boundary_cache_key = key
			if surface != _boundary_cached_surface:
				_boundary_cached_surface = surface.duplicate()
		return
	if boundary_bounds_buffer.is_valid(): rd.buffer_update(boundary_bounds_buffer,0,32,PackedFloat32Array([0.,0.,0.,0.,0.,0.,0.,0.]).to_byte_array())
	if not cacheable:
		_boundary_cache_key.clear()
		_boundary_cached_surface = PackedVector3Array()
	var boundary_positions_local := PackedVector4Array()
	var boundary_velocities_local := PackedVector4Array()
	var inv := global_transform.affine_inverse()
	var sim_scale: float = max(global_transform.basis.get_scale().x, 0.0001)
	for p: Vector3 in boundary_body.get_world_particle_positions():
		var local_p: Vector3 = inv * p
		boundary_positions_local.append(Vector4(local_p.x, local_p.y, local_p.z, 1.0))
	for v: Vector3 in boundary_body.get_world_particle_velocities():
		var local_v: Vector3 = inv.basis * v
		boundary_velocities_local.append(Vector4(local_v.x, local_v.y, local_v.z, 0.0))
	boundary_count = boundary_positions_local.size()
	boundary_radius = boundary_body.get_world_particle_radius() / sim_scale
	if boundary_count > 0:
		var pos_bytes := boundary_positions_local.to_byte_array()
		var vel_bytes := boundary_velocities_local.to_byte_array()
		rd.buffer_update(boundary_positions_buffer, 0, pos_bytes.size(), pos_bytes)
		rd.buffer_update(boundary_velocities_buffer, 0, vel_bytes.size(), vel_bytes)
		boundary_upload_batches += 1
	if cacheable:
		_boundary_cache_key = key
		_boundary_cached_surface = surface.duplicate()

func params_to_byte_array(params) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(params.size()*4)
	for i in params.size():
		if params[i] is int: data.encode_s32(i*4, params[i])
		else: data.encode_float(i*4, params[i])
	return data



#func _draw() -> void:
	#for x in positions:
		#draw_circle(x, radius, Color.BLUE)

func _process(_delta: float) -> void:
	pass

# Compatibility entry point. The removed profiler used dummy SDFs and tried
# submit/sync on the main RenderingDevice, producing invalid measurements.
func debug_sim_step(delta):
	push_warning("Use tools/benchmark.gd for CPU/GPU profiling of the real scene")
	sim_step(delta)

func _sim_substep(delta):
	var total_count := count + boundary_count
	var fluid_groups := ceili(float(count) / shader_local_size)
	var total_groups := ceili(float(total_count) / shader_local_size)
	var hash_groups := ceili(float(total_count * hash_oversizing) / shader_local_size)
	# Serialize the shared block once. Only its mode changes between dispatches.
	var data: PackedByteArray = params_to_byte_array([0, radius, smoothing_radius,
		gravity, default_density, pressure_multiply, damping, count,
		total_count * hash_oversizing, mass, delta, length, width, height,
		viscosity_multiplier, 0, 0, boundary_count, boundary_radius,
		1 if use_collision_sdf else 0, float(derived.contact_epsilon),
		float(derived.density_floor), 0.0, 0.0])
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	for mode in [0, 1]:
		data.encode_s32(0, mode)
		rd.compute_list_set_push_constant(list, data, data.size())
		rd.compute_list_dispatch(list, hash_groups if mode == 0 else total_groups, 1, 1)
		rd.compute_list_add_barrier(list)
	rd.compute_list_bind_compute_pipeline(list, sum_pipeline)
	for i in _scan_constants.size():
		rd.compute_list_bind_uniform_set(list, first_step_sum_uniform_set if i % 2 == 0 else second_step_sum_uniform_set, 0)
		rd.compute_list_set_push_constant(list, _scan_constants[i], 16)
		rd.compute_list_dispatch(list, hash_groups, 1, 1)
		rd.compute_list_add_barrier(list)
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	for mode in [2, 4, 5, 6]:
		data.encode_s32(0, mode)
		rd.compute_list_set_push_constant(list, data, data.size())
		rd.compute_list_dispatch(list, total_groups if mode == 2 else fluid_groups, 1, 1)
		rd.compute_list_add_barrier(list)
	rd.compute_list_end()

func get_buffer_uniform(binding, buffer) -> RDUniform:
	var unif := RDUniform.new()
	unif.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	unif.binding = binding
	unif.add_id(buffer)
	return unif

func set_multimesh_aabb():
	var mm = %MultiMeshInstance3D
	if is_instance_valid(mm.multimesh):
		var aabb = AABB(mm.global_position, Vector3(length, height, width))
		mm.multimesh.custom_aabb = aabb

func _release_gpu_resources():
	_boundary_local_buffer = RID()
	_boundary_metadata = RID()
	_boundary_pipeline = RID()
	_boundary_set = RID()
	_boundary_capacity = 0
	_boundary_cache_key.clear()
	_boundary_cached_surface = PackedVector3Array()
	for i in range(owned_rids.size()-1,-1,-1):
		var rid := owned_rids[i]
		if rid.is_valid():
			rd.free_rid(rid)
	owned_rids.clear()

func _exit_tree():
	_release_gpu_resources()

func rebuild_buffers():
	if not has_node("%MultiMeshInstance3D"):
		return
	
	_release_gpu_resources()
	var mm = MultiMesh.new()
	mm.use_colors = true
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = count
	var aabb = AABB(%MultiMeshInstance3D.global_position, Vector3(length, height, width))
	mm.custom_aabb = aabb
	for i in range(count):
		var t := Transform3D()
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color(0.08, 0.55, 1.0, 1.0))

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = 2 * radius
	sphere.radial_segments = 12
	sphere.rings = 6
	
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true 
	
	var outline_mat := StandardMaterial3D.new()
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED 
	outline_mat.albedo_color = Color.BLACK                        
	outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT            
	outline_mat.grow = true                                        
	outline_mat.grow_amount = radius * 0.07                       
	
	mat.next_pass = outline_mat
	
	sphere.material = mat
	mm.mesh = sphere
	
	%MultiMeshInstance3D.multimesh = mm
	
	
	var mm_rid = RenderingServer.multimesh_get_buffer_rd_rid(mm.get_rid())
	
	
	# load and begin compiling compute shader
	var shader_file :RDShaderFile= preload("res://modules/fluid/compute_shader.gd").load_file("res://modules/fluid/shaders/compute_fluid.glsl")
	var shader_spirv :RDShaderSPIRV= shader_file.get_spirv()
	var shader = rd.shader_create_from_spirv(shader_spirv)
	owned_rids.append(shader)
	pipeline = rd.compute_pipeline_create(shader)
	
	var pref_sum: RDShaderFile = preload("res://modules/fluid/compute_shader.gd").load_file("res://modules/fluid/shaders/pref_sum.glsl")
	var shader_pref_spirv: RDShaderSPIRV = pref_sum.get_spirv()
	var sum_shader = rd.shader_create_from_spirv(shader_pref_spirv)
	owned_rids.append(sum_shader)
	sum_pipeline = rd.compute_pipeline_create(sum_shader)
	#var arr: PackedInt32Array
	#for i in range(hash_oversizing * positions.size()):
		#arr.append(i)

	var capacity := count + maxi(boundary_count, 1)
	var hash_capacity: int = hash_oversizing * capacity
	_scan_constants.clear()
	var scan_stride := 1
	while scan_stride < hash_capacity * 2:
		_scan_constants.append(PackedInt32Array([scan_stride,0,0,0]).to_byte_array())
		scan_stride *= 2
	var pref_sum_hash_count_buffer = rd.storage_buffer_create(int_size * hash_capacity)
	owned_rids.append(pref_sum_hash_count_buffer)
	var pref_sum_hash_count_buffer2 = rd.storage_buffer_create(int_size * hash_capacity)
	owned_rids.append(pref_sum_hash_count_buffer2)
	
	var unif1 := get_buffer_uniform(0, pref_sum_hash_count_buffer)
	var unif2 := get_buffer_uniform(1, pref_sum_hash_count_buffer2)
	first_step_sum_uniform_set = rd.uniform_set_create([unif1, unif2], sum_shader, 0)
	
	unif1.binding = 1
	unif2.binding = 0
	second_step_sum_uniform_set = rd.uniform_set_create([unif1, unif2], sum_shader, 0)
	#print(positions)
	var data = positions.to_byte_array()
	var zero_data := PackedByteArray()
	zero_data.resize(data.size())
	var positions_buffer = rd.storage_buffer_create(data.size(), data)
	owned_rids.append(positions_buffer)
	diagnostic_positions = positions_buffer
	var predicated_positions_buffer = rd.storage_buffer_create(data.size(), zero_data)
	owned_rids.append(predicated_positions_buffer)
	var velocity_buffer = rd.storage_buffer_create(data.size(), zero_data)
	owned_rids.append(velocity_buffer)
	diagnostic_velocities = velocity_buffer
	var density_buffer = rd.storage_buffer_create(int_size * count)
	owned_rids.append(density_buffer)
	var hash_count_buffer = rd.storage_buffer_create(int_size * hash_capacity)
	owned_rids.append(hash_count_buffer)
	var hash_indexes_buffer = rd.storage_buffer_create(int_size * capacity)
	owned_rids.append(hash_indexes_buffer)
	var force_buffer = rd.storage_buffer_create(data.size(), zero_data)
	owned_rids.append(force_buffer)
	boundary_positions_buffer = rd.storage_buffer_create(maxi(16, boundary_count * 16))
	owned_rids.append(boundary_positions_buffer)
	boundary_velocities_buffer = rd.storage_buffer_create(maxi(16, boundary_count * 16))
	owned_rids.append(boundary_velocities_buffer)
	

	var sampler_state := RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	var sampler_rid : RID = rd.sampler_create(sampler_state)
	owned_rids.append(sampler_rid)
	
	var sdf_uniform := RDUniform.new()
	sdf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	sdf_uniform.binding = 11
	
	sdf_uniform.add_id(sampler_rid)
	var sdf_data := PackedFloat32Array([1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1, 0,0,0,0, 1,1,1,1])
	if use_collision_sdf:
		var relative: Transform3D = global_transform.affine_inverse() * sdf_node.global_transform
		var scales := relative.basis.get_scale().abs()
		assert(is_equal_approx(scales.x, scales.y) and is_equal_approx(scales.y, scales.z), "SDF node must have uniform scale; mesh scales may be arbitrary")
		var inverse := relative.affine_inverse()
		var grid := Vector3(sdf_node.texture.get_width(), sdf_node.texture.get_height(), sdf_node.texture.get_depth())
		# Godot rounds shorter axes down to whole cubic cells when baking.
		var cell: float = sdf_node.size[sdf_node.size.max_axis_index()] / grid[grid.max_axis_index()]
		var extent := grid * cell
		sdf_data = PackedFloat32Array([
			inverse.basis.x.x,inverse.basis.x.y,inverse.basis.x.z,0,
			inverse.basis.y.x,inverse.basis.y.y,inverse.basis.y.z,0,
			inverse.basis.z.x,inverse.basis.z.y,inverse.basis.z.z,0,
			inverse.origin.x,inverse.origin.y,inverse.origin.z,1,
			-sdf_node.size.x/2,-sdf_node.size.y/2,-sdf_node.size.z/2,0,
			extent.x,extent.y,extent.z,scales.x])
		sdf_uniform.add_id(RenderingServer.texture_get_rd_texture(sdf_node.texture.get_rid()))
	else:
		var empty_format := RDTextureFormat.new()
		empty_format.width = 1
		empty_format.height = 1
		empty_format.depth = 1
		empty_format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
		empty_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
		empty_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		var empty_data: Array[PackedByteArray] = [PackedFloat32Array([1.0]).to_byte_array()]
		var empty_texture := rd.texture_create(empty_format, RDTextureView.new(), empty_data)
		owned_rids.append(empty_texture)
		sdf_uniform.add_id(empty_texture)
	var sdf_metadata := rd.storage_buffer_create(sdf_data.size()*4, sdf_data.to_byte_array())
	owned_rids.append(sdf_metadata)
	var sdf_metadata_uniform := get_buffer_uniform(14, sdf_metadata)
	
	var positions_uniform = get_buffer_uniform(0, positions_buffer)
	var predicated_positions_uniform = get_buffer_uniform(1, predicated_positions_buffer)
	var velocity_uniform = get_buffer_uniform(2, velocity_buffer)
	var density_uniform = get_buffer_uniform(3, density_buffer)
	var hash_count_uniform  = get_buffer_uniform(4, hash_count_buffer)
	var pref_sum_hash_count_uniform = get_buffer_uniform(5, pref_sum_hash_count_buffer)
	var hash_indexes_uniform = get_buffer_uniform(6, hash_indexes_buffer)
	var pref_sum_hash_count_uniform2 = get_buffer_uniform(7, pref_sum_hash_count_buffer2)
	var force_buffer_uniform = get_buffer_uniform(9, force_buffer)
	var mm_uniform = get_buffer_uniform(10, mm_rid)
	var boundary_positions_uniform = get_buffer_uniform(12, boundary_positions_buffer)
	var boundary_velocities_uniform = get_buffer_uniform(13, boundary_velocities_buffer)

	
	boundary_bounds_buffer = rd.storage_buffer_create(32,PackedFloat32Array([0.,0.,0.,0.,0.,0.,0.,0.]).to_byte_array())
	owned_rids.append(boundary_bounds_buffer)
	neighbor_count_buffer = rd.storage_buffer_create(count * 4)
	bucket_bounds_buffer = rd.storage_buffer_create(hash_capacity * 32)
	owned_rids.append(bucket_bounds_buffer)
	neighbor_index_buffer = rd.storage_buffer_create(count * 128 * 4)
	owned_rids.append_array([neighbor_count_buffer, neighbor_index_buffer])
	compute_uniforms = [get_buffer_uniform(18,bucket_bounds_buffer),get_buffer_uniform(17,boundary_bounds_buffer),get_buffer_uniform(15,neighbor_count_buffer), get_buffer_uniform(16,neighbor_index_buffer),positions_uniform,
	predicated_positions_uniform, 
	velocity_uniform, 
	density_uniform, 
	hash_count_uniform, 
	pref_sum_hash_count_uniform, 
	hash_indexes_uniform, 
	pref_sum_hash_count_uniform2, 
	force_buffer_uniform,
	mm_uniform,
	sdf_uniform,
	boundary_positions_uniform,
	boundary_velocities_uniform,
	sdf_metadata_uniform,
	]
	uniform_set = rd.uniform_set_create(compute_uniforms, shader, 0)
	
	


var rebuild := rebuild_buffers
