class_name ForestTrees
extends RefCounted

## Authoritative individuals. Rendering only reads these arrays.
## One root cell / tree, coarse canopy competition; not a forestry prediction.
var land: ForestLandscape
var species := PackedInt32Array()
var positions := PackedVector3Array()
var yaw := PackedFloat64Array()
var size := PackedFloat64Array()
var age_years := PackedFloat64Array()
var stress := PackedFloat64Array()
var alive := PackedByteArray()
var root_cells := PackedInt32Array()
var light := PackedFloat64Array()
var last_supply := PackedFloat64Array()
var rng := RandomNumberGenerator.new()
var ticks := 0
var elapsed_s := 0.0
var water_elapsed_s := 0.0
var transpired_m3 := 0.0
var deaths := 0


func _init(l: ForestLandscape) -> void:
	land = l
	rng.seed = l.settings.seed
	var definitions := l.settings.plants
	var total_weight := 0.0
	for definition in definitions:
		total_weight += definition.weight
	for attempt in l.settings.tree_attempts:
		var choice := rng.randf() * total_weight
		var selected := definitions.size() - 1
		for s in definitions.size():
			choice -= definitions[s].weight
			if choice <= 0:
				selected = s
				break
		var definition: ForestPlantDefinition = definitions[selected]
		var x := rng.randf_range(12, l.settings.extent - 12)
		var z := rng.randf_range(12, l.settings.extent - 12)
		var distance := absf(x - l.channel_x(z))
		var clearing := (
			Vector2(x / l.settings.extent - .375, z / l.settings.extent - .557).length() < .06
		)
		if distance < definition.minimum_channel_distance or clearing:
			continue
		if distance < 36 and rng.randf() < .65:
			continue
		if l.noise.get_noise_2d(x * .7 + 300, z * .7) < -.24 and rng.randf() < .8:
			continue
		var initial_size := rng.randf_range(definition.scale_range.x, definition.scale_range.y)
		var angle := rng.randf() * TAU
		# Array index is a stable individual ID. Dead stems are retained, not erased.
		species.append(selected)
		positions.append(Vector3(x, l.height_at(x, z) - .1, z))
		yaw.append(angle)
		size.append(initial_size)
		age_years.append(8.0 + 32.0 * initial_size / definition.scale_range.y)
		stress.append(0)
		alive.append(1)
		var n := l.settings.water_resolution
		var dx := l.settings.extent / n
		root_cells.append(clampi(int(z / dx), 0, n - 1) * n + clampi(int(x / dx), 0, n - 1))
		light.append(1)
		last_supply.append(1)


func step(dt: float, water: ForestWatershed, water_dt := -1.0) -> void:
	assert(dt > 0)
	# Biology uses accelerated years; uptake uses actual hydrological SI seconds.
	if water_dt < 0:
		water_dt = dt
	var climate := ForestClimate.sample(
		elapsed_s + dt * .5, land.settings.start_day, land.settings.latitude_deg
	)
	var demand := PackedFloat64Array()
	demand.resize(water.resolution * water.resolution)
	var individual_demand := PackedFloat64Array()
	individual_demand.resize(species.size())
	_update_light()
	for i in species.size():
		if not alive[i]:
			continue
		var definition: ForestPlantDefinition = land.settings.plants[species[i]]
		var leaf := ForestClimate.leaves(definition, climate.day)
		var area := PI * pow(definition.crown_radius_m * size[i], 2)
		var volume: float = (
			definition.transpiration_m_s * area * leaf * climate.evaporation * water_dt
		)
		individual_demand[i] = volume
		demand[root_cells[i]] += volume / water.cell_area
	var supplied: PackedFloat64Array = water.native.withdraw_roots(demand)
	assert(supplied.size() == demand.size())
	for k in supplied.size():
		transpired_m3 += supplied[k] * water.cell_area
	# Surface snapshots are current at ecology boundaries; native owns withdrawal.
	for i in species.size():
		if not alive[i]:
			continue
		var definition: ForestPlantDefinition = land.settings.plants[species[i]]
		var cell := root_cells[i]
		var ratio := clampf(supplied[cell] / demand[cell], 0, 1) if demand[cell] > 0 else 1.0
		if water_dt == 0 and leaf_demand(definition, climate) > 0:
			ratio = last_supply[i]  # No water tick: don't invent recovery from a zero request.
		last_supply[i] = ratio
		var flood := clampf(water.depth[cell] / definition.flood_depth_m - 1.0, 0, 1)
		var target_stress := maxf(1.0 - ratio, flood)
		# Exact relaxation for a constant forcing; no dt-dependent stress increments.
		var days := (
			definition.stress_days if target_stress > stress[i] else definition.recovery_days
		)
		stress[i] = (
			target_stress + (stress[i] - target_stress) * exp(-dt / (days * ForestClimate.DAY_S))
		)
		age_years[i] += dt / ForestClimate.YEAR_S
		if stress[i] >= definition.lethal_stress or age_years[i] >= definition.lifespan_years:
			alive[i] = 0
			deaths += 1
			continue
		var growth: float = climate.growth * ForestClimate.leaves(definition, climate.day)
		growth *= (
			ratio
			* (1.0 - stress[i])
			* clampf((light[i] - definition.minimum_light) / (1.0 - definition.minimum_light), 0, 1)
		)
		var ceiling := definition.max_height_m / definition.reference_height_m
		size[i] = minf(
			ceiling,
			(
				size[i]
				+ (
					definition.height_growth_m_year
					/ definition.reference_height_m
					* growth
					* dt
					/ ForestClimate.YEAR_S
					* maxf(0, 1 - size[i] / ceiling)
				)
			)
		)
	elapsed_s += dt
	water_elapsed_s += water_dt
	ticks += 1
	water.sync_fields()


