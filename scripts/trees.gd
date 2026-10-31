class_name ForestTrees
extends RefCounted

## One authoritative array model for trees, shrubs and herbaceous patches.
## IDs are append-only array indices; views never own biomass or advance age.
## Size is derived allometry: species size=1 carbon * size³ (scenario, not fitted).
const MAX_INDIVIDUALS := 24000
var land: ForestLandscape
var soil: ForestSoil
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
var last_nutrient := PackedFloat64Array()
var biomass_c := PackedFloat64Array()
var biomass_n := PackedFloat64Array()
var biomass_p := PackedFloat64Array()
var dead_c := PackedFloat64Array()
var dead_n := PackedFloat64Array()
var dead_p := PackedFloat64Array()
var seed_c := PackedFloat64Array()
var seed_n := PackedFloat64Array()
var seed_p := PackedFloat64Array()
var rng := RandomNumberGenerator.new()
var ticks := 0
var elapsed_s := 0.0
var water_elapsed_s := 0.0
var transpired_m3 := 0.0
var deaths := 0
var recruits := 0
var photosynthesized_kg_c := 0.0
var exported_kg_c := 0.0
var exported_kg_n := 0.0
var exported_kg_p := 0.0
var litter_kg_c := 0.0
var litter_kg_n := 0.0
var litter_kg_p := 0.0
var soil_uptake_n_kg := 0.0
var soil_uptake_p_kg := 0.0
var implicit_nutrient_n_kg := 0.0
var implicit_nutrient_p_kg := 0.0
var initial_c := 0.0
var initial_n := 0.0
var initial_p := 0.0
var revision := 0
var _column_cover := {}
var _initial_count := 0


func _init(l: ForestLandscape, shared_soil: ForestSoil = null) -> void:
	land = l
	soil = shared_soil
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
		# Clearing retains low vegetation; this is a growth-form rule, not a species ID.
		if (
			distance < definition.minimum_channel_distance
			or (clearing and definition.growth_form == &"tree")
		):
			continue
		if distance < 36 and rng.randf() < .65:
			continue
		if l.noise.get_noise_2d(x * .7 + 300, z * .7) < -.24 and rng.randf() < .8:
			continue
		var initial_size := rng.randf_range(definition.scale_range.x, definition.scale_range.y)
		var initial_age := rng.randf_range(
			definition.initial_age_years.x, definition.initial_age_years.y
		)
		_append(selected, Vector3(x, l.height_at(x, z) - .1, z), initial_size, initial_age)
	_initial_count = species.size()
	var totals := _totals()
	initial_c = totals[0]
	initial_n = totals[1]
	initial_p = totals[2]


func _append(which: int, position: Vector3, scale: float, age: float, carbon := -1.0) -> int:
	var definition: ForestPlantDefinition = land.settings.plants[which]
	species.append(which)
	positions.append(position)
	yaw.append(rng.randf() * TAU)
	size.append(scale)
	age_years.append(age)
	stress.append(0)
	alive.append(1)
	var n := land.settings.water_resolution
	var dx := land.settings.extent / n
	root_cells.append(
		clampi(int(position.z / dx), 0, n - 1) * n + clampi(int(position.x / dx), 0, n - 1)
	)
	light.append(1)
	last_supply.append(1)
	last_nutrient.append(1)
	var c := definition.biomass_kg_c * pow(scale, 3) if carbon < 0 else carbon
	biomass_c.append(c)
	biomass_n.append(c / definition.cn_ratio)
	biomass_p.append(c / definition.cp_ratio)
	dead_c.append(0)
	dead_n.append(0)
	dead_p.append(0)
	seed_c.append(0)
	seed_n.append(0)
	seed_p.append(0)
	return species.size() - 1


