class_name ForestWatershed
extends RefCounted

## Native local-inertial surface flow + two-layer bucket soil, all in SI.
## Public arrays are read-only snapshots, never the authoritative reserves.
var source_indices := PackedInt32Array()
var source_flow_m3_s := PackedFloat64Array()  # Per-cell external input, m³/s.
var config: ForestSettings
var resolution: int
var cell_size: float
var cell_area: float
var landscape: ForestLandscape
var bed := PackedFloat64Array()
var depth := PackedFloat64Array()
var soil := PackedFloat64Array()
var flux_x := PackedFloat64Array()
var flux_z := PackedFloat64Array()
var top_water_m := PackedFloat64Array()
var root_water_m := PackedFloat64Array()
var pending_water_m := PackedFloat64Array()
var ground_water_m := PackedFloat64Array()
var seepage_m_s := PackedFloat64Array()
var native = ClassDB.instantiate(&"ForestHydroNative")
var stats := {}
var raining := false
var inflow := 0.0
var outflow := 0.0
var infiltrated := 0.0
var evaporated := 0.0
var deep_drain := 0.0
var soil_volume := 0.0
var initial_volume := 0.0
var clock := 0.0
var barriers: Array[ForestBarrier] = []
var crest_x := PackedFloat64Array()
var crest_z := PackedFloat64Array()


func _init(land: ForestLandscape) -> void:
	landscape = land
	config = land.settings
	resolution = land.settings.water_resolution
	cell_size = land.settings.extent / resolution
	cell_area = cell_size * cell_size
	# Packed arrays are copy-on-write; allocate each explicitly.
	bed.resize(resolution * resolution)
	depth.resize(resolution * resolution)
	soil.resize(resolution * resolution)
	source_flow_m3_s.resize(resolution * resolution)
	for j in resolution:
		for i in resolution:
			var k := j * resolution + i
			var x := (i + 0.5) * cell_size
			var z := (j + 0.5) * cell_size
			bed[k] = landscape.height_at(x, z)
			if (
				z < config.headwater_length
				and absf(x - landscape.channel_x(z)) < config.headwater_width / 2
			):
				source_indices.append(k)
			var d := absf(x - landscape.channel_x(z))
			depth[k] = (
				maxf(0.0, 0.65 - (bed[k] - landscape.height_at(landscape.channel_x(z), z)))
				if d < 10.0
				else 0.0
			)
			depth[k] = maxf(depth[k], landscape.initial_spring_depth(x, z))
			soil[k] = 0.4 + 0.4 * exp(-d / 22.0)
	assert(
		not source_indices.is_empty(),
		"Grid misses headwater source; refine resolution or widen source"
	)
	for k in source_indices:
		source_flow_m3_s[k] = config.headwater_m3_s / source_indices.size()
	if config.spring_enabled:
		var spring := landscape.spring_position()
		var k := index_at(spring.x, spring.y)
		source_flow_m3_s[k] += config.spring_flow_m3_s
		if not source_indices.has(k):
			source_indices.append(k)
	var weights := PackedFloat64Array()
	var source_total := 0.0
	for k in source_indices:
		weights.append(source_flow_m3_s[k])
		source_total += source_flow_m3_s[k]
	assert(native != null, "Build native hydrology with tools/build_hydro.sh")
	var profile := config.soil_profile
	var options := {
		"max_step_s": config.water_step,
		"cfl": config.water_cfl,
		"manning_n": config.manning_n,
		"theta": config.water_theta,
		"max_froude": config.max_froude,
		"rain_m_s": config.rainfall_m_s,
		"source_m3_s": source_total,
		"source_weights": weights,
		"soil_interval_s": config.soil_interval_s,
		"top_m": profile.top_depth_m,
		"root_m": profile.root_depth_m,
		"porosity": profile.porosity,
		"field_theta": profile.field_capacity_theta,
		"residual_theta": profile.residual_theta,
		"conductivity_m_s": profile.saturated_conductivity_m_s,
		"root_conductivity_m_s": profile.root_conductivity_m_s,
		"evaporation_m_s": config.evaporation_m_s
	}
	options.merge(
		{
			"groundwater": profile.groundwater_enabled,
			"aquifer_m": profile.aquifer_depth_m,
			"specific_yield": profile.specific_yield,
			"lateral_k_m_s": profile.lateral_conductivity_m_s,
			"initial_groundwater_fraction": profile.initial_groundwater_fraction
		}
	)
	var ok: bool = native.configure(
		resolution, cell_size, options, bed, depth, soil, source_indices, _initial_groundwater()
	)
	assert(ok, "Invalid native hydrology inputs")
	_rebuild_crests()
	sync_fields()


func _initial_groundwater() -> PackedFloat64Array:
	var values := PackedFloat64Array()
	values.resize(depth.size())
	var profile := config.soil_profile
	if profile.groundwater_enabled:
		for k in depth.size():
			# Initial persistent stream is connected to a saturated shallow store.
			# This is a declared scenario initial condition, not water created later.
			var fraction := 1.0 if depth[k] > 0 else profile.initial_groundwater_fraction
			values[k] = profile.aquifer_depth_m * profile.specific_yield * fraction
	return values


func volume() -> float:
	return native.metrics().surface_m3


func balance_error() -> float:
	return native.metrics().balance_error_m3


