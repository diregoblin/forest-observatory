class_name ForestWatershed
extends RefCounted

# Conservative reservoir exchange, NOT Landlab/shallow-water hydrodynamics.
# Lengths in scene metres; model time is intentionally accelerated, uncalibrated.
var source_indices := PackedInt32Array()
var config: ForestSettings
var resolution: int
var cell_size: float
var cell_area: float
var landscape: ForestLandscape
var bed := PackedFloat64Array()
var depth := PackedFloat64Array()
var soil := PackedFloat64Array()
var delta := PackedFloat64Array()
var outgoing := PackedFloat64Array()
var flux_x := PackedFloat64Array()
var flux_z := PackedFloat64Array()
var raining := false
var inflow := 0.0
var outflow := 0.0
var infiltrated := 0.0
var evaporated := 0.0
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
	delta.resize(resolution * resolution)
	outgoing.resize(resolution * resolution)
	flux_x.resize(resolution * resolution)
	flux_z.resize(resolution * resolution)
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
			soil[k] = 0.4 + 0.4 * exp(-d / 22.0)
	assert(
		not source_indices.is_empty(),
		"Grid misses headwater source; refine resolution or widen source"
	)
	_rebuild_crests()
	initial_volume = volume()


func volume() -> float:
	var total := 0.0
	for h in depth:
		total += h * cell_area
	return total


func balance_error() -> float:
	return volume() + outflow + infiltrated + evaporated - initial_volume - inflow


func volume_in(bounds: Rect2) -> float:
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


func step(dt: float) -> void:
	clock += dt
	delta.fill(0.0)
	outgoing.fill(0.0)
	flux_x.fill(0.0)
	flux_z.fill(0.0)
	# Source volume is independent of the number/area of source cells.
	var spring_volume := config.headwater_flow * dt
	for k in source_indices:
		depth[k] += spring_volume / (float(source_indices.size()) * cell_area)
	inflow += spring_volume
	var rain := config.rainfall_intensity * dt if raining else 0.0
	inflow += rain * cell_area * float(resolution * resolution)
	for k in resolution * resolution:
		depth[k] += rain
		var soak := minf(depth[k], config.infiltration_rate * dt * (1.0 - soil[k]))
		depth[k] -= soak
		infiltrated += soak * cell_area
		soil[k] = clampf(soil[k] + soak * 2.0 - config.soil_drying_rate * dt, 0, 1)
	# Compute signed face transfers, then limit the SUM of donor outflows.
	for j in resolution:
		for i in resolution:
			var a := j * resolution + i
			if i < resolution - 1:
				flux_x[a] = _transfer(a, a + 1, crest_x[a], dt)
				outgoing[a if flux_x[a] > 0 else a + 1] += absf(flux_x[a])
			if j < resolution - 1:
				flux_z[a] = _transfer(a, a + resolution, crest_z[a], dt)
				outgoing[a if flux_z[a] > 0 else a + resolution] += absf(flux_z[a])
	for j in resolution:
		for i in resolution:
			var a := j * resolution + i
			if i < resolution - 1:
				_apply_flux(a, a + 1, flux_x[a])
			if j < resolution - 1:
				_apply_flux(a, a + resolution, flux_z[a])
	for k in resolution * resolution:
		depth[k] += delta[k]
		var evap := minf(depth[k], config.evaporation_rate * dt)
		depth[k] -= evap
		evaporated += evap * cell_area
	for i in resolution:
		var k := (resolution - 1) * resolution + i
		var drain := depth[k] * minf(config.outlet_rate * dt, config.donor_fraction)
		depth[k] -= drain
		outflow += drain * cell_area


func _transfer(a: int, b: int, crest: float, dt: float) -> float:
	var sa := bed[a] + depth[a]
	var sb := bed[b] + depth[b]
	if sa > sb:
		return config.exchange_rate * dt * maxf(0.0, sa - maxf(sb, crest))
	return -config.exchange_rate * dt * maxf(0.0, sb - maxf(sa, crest))


func _apply_flux(a: int, b: int, raw: float) -> void:
	var donor := a if raw > 0 else b
	var f := raw * minf(1.0, depth[donor] * config.donor_fraction / maxf(outgoing[donor], 1e-20))
	delta[a] -= f
	delta[b] += f


func index_at(x: float, z: float) -> int:
	return (
		clampi(int(z / cell_size), 0, resolution - 1) * resolution
		+ clampi(int(x / cell_size), 0, resolution - 1)
	)