func step(dt: float, water: ForestWatershed, water_dt := -1.0) -> void:
	assert(dt > 0)
	if water_dt < 0:
		water_dt = dt
	var climate := ForestClimate.sample(
		elapsed_s + dt * .5, land.settings.start_day, land.settings.latitude_deg
	)
	_decay_dead(dt, climate, water)
	var count := species.size()  # New recruits participate beginning next fixed tick.
	var demand := PackedFloat64Array()
	demand.resize(water.resolution * water.resolution)
	_update_light()
	for i in count:
		if alive[i]:
			var d: ForestPlantDefinition = land.settings.plants[species[i]]
			var area := PI * pow(d.crown_radius_m * size[i], 2)
			demand[root_cells[i]] += leaf_demand(d, climate) * area * water_dt / water.cell_area
	var supplied: PackedFloat64Array = water.native.withdraw_roots(demand)
	assert(supplied.size() == demand.size())
	for value in supplied:
		transpired_m3 += value * water.cell_area
	var growth_c := PackedFloat64Array()
	var nutrient_n := PackedFloat64Array()
	var nutrient_p := PackedFloat64Array()
	growth_c.resize(count)
	nutrient_n.resize(count)
	nutrient_p.resize(count)
	for i in count:
		if not alive[i]:
			continue
		var d: ForestPlantDefinition = land.settings.plants[species[i]]
		var cell := root_cells[i]
		var ratio := clampf(supplied[cell] / demand[cell], 0, 1) if demand[cell] > 0 else 1.0
		if water_dt == 0 and leaf_demand(d, climate) > 0:
			ratio = last_supply[i]
		last_supply[i] = ratio
		var flood := clampf(water.depth[cell] / d.flood_depth_m - 1.0, 0, 1)
		var target_stress := maxf(1.0 - ratio, flood)
		var days := d.stress_days if target_stress > stress[i] else d.recovery_days
		stress[i] = (
			target_stress + (stress[i] - target_stress) * exp(-dt / (days * ForestClimate.DAY_S))
		)
		age_years[i] += dt / ForestClimate.YEAR_S
		var lifespan := minf(
			d.lifespan_years,
			(
				1.0
				if d.life_cycle == &"annual"
				else (2.0 if d.life_cycle == &"biennial" else d.lifespan_years)
			)
		)
		if (
			stress[i] >= d.lethal_stress
			or age_years[i] >= lifespan
			or _annual_season_finished(d, dt)
		):
			_die(i)
			continue
		var growth: float = climate.growth * ForestClimate.leaves(d, climate.day)
		growth *= (
			ratio
			* (1.0 - stress[i])
			* clampf((light[i] - d.minimum_light) / (1.0 - d.minimum_light), 0, 1)
		)
		var ceiling := d.max_height_m / d.reference_height_m
		var next_size := minf(
			ceiling,
			(
				size[i]
				+ (
					d.height_growth_m_year
					/ d.reference_height_m
					* growth
					* dt
					/ ForestClimate.YEAR_S
					* maxf(0, 1 - size[i] / ceiling)
				)
			)
		)
		growth_c[i] = maxf(0, d.biomass_kg_c * pow(next_size, 3) - biomass_c[i])
		nutrient_n[i] = growth_c[i] / d.cn_ratio
		nutrient_p[i] = growth_c[i] / d.cp_ratio
	# All plant species in the same cell request together. Sorting identities does
	# not give an early species first access to mineral N/P.
	var uptake := {"nitrogen": nutrient_n, "phosphorus": nutrient_p}
	if soil != null:
		uptake = soil.withdraw_nutrients(positions, nutrient_n, nutrient_p)
	for i in count:
		if not alive[i]:
			continue
		var d: ForestPlantDefinition = land.settings.plants[species[i]]
		var n: float = uptake.nitrogen[i]
		var p: float = uptake.phosphorus[i]
		var gained := minf(growth_c[i], minf(n * d.cn_ratio, p * d.cp_ratio))
		var used_n := gained / d.cn_ratio
		var used_p := gained / d.cp_ratio
		if soil != null:
			soil.deposit_elements(positions[i], 0, maxf(0, n - used_n), maxf(0, p - used_p), false)
		else:
			implicit_nutrient_n_kg += used_n
			implicit_nutrient_p_kg += used_p
		soil_uptake_n_kg += used_n
		soil_uptake_p_kg += used_p
		biomass_c[i] += gained
		biomass_n[i] += used_n
		biomass_p[i] += used_p
		photosynthesized_kg_c += gained
		last_nutrient[i] = gained / growth_c[i] if growth_c[i] > 0 else 1.0
		var before_size := size[i]
		size[i] = pow(maxf(0, biomass_c[i] / d.biomass_kg_c), 1.0 / 3)
		if growth_c[i] == 0:
			size[i] = before_size  # Exact no-growth/null behavior and unchanged view.
		if age_years[i] >= d.mature_age_years and climate.growth > 0 and last_supply[i] > 0:
			var fraction := (
				(1.0 - exp(-d.reproduction_per_year * climate.growth * dt / ForestClimate.YEAR_S))
				* .08
			)
			var c := biomass_c[i] * fraction
			biomass_c[i] -= c
			biomass_n[i] -= c / d.cn_ratio
			biomass_p[i] -= c / d.cp_ratio
			seed_c[i] += c
			seed_n[i] += c / d.cn_ratio
			seed_p[i] += c / d.cp_ratio
			if c > 0:
				size[i] = pow(biomass_c[i] / d.biomass_kg_c, 1.0 / 3)
	_recruit(dt, climate, water, count)
	elapsed_s += dt
	water_elapsed_s += water_dt
	ticks += 1
	revision += 1
	water.sync_fields()


