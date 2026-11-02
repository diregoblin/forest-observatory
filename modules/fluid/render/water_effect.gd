extends CompositorEffect

# Screen-space visualization only. Borrows the simulation's actual position RID.
# No CPU particle readback, no alternate solver, no particle-count reduction.
var simulation: Node3D
var milky := false
var liquid_tint := Color(.08,.42,.58,0.)
# Visualization budget only; the solver retains all particles and its fixed dt.
var low_cost := OS.get_environment("FLUID_RENDER_QUALITY") == "low"
var profile_gpu := OS.get_environment("FLUID_GPU_STAGES") == "1"
var state_mutex := Mutex.new()
var simulation_state := {}
var failed := false
var rendered_frames := 0
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sampler: RID
var metadata: RID
var field_buffer: RID
var surface_a: RID
var surface_b: RID
var background: RID
var target_size := Vector2i.ZERO
var surface_size := Vector2i.ZERO
var target_divisor := 0
var owned: Array[RID] = []
var targets: Array[RID] = []
var shader_file: RDShaderFile = preload("res://modules/fluid/compute_shader.gd").load_file("res://modules/fluid/render/water.glsl")

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true

## Main-thread snapshot: render callbacks never read a live Node3D transform.
func capture_simulation_state() -> void:
	if not is_instance_valid(simulation): return
	var state := {"positions":simulation.diagnostic_positions,
		"transform":simulation.global_transform,"count":simulation.count,
		"radius":simulation.derived.spacing*.64,"milky":milky,"low_cost":low_cost,"tint":liquid_tint}
	state_mutex.lock()
	simulation_state = state
	state_mutex.unlock()

func _buffer_uniform(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u

func _image_uniform(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u

func _sample_uniform(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(sampler)
	u.add_id(rid)
	return u

func _texture(size: Vector2i, format: int) -> RID:
	var f := RDTextureFormat.new()
	f.width = size.x
	f.height = size.y
	f.format = format
	f.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var rid := rd.texture_create(f, RDTextureView.new())
	targets.append(rid)
	return rid

func _setup(size: Vector2i, divisor: int) -> bool:
	if not shader.is_valid():
		var spv := shader_file.get_spirv()
		if not spv.compile_error_compute.is_empty():
			push_error("Water shader: " + spv.compile_error_compute)
			failed = true
			return false
		shader = rd.shader_create_from_spirv(spv)
		pipeline = rd.compute_pipeline_create(shader)
		var state := RDSamplerState.new()
		state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler = rd.sampler_create(state)
		metadata = rd.storage_buffer_create(304)
		owned.assign([pipeline, shader, sampler, metadata])
	if size != target_size or divisor != target_divisor:
		for rid in targets:
			if rid.is_valid(): rd.free_rid(rid)
		targets.clear()
		target_size = size
		target_divisor = divisor
		var half_size := Vector2i(ceili(float(size.x)/divisor),ceili(float(size.y)/divisor))
		surface_size = half_size
		field_buffer = rd.storage_buffer_create(half_size.x * half_size.y * 8)
		targets.append(field_buffer)
		surface_a = _texture(half_size, RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
		surface_b = _texture(half_size, RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
		background = _texture(Vector2i.ONE if divisor == 4 else size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	return true

func _matrix(data: PackedFloat32Array, p: Projection) -> void:
	for c in [p.x, p.y, p.z, p.w]:
		data.append_array(PackedFloat32Array([c.x, c.y, c.z, c.w]))

func _render_callback(_type: int, render_data: RenderData) -> void:
	if failed: return
	state_mutex.lock()
	var state := simulation_state.duplicate()
	state_mutex.unlock()
	if state.is_empty(): return
	rd = RenderingServer.get_rendering_device()
	if rd == null or not state.positions.is_valid(): return
	var buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var size := buffers.get_internal_size()
	var divisor := 4 if state.low_cost else 2
	if size.x < 1 or size.y < 1 or not _setup(size,divisor): return
	if profile_gpu: rd.capture_timestamp("fluid/water/begin")
	var scene_data: RenderSceneDataRD = render_data.get_render_scene_data()
	var projection := scene_data.get_cam_projection()
	var data := PackedFloat32Array()
	_matrix(data, Projection(state.transform))
	_matrix(data, Projection(scene_data.get_cam_transform().affine_inverse()))
	_matrix(data, projection)
	_matrix(data, projection.inverse())
	var half_size := surface_size
	var tint: Color = Color(.92,.9,.86,1.) if state.milky else state.tint
	data.append_array(PackedFloat32Array([size.x, size.y, half_size.x, half_size.y,
		state.count, state.radius, 1. if state.low_cost else 0., 2. if state.low_cost else 3., tint.r, tint.g, tint.b, tint.a]))
	var bytes := data.to_byte_array()
	rd.buffer_update(metadata, 0, bytes.size(), bytes)
	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		var uniforms: Array[RDUniform] = [_buffer_uniform(0, state.positions), _buffer_uniform(1, field_buffer), _buffer_uniform(2, metadata), _image_uniform(3, surface_a), _image_uniform(4, color), _sample_uniform(5, depth), _sample_uniform(6, background), _sample_uniform(7, surface_b), _image_uniform(8, background)]
		var set_rid := UniformSetCacheRD.get_cache(shader, 0, uniforms)
		for mode in ([0,1,2,3] if state.low_cost else [4,0,1,2,3]):
			if mode == 3:
				rd.texture_copy(surface_a, surface_b, Vector3.ZERO, Vector3.ZERO, Vector3(half_size.x, half_size.y, 1), 0, 0, 0, 0)
			var list := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(list, pipeline)
			rd.compute_list_bind_uniform_set(list, set_rid, 0)
			rd.compute_list_set_push_constant(list, PackedInt32Array([mode,0,0,0]).to_byte_array(), 16)
			var items: int = state.count if mode == 1 else (size.x * size.y if mode == 3 or mode == 4 else half_size.x * half_size.y)
			rd.compute_list_dispatch(list, ceili(items / 64.0), 1, 1)
			rd.compute_list_end()
	if profile_gpu: rd.capture_timestamp("fluid/water/end")
	rendered_frames += 1

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		var device := rd
		var resources := targets.duplicate()
		resources.append_array(owned)
		RenderingServer.call_on_render_thread(func():
			for rid in resources:
				if rid.is_valid(): device.free_rid(rid))