func leaf_demand(definition: ForestPlantDefinition, climate: Dictionary) -> float:
	return (
		definition.transpiration_m_s
		* ForestClimate.leaves(definition, climate.day)
		* climate.evaporation
	)


func _update_light() -> void:
	# Coarse 16 m canopy columns; taller crowns shade shorter ones.
	# Columns are independent: don't globally sort thousands of unrelated crowns.
	var columns := {}
	var heights := PackedFloat64Array()
	heights.resize(species.size())
	for i in species.size():
		heights[i] = _height(i)
		var cell := Vector2i(int(positions[i].x / 16), int(positions[i].z / 16))
		if not columns.has(cell):
			columns[cell] = []
		columns[cell].append(i)
	for column in columns.values():
		column.sort_custom(func(a: int, b: int): return heights[a] > heights[b])
		var cover := 0.0
		for i in column:
			light[i] = exp(-cover)
			if alive[i]:
				var definition: ForestPlantDefinition = land.settings.plants[species[i]]
				cover += PI * pow(definition.crown_radius_m * size[i], 2) / 256.0


func _height(i: int) -> float:
	return size[i] * land.settings.plants[species[i]].reference_height_m


func snapshot() -> Dictionary:
	return {
		"version": 2,
		"configuration": _configuration(),
		"species": species.duplicate(),
		"positions": positions.duplicate(),
		"yaw": yaw.duplicate(),
		"size": size.duplicate(),
		"age_years": age_years.duplicate(),
		"stress": stress.duplicate(),
		"alive": alive.duplicate(),
		"root_cells": root_cells.duplicate(),
		"last_supply": last_supply.duplicate(),
		"ticks": ticks,
		"elapsed_s": elapsed_s,
		"water_elapsed_s": water_elapsed_s,
		"transpired_m3": transpired_m3,
		"deaths": deaths,
		"rng_state": rng.state
	}


func _configuration() -> Dictionary:
	var definitions: Array[Dictionary] = []
	for definition in land.settings.plants:
		var traits := {}
		for name in [
			"species_id",
			"deciduous",
			"leaf_on_day",
			"leaf_off_day",
			"leaf_transition_days",
			"reference_height_m",
			"max_height_m",
			"crown_radius_m",
			"height_growth_m_year",
			"transpiration_m_s",
			"minimum_light",
			"flood_depth_m",
			"stress_days",
			"recovery_days",
			"lethal_stress",
			"lifespan_years"
		]:
			traits[name] = definition.get(name)
		definitions.append(traits)
	return {
		"start_day": land.settings.start_day,
		"latitude": land.settings.latitude_deg,
		"year_speed_multiplier": land.settings.year_speed_multiplier,
		"traits": definitions
	}


# gdlint: disable=max-returns
func restore(state: Dictionary) -> bool:
	# Validate completely before mutation. Species/config belongs to the same world.
	if state.get("version", 0) != 2 or state.get("configuration", {}) != _configuration():
		return false
	for field in [
		"species",
		"positions",
		"yaw",
		"size",
		"age_years",
		"stress",
		"alive",
		"root_cells",
		"last_supply"
	]:
		if not state.has(field) or typeof(state[field]) != typeof(get(field)):
			return false
		if state[field].size() != species.size():
			return false
	if state.species != species or state.positions != positions or state.root_cells != root_cells:
		return false
	for i in species.size():
		for value in [
			state.yaw[i], state.size[i], state.age_years[i], state.stress[i], state.last_supply[i]
		]:
			if not is_finite(value) or value < 0:
				return false
		if (
			state.size[i] <= 0
			or state.stress[i] > 1
			or state.last_supply[i] > 1
			or state.alive[i] > 1
		):
			return false
	for field in ["ticks", "elapsed_s", "water_elapsed_s", "transpired_m3", "deaths", "rng_state"]:
		if not state.has(field):
			return false
	for value in [
		state.ticks, state.elapsed_s, state.water_elapsed_s, state.transpired_m3, state.deaths
	]:
		if not is_finite(value) or value < 0:
			return false
	yaw = state.yaw.duplicate()
	size = state.size.duplicate()
	age_years = state.age_years.duplicate()
	stress = state.stress.duplicate()
	alive = state.alive.duplicate()
	last_supply = state.last_supply.duplicate()
	ticks = state.ticks
	elapsed_s = state.elapsed_s
	water_elapsed_s = state.water_elapsed_s
	transpired_m3 = state.transpired_m3
	deaths = state.deaths
	rng.state = state.rng_state
	return true