func _annual_season_finished(definition: ForestPlantDefinition, dt: float) -> bool:
	if definition.life_cycle != &"annual":
		return false
	var start := land.settings.start_day + elapsed_s / ForestClimate.DAY_S
	var finish := start + dt / ForestClimate.DAY_S
	var day := fposmod(start - 1.0, 365.0) + 1.0
	var season_end := definition.leaf_off_day + definition.leaf_transition_days
	# Phenological boundary shared by every annual species, including a tick
	# crossing year-end: a young autumn plant cannot survive merely because
	# its numerical age is still below one year.
	return (
		day < definition.leaf_on_day
		or day >= season_end
		or floor((finish - season_end) / 365.0) > floor((start - season_end) / 365.0)
	)


func _die(i: int) -> void:
	alive[i] = 0
	deaths += 1
	dead_c[i] += biomass_c[i]
	dead_n[i] += biomass_n[i]
	dead_p[i] += biomass_p[i]
	biomass_c[i] = 0
	biomass_n[i] = 0
	biomass_p[i] = 0


func _decay_dead(dt: float, climate: Dictionary, water: ForestWatershed) -> void:
	for i in species.size():
		if dead_c[i] <= 0:
			continue
		var d: ForestPlantDefinition = land.settings.plants[species[i]]
		var moisture := clampf((water.soil[root_cells[i]] - .1) / .5, 0, 1)
		var temperature := clampf((float(climate.temperature_c) + 2) / 20, 0, 1.5)
		var fraction := (
			1.0 - exp(-d.dead_decay_per_year * moisture * temperature * dt / ForestClimate.YEAR_S)
		)
		var c := dead_c[i] * fraction
		var n := dead_n[i] * fraction
		var p := dead_p[i] * fraction
		dead_c[i] -= c
		dead_n[i] -= n
		dead_p[i] -= p
		_litter(i, c, n, p)
		if not alive[i]:
			size[i] = pow(maxf(0, dead_c[i] / d.biomass_kg_c), 1.0 / 3)


func _litter(i: int, c: float, n: float, p: float) -> void:
	if soil != null:
		soil.deposit_elements(positions[i], c, n, p)
	litter_kg_c += c
	litter_kg_n += n
	litter_kg_p += p