func volume_in(bounds: Rect2) -> float:
	# Explicit readback for a diagnostic; never a per-cell extension call.
	sync_fields()
	var total := 0.0
	for j in resolution:
		for i in resolution:
			if bounds.has_point(Vector2((i + .5) * cell_size, (j + .5) * cell_size)):
				total += depth[j * resolution + i] * cell_area
	return total


func set_barrier(barrier: ForestBarrier, enabled: bool) -> void:
	# Replacing/removing by identity also permits moving an existing obstacle.
	for i in range(barriers.size() - 1, -1, -1):
		if barriers[i].barrier_id == barrier.barrier_id:
			barriers.remove_at(i)
	if enabled:
		assert(barrier.start.distance_to(barrier.end) > 0)
		barriers.append(barrier)
	_rebuild_crests()


func _rebuild_crests() -> void:
	crest_x.resize(resolution * resolution)
	crest_z.resize(resolution * resolution)
	for j in resolution:
		for i in resolution:
			var k := j * resolution + i
			var point := Vector2((i + .5) * cell_size, (j + .5) * cell_size)
			if i < resolution - 1:
				crest_x[k] = maxf(bed[k], bed[k + 1])
				for barrier in barriers:
					if (
						Geometry2D.segment_intersects_segment(
							point, point + Vector2(cell_size, 0), barrier.start, barrier.end
						)
						!= null
					):
						crest_x[k] = maxf(crest_x[k], barrier.crest)
			if j < resolution - 1:
				crest_z[k] = maxf(bed[k], bed[k + resolution])
				for barrier in barriers:
					if (
						Geometry2D.segment_intersects_segment(
							point, point + Vector2(0, cell_size), barrier.start, barrier.end
						)
						!= null
					):
						crest_z[k] = maxf(crest_z[k], barrier.crest)
	var ok: bool = native.set_crests(crest_x, crest_z)
	assert(ok)


func step(
	dt: float, copy_fields := true, liquid_m_s := -1.0, liquid_field := PackedFloat64Array()
) -> void:
	var ok: bool
	if not liquid_field.is_empty():
		ok = native.advance_field(dt, liquid_field)
	else:
		ok = (
			native.advance(dt, raining) if liquid_m_s < 0 else native.advance_forced(dt, liquid_m_s)
		)
	assert(ok, "Native hydrology advance failed")
	clock += dt
	if copy_fields:
		sync_fields()


func sync_fields() -> void:
	var fields: Dictionary = native.fields()
	depth = fields.depth
	soil = fields.soil  # Derived saturation of the combined soil profile, not theta.
	top_water_m = fields.top_water_m
	root_water_m = fields.root_water_m
	pending_water_m = fields.pending_water_m
	ground_water_m = fields.ground_water_m
	seepage_m_s = fields.seepage_m_s
	flux_x = fields.qx
	flux_z = fields.qz
	stats = native.metrics()
	clock = stats.time_s
	inflow = stats.input_m3
	outflow = stats.outlet_m3
	infiltrated = stats.infiltrated_m3  # Internal transfer; NEVER an external sink.
	evaporated = stats.evaporated_m3
	deep_drain = stats.deep_drain_m3
	soil_volume = stats.soil_m3
	initial_volume = stats.initial_m3  # Surface + both layers + pending reserve.


func save_state(path: String) -> Error:
	var interventions: Array[Dictionary] = []
	for barrier in barriers:
		interventions.append(
			{
				"id": barrier.barrier_id,
				"start": barrier.start,
				"end": barrier.end,
				"crest": barrier.crest
			}
		)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(
		{
			"version": 1,
			"native": native.snapshot(),
			"raining": raining,
			"barriers": interventions,
			"land_seed": config.seed,
			"extent_m": config.extent
		}
	)
	file.flush()
	return file.get_error()


func load_state(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var state: Variant = file.get_var()
	if (
		not state is Dictionary
		or state.get("version") != 1
		or state.get("land_seed") != config.seed
		or state.get("extent_m") != config.extent
		or not state.get("barriers") is Array
		or not state.get("raining") is bool
	):
		return false
	var saved: Dictionary = state.get("native", {})
	var current: Dictionary = native.snapshot()
	if (
		saved.get("n") != resolution
		or saved.get("dx") != cell_size
		or saved.get("options") != current.options
		or saved.get("bed") != current.bed
		or saved.get("sources") != current.sources
		or saved.get("source_weights") != current.source_weights
	):
		return false
	var restored_barriers: Array[ForestBarrier] = []
	for entry in state.barriers:
		if (
			not entry is Dictionary
			or not entry.get("start") is Vector2
			or not entry.get("end") is Vector2
			or not entry.get("crest") is float
			or not entry.has("id")
		):
			return false
		var barrier := ForestBarrier.new()
		barrier.barrier_id = entry.id
		barrier.start = entry.start
		barrier.end = entry.end
		barrier.crest = entry.crest
		restored_barriers.append(barrier)
	if not native.restore(saved):
		return false
	barriers = restored_barriers
	bed = saved.bed
	crest_x = saved.crest_x
	crest_z = saved.crest_z
	raining = state.raining
	sync_fields()
	return true


func index_at(x: float, z: float) -> int:
	return (
		clampi(int(z / cell_size), 0, resolution - 1) * resolution
		+ clampi(int(x / cell_size), 0, resolution - 1)
	)