func _recruit(dt: float, climate: Dictionary, water: ForestWatershed, count: int) -> void:
	var occupancy := {}
	for i in count:
		if alive[i]:
			var key := Vector2i(int(positions[i].x / 2), int(positions[i].z / 2))
			occupancy[key] = true
	for i in count:
		var d: ForestPlantDefinition = land.settings.plants[species[i]]
		var decayed := seed_c[i] * (1.0 - exp(-.5 * dt / ForestClimate.YEAR_S))
		seed_c[i] -= decayed
		seed_n[i] -= decayed / d.cn_ratio
		seed_p[i] -= decayed / d.cp_ratio
		_litter(i, decayed, decayed / d.cn_ratio, decayed / d.cp_ratio)
		if (
			d.life_cycle == &"annual"
			and (climate.day < d.leaf_on_day or climate.day >= d.leaf_off_day)
		):
			continue  # Annual seed bank, not living winter plants.
		if climate.growth <= 0 or seed_c[i] < d.seed_cost_kg_c or species.size() >= MAX_INDIVIDUALS:
			continue
		# One candidate event per mother/tick; probability is derived from a
		# finite seed budget. Failed establishment leaves the seeds in the bank.
		var chance := minf(
			1,
			(
				seed_c[i]
				/ d.seed_cost_kg_c
				* d.germination_fraction
				* climate.growth
				* dt
				/ ForestClimate.YEAR_S
			)
		)
		if rng.randf() >= chance:
			continue
		var angle := rng.randf() * TAU
		var distance := sqrt(rng.randf()) * d.dispersal_m
		var x := positions[i].x + cos(angle) * distance
		var z := positions[i].z + sin(angle) * distance
		if x < 1 or z < 1 or x >= land.settings.extent - 1 or z >= land.settings.extent - 1:
			continue
		var key := Vector2i(int(x / 2), int(z / 2))
		if occupancy.has(key) or absf(x - land.channel_x(z)) < d.minimum_channel_distance:
			continue
		var dx := water.cell_size
		var cell := (
			clampi(int(z / dx), 0, water.resolution - 1) * water.resolution
			+ clampi(int(x / dx), 0, water.resolution - 1)
		)
		if water.depth[cell] > d.flood_depth_m or water.soil[cell] < .2:
			continue
		var received_light := _light_at(x, z)
		if received_light < d.recruitment_light:
			continue
		var c := d.seed_cost_kg_c
		seed_c[i] -= c
		seed_n[i] -= c / d.cn_ratio
		seed_p[i] -= c / d.cp_ratio
		var scale := pow(c / d.biomass_kg_c, 1.0 / 3)
		_append(species[i], Vector3(x, land.height_at(x, z) - .1, z), scale, 0, c)
		occupancy[key] = true
		recruits += 1


func _light_at(x: float, z: float) -> float:
	return exp(-float(_column_cover.get(Vector2i(int(x / 16), int(z / 16)), 0.0)))


func leaf_demand(definition: ForestPlantDefinition, climate: Dictionary) -> float:
	return (
		definition.transpiration_m_s
		* ForestClimate.leaves(definition, climate.day)
		* climate.evaporation
	)


func _update_light() -> void:
	_column_cover.clear()
	var columns := {}
	var heights := PackedFloat64Array()
	heights.resize(species.size())
	for i in species.size():
		heights[i] = _height(i)
		var cell := Vector2i(int(positions[i].x / 16), int(positions[i].z / 16))
		if not columns.has(cell):
			columns[cell] = []
		columns[cell].append(i)
	for key in columns:
		var column: Array = columns[key]
		column.sort_custom(func(a: int, b: int): return heights[a] > heights[b])
		var cover := 0.0
		for i in column:
			light[i] = exp(-cover)
			if alive[i]:
				var d: ForestPlantDefinition = land.settings.plants[species[i]]
				cover += PI * pow(d.crown_radius_m * size[i], 2) / 256.0
		_column_cover[key] = cover


func _height(i: int) -> float:
	return size[i] * land.settings.plants[species[i]].reference_height_m


func harvest(id: int, requested_carbon_kg: float) -> Vector3:
	if (
		id < 0
		or id >= species.size()
		or not alive[id]
		or not is_finite(requested_carbon_kg)
		or requested_carbon_kg <= 0
	):
		return Vector3.ZERO
	var d: ForestPlantDefinition = land.settings.plants[species[id]]
	var c := minf(requested_carbon_kg, biomass_c[id] * d.edible_fraction)
	if c <= 0:
		return Vector3.ZERO
	# Quantize ONCE at the existing animal command boundary; subtract exactly
	# those returned quantities rather than a different hidden float64 meal.
	var meal := Vector3(c, c / d.cn_ratio, c / d.cp_ratio)
	if meal.x > biomass_c[id] or meal.y > biomass_n[id] or meal.z > biomass_p[id]:
		meal *= .9999998
	biomass_c[id] -= meal.x
	biomass_n[id] -= meal.y
	biomass_p[id] -= meal.z
	exported_kg_c += meal.x
	exported_kg_n += meal.y
	exported_kg_p += meal.z
	size[id] = pow(maxf(0, biomass_c[id] / d.biomass_kg_c), 1.0 / 3)
	if biomass_c[id] <= 1e-12:
		_die(id)
	revision += 1
	return meal


func inspect(id: int) -> Dictionary:
	if id < 0 or id >= species.size():
		return {}
	var d: ForestPlantDefinition = land.settings.plants[species[id]]
	var stage := "молодое" if age_years[id] < d.mature_age_years else "взрослое"
	if (
		d.life_cycle == &"annual"
		and alive[id]
		and age_years[id] >= d.mature_age_years
		and seed_c[id] > 0
	):
		stage = "семенная стадия"
	if not alive[id]:
		stage = (
			"сухое растение · семенной банк"
			if d.life_cycle == &"annual" and seed_c[id] > 0
			else "погибло"
		)
	return {
		"id": id,
		"title": d.display_name,
		"subtitle":
		(
			"%s · %s · %s"
			% [
				d.latin_name,
				(
					{
						&"tree": "дерево",
						&"shrub": "кустарник",
						&"dwarf_shrub": "кустарничек",
						&"herb": "трава",
						&"grass": "злак"
					}
					. get(d.growth_form, d.growth_form)
				),
				(
					{&"annual": "однолетнее", &"biennial": "двулетнее", &"perennial": "многолетнее"}
					. get(d.life_cycle, d.life_cycle)
				)
			]
		),
		"description": d.description,
		"species_id": d.species_id,
		"growth_form": d.growth_form,
		"life_cycle": d.life_cycle,
		"age_years": age_years[id],
		"initial_age": id < _initial_count,
		"stage": stage,
		"position": positions[id],
		"alive": bool(alive[id]),
		"carbon_kg": biomass_c[id] + dead_c[id],
		"nitrogen_kg": biomass_n[id] + dead_n[id],
		"phosphorus_kg": biomass_p[id] + dead_p[id],
		"dead_carbon_kg": dead_c[id],
		"seed_carbon_kg": seed_c[id],
		"height_m": _height(id),
		"stress": stress[id],
		"light": light[id],
		"water_supply": last_supply[id],
		"nutrient_supply": last_nutrient[id],
		"source_url": d.source_url,
		"details":
		{
			"Запасы":
			(
				"C %.3f кг · N %.4f кг · P %.5f кг"
				% [
					biomass_c[id] + dead_c[id],
					biomass_n[id] + dead_n[id],
					biomass_p[id] + dead_p[id]
				]
			),
			"Условия":
			(
				"Свет %.0f%% · вода %.0f%% · питание %.0f%%"
				% [light[id] * 100, last_supply[id] * 100, last_nutrient[id] * 100]
			),
			"Возраст":
			"с прорастания" if id >= species.size() - recruits else "задан при инициализации"
		}
	}


func _totals() -> PackedFloat64Array:
	var totals := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in species.size():
		totals[0] += biomass_c[i] + dead_c[i] + seed_c[i]
		totals[1] += biomass_n[i] + dead_n[i] + seed_n[i]
		totals[2] += biomass_p[i] + dead_p[i] + seed_p[i]
	return totals


func element_totals() -> Vector3:
	var t := _totals()
	return Vector3(t[0], t[1], t[2])


func carbon_total_kg() -> float:
	return _totals()[0]


func metrics() -> Dictionary:
	var t := _totals()
	return {
		"carbon_kg": t[0],
		"nitrogen_kg": t[1],
		"phosphorus_kg": t[2],
		"photosynthesized_kg_c": photosynthesized_kg_c,
		"exported_kg_c": exported_kg_c,
		"exported_kg_n": exported_kg_n,
		"exported_kg_p": exported_kg_p,
		"litter_kg_c": litter_kg_c,
		"litter_kg_n": litter_kg_n,
		"litter_kg_p": litter_kg_p,
		"recruits": recruits,
		"deaths": deaths,
		"soil_uptake_n_kg": soil_uptake_n_kg,
		"soil_uptake_p_kg": soil_uptake_p_kg,
		"dead_carbon_kg": _sum(dead_c),
		"dead_nitrogen_kg": _sum(dead_n),
		"dead_phosphorus_kg": _sum(dead_p),
		"seed_carbon_kg": _sum(seed_c),
		"live_carbon_kg": _sum(biomass_c),
		"carbon_error_kg": t[0] + exported_kg_c + litter_kg_c - initial_c - photosynthesized_kg_c,
		"nitrogen_error_kg": t[1] + exported_kg_n + litter_kg_n - initial_n - soil_uptake_n_kg,
		"phosphorus_error_kg": t[2] + exported_kg_p + litter_kg_p - initial_p - soil_uptake_p_kg
	}


func _sum(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values:
		result += value
	return result


func snapshot() -> Dictionary:
	var result := {"version": 3, "configuration": _configuration(), "rng_state": rng.state}
	for field in _array_fields():
		result[field] = get(field).duplicate()
	for field in _scalar_fields():
		result[field] = get(field)
	return result


func _array_fields() -> Array:
	return [
		"species",
		"positions",
		"yaw",
		"size",
		"age_years",
		"stress",
		"alive",
		"root_cells",
		"last_supply",
		"last_nutrient",
		"biomass_c",
		"biomass_n",
		"biomass_p",
		"dead_c",
		"dead_n",
		"dead_p",
		"seed_c",
		"seed_n",
		"seed_p"
	]


func _scalar_fields() -> Array:
	return [
		"ticks",
		"elapsed_s",
		"water_elapsed_s",
		"transpired_m3",
		"deaths",
		"recruits",
		"photosynthesized_kg_c",
		"exported_kg_c",
		"exported_kg_n",
		"exported_kg_p",
		"litter_kg_c",
		"litter_kg_n",
		"litter_kg_p",
		"soil_uptake_n_kg",
		"soil_uptake_p_kg",
		"implicit_nutrient_n_kg",
		"implicit_nutrient_p_kg",
		"initial_c",
		"initial_n",
		"initial_p"
	]


func _configuration() -> Dictionary:
	var definitions: Array[Dictionary] = []
	for d in land.settings.plants:
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
			"lifespan_years",
			"growth_form",
			"life_cycle",
			"initial_age_years",
			"biomass_kg_c",
			"cn_ratio",
			"cp_ratio",
			"edible_fraction",
			"mature_age_years",
			"seed_cost_kg_c",
			"reproduction_per_year",
			"dispersal_m",
			"germination_fraction",
			"recruitment_light",
			"dead_decay_per_year",
			"weight",
			"scale_range",
			"minimum_channel_distance"
		]:
			traits[name] = d.get(name)
		definitions.append(traits)
	return {
		"seed": land.settings.seed,
		"extent": land.settings.extent,
		"initial_population": _initial_count,
		"start_day": land.settings.start_day,
		"latitude": land.settings.latitude_deg,
		"year_speed_multiplier": land.settings.year_speed_multiplier,
		"shared_soil": soil != null,
		"traits": definitions
	}


# Full validation precedes mutation; saved recruits may extend initial arrays.
# gdlint: disable=max-returns
func restore(state: Dictionary) -> bool:
	if state.get("version", 0) != 3 or state.get("configuration", {}) != _configuration():
		return false
	if not state.get("species") is PackedInt32Array:
		return false
	var count: int = state.species.size()
	if count < _initial_count or count > MAX_INDIVIDUALS:
		return false
	for field in _array_fields():
		if (
			not state.has(field)
			or typeof(state[field]) != typeof(get(field))
			or state[field].size() != count
		):
			return false
	for i in count:
		if (
			state.species[i] < 0
			or state.species[i] >= land.settings.plants.size()
			or not state.positions[i].is_finite()
		):
			return false
		var pos: Vector3 = state.positions[i]
		var dx := land.settings.extent / land.settings.water_resolution
		var cell := int(pos.z / dx) * land.settings.water_resolution + int(pos.x / dx)
		if (
			pos.x < 0
			or pos.z < 0
			or pos.x >= land.settings.extent
			or pos.z >= land.settings.extent
			or state.root_cells[i] != cell
		):
			return false
		for field in [
			"yaw",
			"size",
			"age_years",
			"stress",
			"last_supply",
			"last_nutrient",
			"biomass_c",
			"biomass_n",
			"biomass_p",
			"dead_c",
			"dead_n",
			"dead_p",
			"seed_c",
			"seed_n",
			"seed_p"
		]:
			if not is_finite(state[field][i]) or state[field][i] < 0:
				return false
		if (
			state.stress[i] > 1
			or state.last_supply[i] > 1
			or state.last_nutrient[i] > 1
			or state.alive[i] > 1
			or (state.alive[i] and state.size[i] <= 0)
		):
			return false
	for field in _scalar_fields():
		if not state.has(field) or not is_finite(state[field]) or state[field] < 0:
			return false
	for field in ["ticks", "deaths", "recruits", "rng_state"]:
		if not state.get(field) is int:
			return false
	if count != _initial_count + state.recruits:
		return false
	if state.deaths != state.alive.count(0):
		return false
	var totals := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in count:
		totals[0] += state.biomass_c[i] + state.dead_c[i] + state.seed_c[i]
		totals[1] += state.biomass_n[i] + state.dead_n[i] + state.seed_n[i]
		totals[2] += state.biomass_p[i] + state.dead_p[i] + state.seed_p[i]
		if (
			not state.alive[i]
			and (state.biomass_c[i] != 0 or state.biomass_n[i] != 0 or state.biomass_p[i] != 0)
		):
			return false
	var errors := PackedFloat64Array(
		[
			(
				totals[0]
				+ state.exported_kg_c
				+ state.litter_kg_c
				- state.initial_c
				- state.photosynthesized_kg_c
			),
			(
				totals[1]
				+ state.exported_kg_n
				+ state.litter_kg_n
				- state.initial_n
				- state.soil_uptake_n_kg
			),
			(
				totals[2]
				+ state.exported_kg_p
				+ state.litter_kg_p
				- state.initial_p
				- state.soil_uptake_p_kg
			)
		]
	)
	for element in 3:
		if absf(errors[element]) > 1e-7 * maxf(1.0, totals[element]):
			return false
	for field in _array_fields():
		set(field, state[field].duplicate())
	for field in _scalar_fields():
		set(field, state[field])
	rng.state = state.rng_state
	light.resize(count)
	_update_light()
	revision += 1
	return true
