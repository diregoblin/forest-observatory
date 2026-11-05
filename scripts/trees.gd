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
var leaf_carbon := PackedFloat64Array()
var fallen := PackedByteArray()
var fallen_age_s := PackedFloat64Array()
var fruit_c := PackedFloat64Array()  # Subset of seed_c, not another stock.
var reserved_seed_c := PackedFloat64Array()  # Subset of seed_c held by carriers.
var _habitat_ref: WeakRef
var habitat: RefCounted:
	get:
		return _habitat_ref.get_ref() if _habitat_ref != null else null
	set(value):
		_habitat_ref = weakref(value) if value != null else null
var mycorrhiza: ForestFungi
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
	for attempt in l.settings.tree_attempts:
		var x := rng.randf_range(12, l.settings.extent - 12)
		var z := rng.randf_range(12, l.settings.extent - 12)
		var site := l.habitat_at(x, z)
		if rng.randf() > 1.0 - .92 * site.w:
			continue
		var weights := PackedFloat64Array()
		var tree_weight := 0.0
		for d in definitions:
			var weight: float = d.weight * d.initial_habitat_weights.dot(site)
			if d.growth_form == &"tree":
				weight *= smoothstep(.5, .9, site.x) + site.w * .02
			if absf(x - l.channel_x(z)) < d.minimum_channel_distance:
				weight = 0.0
			weights.append(weight)
			if d.growth_form == &"tree":
				tree_weight += weight
		var stand_choice := l.stand_at(x, z) * tree_weight
		var dominant := -1
		for which in definitions.size():
			if definitions[which].growth_form != &"tree" or weights[which] <= 0:
				continue
			stand_choice -= weights[which]
			if stand_choice <= 0:
				dominant = which
				break
		# Preserve the forest placement probability, but distribute trees as a
		# locally dominant species plus a real mixture, not nearly pure stands.
		var dominant_weight := weights[dominant] if dominant >= 0 else 0.0
		var stand_weight := dominant_weight * 5.0 + (tree_weight - dominant_weight) * .06
		var admixture := tree_weight - dominant_weight
		var total_weight := 0.0
		for which in weights.size():
			if definitions[which].growth_form == &"tree":
				if which == dominant:
					weights[which] = stand_weight * (.65 if admixture > 0 else 1.0)
				else:
					weights[which] = (
						stand_weight * .35 * weights[which] / admixture if admixture > 0 else 0.0
					)
			total_weight += weights[which]
		if total_weight <= 0:
			continue
		var choice := rng.randf() * total_weight
		var selected := -1
		for which in weights.size():
			choice -= weights[which]
			if choice < 0:
				selected = which
				break
		if selected < 0:
			continue
		var definition: ForestPlantDefinition = definitions[selected]
		var initial_size := rng.randf_range(definition.scale_range.x, definition.scale_range.y)
		var initial_age := rng.randf_range(
			definition.initial_age_years.x, definition.initial_age_years.y
		)
		_append(selected, Vector3(x, l.height_at(x, z) - .1, z), initial_size, initial_age)
	# Additional finite herb/grass patches on open sites, using the existing
	# placement budget, not a second unaccounted grass or food reservoir.
	for attempt in mini(l.settings.grass_attempts, l.settings.tree_attempts * 3):
		var x := rng.randf_range(12, l.settings.extent - 12)
		var z := rng.randf_range(12, l.settings.extent - 12)
		var site := l.habitat_at(x, z)
		if rng.randf() > site.y * .75 + site.z:
			continue
		var weights := PackedFloat64Array()
		var total_weight := 0.0
		for d in definitions:
			var weight: float = d.weight * d.initial_habitat_weights.dot(site)
			if (
				d.growth_form not in [&"herb", &"grass"]
				or absf(x - l.channel_x(z)) < d.minimum_channel_distance
			):
				weight = 0
			weights.append(weight)
			total_weight += weight
		if total_weight <= 0 or species.size() >= MAX_INDIVIDUALS:
			continue
		var choice := rng.randf() * total_weight
		for which in weights.size():
			choice -= weights[which]
			if choice < 0:
				var d: ForestPlantDefinition = definitions[which]
				_append(
					which,
					Vector3(x, l.height_at(x, z) - .1, z),
					rng.randf_range(d.scale_range.x, d.scale_range.y),
					rng.randf_range(d.initial_age_years.x, d.initial_age_years.y)
				)
				break
	_seed_initial_deadwood()
	_initial_count = species.size()
	var totals := _totals()
	initial_c = totals[0]
	initial_n = totals[1]
	initial_p = totals[2]


func _seed_initial_deadwood() -> void:
	# Reclassify existing tree stocks, never add decorative/free wood. Separate
	# RNG preserves placement and the subsequent simulation's random stream.
	if land.settings.initial_fallen_fraction <= 0:
		return
	var candidates := PackedInt32Array()
	for i in species.size():
		if land.settings.plants[species[i]].growth_form == &"tree":
			candidates.append(i)
	var count := roundi(candidates.size() * land.settings.initial_fallen_fraction)
	var placement_rng := RandomNumberGenerator.new()
	placement_rng.seed = land.settings.seed + 73019
	# Partial Fisher-Yates: no duplicate choices or repeated linear searches.
	for slot in count:
		var pick := placement_rng.randi_range(slot, candidates.size() - 1)
		var id := candidates[pick]
		candidates[pick] = candidates[slot]
		candidates[slot] = id
		_die(id)
		fallen[id] = 1
		# Existing independent yaw gives varied orientations across each stand.
		# Fallen age starts at zero; no fictitious historical decay is booked.


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
	fallen.append(0)
	fallen_age_s.append(0)
	fruit_c.append(0)
	reserved_seed_c.append(0)
	seed_c.append(0)
	seed_n.append(0)
	seed_p.append(0)
	leaf_carbon.append(
		(
			c
			* definition.leaf_mass_fraction
			* ForestClimate.leaves(definition, land.settings.start_day)
		)
	)
	return species.size() - 1


var step_profile_usec := {}
var _light_kernel := ForestPlantLightNative.new()
var use_native_light := true  # Reference switch for checks, not a different model.


func step(dt: float, water: ForestWatershed, water_dt := -1.0, forcing: Dictionary = {}) -> void:
	assert(dt > 0)
	if water_dt < 0:
		water_dt = dt
	var climate := ForestClimate.sample(
		elapsed_s + dt * .5, land.settings.start_day, land.settings.latitude_deg
	)
	if not forcing.is_empty():
		climate = forcing
	var local_fields := ForestWeatherFront.grid(climate, land.settings.extent)
	var local_evaporation := PackedFloat64Array()
	var local_growth := PackedFloat64Array()
	for point in positions:
		var p := Vector2(point.x, point.z)
		local_evaporation.append(
			ForestWeatherFront.value(local_fields.evaporation, p, land.settings.extent)
		)
		local_growth.append(ForestWeatherFront.value(local_fields.growth, p, land.settings.extent))
	var profile := {}
	var mark := Time.get_ticks_usec()
	_windfall(dt, climate, water_dt)
	profile.windfall = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	_leaf_turnover(dt)
	profile.leaf_turnover = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	# Species-wide phenology/kinetics are identical for every individual this tick.
	var leaves := PackedFloat64Array()
	var seasonal_death := PackedByteArray()
	var reproduction := PackedFloat64Array()
	for definition in land.settings.plants:
		leaves.append(ForestClimate.leaves(definition, climate.day))
		seasonal_death.append(1 if _annual_season_finished(definition, dt) else 0)
		reproduction.append(
			(
				(
					1.0
					- exp(
						(
							-definition.reproduction_per_year
							* climate.growth
							* dt
							/ ForestClimate.YEAR_S
						)
					)
				)
				* .08
			)
		)
	_decay_dead(dt, climate, water)
	profile.phenology_dead = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	var count := species.size()  # New recruits participate beginning next fixed tick.
	var demand := PackedFloat64Array()
	demand.resize(water.resolution * water.resolution)
	profile.allocation = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	_update_light()
	profile.light = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	for i in count:
		if alive[i]:
			var d: ForestPlantDefinition = land.settings.plants[species[i]]
			var area := PI * pow(d.crown_radius_m * size[i], 2)
			demand[root_cells[i]] += (
				d.transpiration_m_s
				* leaves[species[i]]
				* local_evaporation[i]
				* area
				* water_dt
				/ water.cell_area
			)
	var supplied: PackedFloat64Array = water.native.withdraw_roots(demand)
	assert(supplied.size() == demand.size())
	for value in supplied:
		transpired_m3 += value * water.cell_area
	profile.transpiration = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
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
		if water_dt == 0 and d.transpiration_m_s * leaves[species[i]] * local_evaporation[i] > 0:
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
		if stress[i] >= d.lethal_stress or age_years[i] >= lifespan or seasonal_death[species[i]]:
			_die(i)
			continue
		var growth: float = local_growth[i] * leaves[species[i]]
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
	profile.growth_requests = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	# All plant species in the same cell request together. Sorting identities does
	# not give an early species first access to mineral N/P.
	var uptake := {"nitrogen": nutrient_n, "phosphorus": nutrient_p}
	if soil != null:
		uptake = soil.withdraw_nutrients(positions, nutrient_n, nutrient_p)
	profile.nutrient_uptake = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	for i in count:
		if not alive[i]:
			continue
		var d: ForestPlantDefinition = land.settings.plants[species[i]]
		var n: float = uptake.nitrogen[i]
		var p: float = uptake.phosphorus[i]
		if (
			mycorrhiza != null
			and d.mycorrhiza_type == &"ecto"
			and (n < nutrient_n[i] or p < nutrient_p[i])
		):
			var exchange := mycorrhiza.trade(
				positions[i],
				maxf(0, nutrient_n[i] - n),
				maxf(0, nutrient_p[i] - p),
				minf(biomass_c[i] * .001, growth_c[i] * .2)
			)
			biomass_c[i] -= exchange[0]
			exported_kg_c += exchange[0]
			n += exchange[1]
			p += exchange[2]
		var gained := minf(growth_c[i], minf(n * d.cn_ratio, p * d.cp_ratio))
		var used_n := gained / d.cn_ratio
		var used_p := gained / d.cp_ratio
		if soil != null and (n > used_n or p > used_p):
			soil.deposit_elements(positions[i], 0, maxf(0, n - used_n), maxf(0, p - used_p), false)
		elif soil == null:
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
			var fraction := reproduction[species[i]]
			if d.fruit_bearing:
				var flowering := flower_fraction(d, climate.day)
				var pollination: float = (
					habitat.pollination_at(positions[i])
					if habitat != null and d.insect_pollinated
					else 1.0
				)
				fraction *= flowering * pollination
			var c := biomass_c[i] * fraction
			biomass_c[i] -= c
			biomass_n[i] -= c / d.cn_ratio
			biomass_p[i] -= c / d.cp_ratio
			seed_c[i] += c
			seed_n[i] += c / d.cn_ratio
			seed_p[i] += c / d.cp_ratio
			if c > 0:
				size[i] = pow(biomass_c[i] / d.biomass_kg_c, 1.0 / 3)
		leaf_carbon[i] = minf(leaf_carbon[i], biomass_c[i])
	for i in count:
		var d: ForestPlantDefinition = land.settings.plants[species[i]]
		var ripe := (
			d.fruit_bearing
			and fposmod(climate.day - d.fruit_start_day, 365) < d.fruit_duration_days
		)
		fruit_c[i] = maxf(0, seed_c[i] - reserved_seed_c[i]) if ripe and alive[i] else 0.0
	profile.assimilation = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	_recruit(dt, climate, water, count)
	elapsed_s += dt
	water_elapsed_s += water_dt
	ticks += 1
	revision += 1
	water.sync_fields()

	profile.recruit_finish = Time.get_ticks_usec() - mark
	step_profile_usec = profile


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
	leaf_carbon[i] = 0


func _leaf_turnover(dt: float) -> void:
	var removed := PackedFloat64Array()
	var retained := PackedFloat64Array()
	for d in land.settings.plants:
		var previous := ForestClimate.leaves(
			d, ForestClimate.sample(elapsed_s, land.settings.start_day).day
		)
		var current := ForestClimate.leaves(
			d, ForestClimate.sample(elapsed_s + dt, land.settings.start_day).day
		)
		removed.append(maxf(0, 1 - current / previous) if d.deciduous and previous > 0 else 0)
		retained.append(current)
	for i in species.size():
		if not alive[i]:
			continue
		var d: ForestPlantDefinition = land.settings.plants[species[i]]
		var c := minf(biomass_c[i], leaf_carbon[i] * removed[species[i]])
		if c > 0:
			biomass_c[i] -= c
			biomass_n[i] -= c / d.cn_ratio
			biomass_p[i] -= c / d.cp_ratio
			leaf_carbon[i] -= c
			# Fall is distributed beneath the actual crown, not a global seasonal tint.
			for offset in [
				Vector3.ZERO, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK
			]:
				if soil != null:
					var landing: Vector3 = positions[i] + offset * d.crown_radius_m * size[i] * .6
					landing.x = clampf(landing.x, 0, land.settings.extent - .001)
					landing.z = clampf(landing.z, 0, land.settings.extent - .001)
					soil.deposit_elements(landing, c / 5, c / d.cn_ratio / 5, c / d.cp_ratio / 5)
			litter_kg_c += c
			litter_kg_n += c / d.cn_ratio
			litter_kg_p += c / d.cp_ratio
			size[i] = pow(maxf(0, biomass_c[i] / d.biomass_kg_c), 1.0 / 3)
		else:
			# Allocation within existing live biomass; never photosynthesis from nothing.
			leaf_carbon[i] = minf(
				biomass_c[i],
				maxf(leaf_carbon[i], biomass_c[i] * d.leaf_mass_fraction * retained[species[i]])
			)


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
	if c == 0 and n == 0 and p == 0:
		return
	if soil != null:
		# A fallen trunk returns wood along its actual footprint, not just the stump.
		var end := positions[i]
		if fallen[i]:
			var length := _height(i) * .8
			end += Vector3(cos(yaw[i]), 0, sin(yaw[i])) * length
			end.x = clampf(end.x, .01, land.settings.extent - .01)
			end.z = clampf(end.z, .01, land.settings.extent - .01)
		for j in 3:
			soil.deposit_elements(positions[i].lerp(end, j / 2.0), c / 3, n / 3, p / 3)
	litter_kg_c += c
	litter_kg_n += n
	litter_kg_p += p


func trample(id: int, pressure: float) -> void:
	# Flattening returns actual living tissue to fresh litter, never another stock.
	if id < 0 or id >= species.size() or not alive[id] or pressure <= 0:
		return
	var d: ForestPlantDefinition = land.settings.plants[species[id]]
	if d.growth_form == &"tree" or _height(id) > 1.2:
		return
	var fraction := minf(.25, pressure * (1 - d.trampling_resistance) * .35)
	var c := biomass_c[id] * fraction
	var n := biomass_n[id] * fraction
	var p := biomass_p[id] * fraction
	biomass_c[id] -= c
	biomass_n[id] -= n
	biomass_p[id] -= p
	leaf_carbon[id] *= 1 - fraction
	size[id] = pow(maxf(0, biomass_c[id] / d.biomass_kg_c), 1.0 / 3)
	_litter(id, c, n, p)
	revision += 1


func _seed_candidate(id: int, d: ForestPlantDefinition, logs: PackedInt32Array) -> Vector3:
	# Bias a dispersal candidate, never teleport seeds beyond the species radius.
	if d.nurse_log_affinity > 0 and rng.randf() < d.nurse_log_affinity:
		var candidates := PackedVector3Array()
		for log_id in logs:
			var start := positions[log_id]
			var end := start + Vector3(cos(yaw[log_id]), 0, sin(yaw[log_id])) * _height(log_id)
			var anchor := Geometry3D.get_closest_point_to_segment(positions[id], start, end)
			if (
				Vector2(anchor.x - positions[id].x, anchor.z - positions[id].z).length()
				<= maxf(0, d.dispersal_m - 1.5)
			):
				candidates.append(anchor)
		if not candidates.is_empty():
			var point := candidates[rng.randi_range(0, candidates.size() - 1)]
			var angle := rng.randf() * TAU
			return point + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(.4, 1.4)
	var angle := rng.randf() * TAU
	var distance := sqrt(rng.randf()) * d.dispersal_m
	return positions[id] + Vector3(cos(angle), 0, sin(angle)) * distance


func _recruit(dt: float, climate: Dictionary, water: ForestWatershed, count: int) -> void:
	var occupancy := {}
	var logs := PackedInt32Array()
	for i in count:
		if fallen[i] and dead_c[i] > .01:
			logs.append(i)
	for i in count:
		if alive[i]:
			var key := Vector2i(int(positions[i].x / 2), int(positions[i].z / 2))
			occupancy[key] = true
	for i in count:
		var d: ForestPlantDefinition = land.settings.plants[species[i]]
		var decayed := (
			maxf(0, seed_c[i] - reserved_seed_c[i]) * (1.0 - exp(-.5 * dt / ForestClimate.YEAR_S))
		)
		seed_c[i] -= decayed
		seed_n[i] -= decayed / d.cn_ratio
		seed_p[i] -= decayed / d.cp_ratio
		_litter(i, decayed, decayed / d.cn_ratio, decayed / d.cp_ratio)
		if (
			d.life_cycle == &"annual"
			and (climate.day < d.leaf_on_day or climate.day >= d.leaf_off_day)
		):
			continue  # Annual seed bank, not living winter plants.
		if (
			climate.growth <= 0
			or seed_c[i] - reserved_seed_c[i] < d.seed_cost_kg_c
			or species.size() >= MAX_INDIVIDUALS
		):
			continue
		# One candidate event per mother/tick; probability is derived from a
		# finite seed budget. Failed establishment leaves the seeds in the bank.
		var chance := minf(
			1,
			(
				(seed_c[i] - reserved_seed_c[i])
				/ d.seed_cost_kg_c
				* d.germination_fraction
				* climate.growth
				* dt
				/ ForestClimate.YEAR_S
			)
		)
		if rng.randf() >= chance:
			continue
		var candidate := _seed_candidate(i, d, logs)
		var x := candidate.x
		var z := candidate.z
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
	for i in count:
		fruit_c[i] = minf(fruit_c[i], maxf(0, seed_c[i] - reserved_seed_c[i]))


func _light_at(x: float, z: float) -> float:
	return exp(-float(_column_cover.get(Vector2i(int(x / 16), int(z / 16)), 0.0)))


func leaf_demand(definition: ForestPlantDefinition, climate: Dictionary) -> float:
	return (
		definition.transpiration_m_s
		* ForestClimate.leaves(definition, climate.day)
		* climate.evaporation
	)


func _update_light() -> void:
	if not use_native_light:
		_update_light_reference()
		return
	var heights := PackedFloat64Array()
	var crowns := PackedFloat64Array()
	for d in land.settings.plants:
		heights.append(d.reference_height_m)
		crowns.append(d.crown_radius_m)
	var result := _light_kernel.compute(species, positions, size, alive, heights, crowns)
	assert(not result.is_empty())
	light = result.light
	_column_cover = result.columns


func _update_light_reference() -> void:
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
	leaf_carbon[id] = minf(leaf_carbon[id], biomass_c[id])
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
		"fallen": bool(fallen[id]),
		"fruit_carbon_kg": fruit_c[id],
		"seed_carbon_kg": seed_c[id],
		"propagule_kind": d.propagule_kind,
		"height_m": _height(id),
		"stress": stress[id],
		"light": light[id],
		"water_supply": last_supply[id],
		"nutrient_supply": last_nutrient[id],
		"source_url": d.source_url,
		"details":
		{
			"Древесина":
			(
				"валежник · %.1f биолет" % (fallen_age_s[id] / ForestClimate.YEAR_S)
				if fallen[id]
				else "на корню"
			),
			"Урожай":
			"%.4f кг C спелых плодов" % fruit_c[id] if d.fruit_bearing else "нет мясистых плодов",
			"Возобновление":
			(
				"Споры; общий конечный банк диаспор"
				if d.propagule_kind == &"spore"
				else "Семена; конечный семенной банк"
			),
			"Микориза":
			(
				{
					&"none": "нет",
					&"ecto": "эктомикориза: обмен при дефиците N/P",
					&"arbuscular": "арбускулярная: признак, обмен пока не рассчитан",
					&"ericoid": "эрикоидная: признак, обмен пока не рассчитан"
				}
				. get(d.mycorrhiza_type)
			),
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
	var result := {"version": 5, "configuration": _configuration(), "rng_state": rng.state}
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
		"seed_p",
		"leaf_carbon",
		"fallen",
		"fallen_age_s",
		"fruit_c",
		"reserved_seed_c"
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
			"leaf_mass_fraction",
			"mycorrhiza_type",
			"propagule_kind",
			"flower_start_day",
			"flower_duration_days",
			"insect_pollinated",
			"fruit_bearing",
			"fruit_start_day",
			"fruit_duration_days",
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
			"nurse_log_affinity",
			"snow_retention",
			"wind_resistance_m_s",
			"trampling_resistance",
			"recruitment_light",
			"dead_decay_per_year",
			"weight",
			"scale_range",
			"minimum_channel_distance",
			"initial_habitat_weights"
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
	if (
		state.get("version", 0) != 5
		or not _compatible_configuration(state.get("configuration", {}))
	):
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
		for field in ["fallen_age_s", "fruit_c", "reserved_seed_c"]:
			if not is_finite(state[field][i]) or state[field][i] < 0:
				return false
		if state.fallen[i] > 1 or (state.fallen[i] and state.alive[i]):
			return false
		if state.fruit_c[i] + state.reserved_seed_c[i] > state.seed_c[i] + 1e-8:
			return false
		if (
			not is_finite(state.leaf_carbon[i])
			or state.leaf_carbon[i] < 0
			or state.leaf_carbon[i] > state.biomass_c[i] + 1e-8
		):
			return false
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


static func flower_fraction(d: ForestPlantDefinition, day: float) -> float:
	var t := fposmod(day - d.flower_start_day, 365)
	return sin(PI * t / d.flower_duration_days) if t < d.flower_duration_days else 0.0


static func snow_load_index(d: ForestPlantDefinition, climate: Dictionary) -> float:
	# Display/risk index from the SAME snow bucket, not intercepted extra water.
	var foliage := ForestClimate.leaves(d, climate.get("day", 1.0))
	return clampf(
		climate.get("snow_water_m", 0.0) / .012 * d.snow_retention * (.1 + .9 * foliage), 0, 1
	)


static func critical_gust(
	d: ForestPlantDefinition,
	climate: Dictionary,
	stress_value: float,
	scale_value := 1.0,
	standing_dead := false
) -> float:
	var height := maxf(1, d.reference_height_m * scale_value)
	var crown := maxf(.25, d.crown_radius_m * scale_value)
	var foliage := (
		.2 if standing_dead else .2 + .8 * ForestClimate.leaves(d, climate.get("day", 150.0))
	)
	return (
		d.wind_resistance_m_s
		* (.25 if standing_dead else 1.0)
		* pow(13.0 / height, .35)
		* pow(3.0 / crown, .15)
		/ sqrt(foliage)
		/ (1 + .65 * stress_value + .3 * snow_load_index(d, climate))
	)


static func windfall_rate(
	d: ForestPlantDefinition,
	climate: Dictionary,
	stress_value: float,
	scale_value := 1.0,
	standing_dead := false
) -> float:
	# Failure hazard per hydrological second. Squared velocity is the load
	# proxy; excess load and duration determine the stochastic scenario risk.
	var ratio: float = (
		climate.get("wind_m_s", 0.0)
		/ critical_gust(d, climate, stress_value, scale_value, standing_dead)
	)
	var snow_hazard: float = (
		snow_load_index(d, climate)
		* .12
		* clampf(climate.get("wind_m_s", 0.0) / 12, 0, 2)
		/ ForestClimate.YEAR_S
	)
	return pow(maxf(0, ratio * ratio - 1), 2) / 120.0 + snow_hazard


func _windfall(dt: float, climate: Dictionary, exposure_dt := -1.0) -> void:
	if exposure_dt < 0:
		exposure_dt = dt
	var phase_rng := RandomNumberGenerator.new()
	phase_rng.seed = land.settings.seed + 54037
	var seed_phase := Vector2(phase_rng.randf_range(-500, 500), phase_rng.randf_range(-500, 500))
	for i in species.size():
		var d: ForestPlantDefinition = land.settings.plants[species[i]]
		if d.growth_form != &"tree":
			continue
		if fallen[i]:
			fallen_age_s[i] += dt
			continue
		var local_climate := ForestWeatherFront.local(
			climate, Vector2(positions[i].x, positions[i].z), true
		)
		var direction: Vector2 = local_climate.get(
			"wind_direction", Vector2(cos(yaw[i]), sin(yaw[i]))
		)
		var speed: float = local_climate.get("wind_m_s", 0.0)
		if climate.has("gust_offset_m"):
			speed *= ForestWeatherFront.gust_envelope(
				Vector2(positions[i].x, positions[i].z) - climate.gust_offset_m + seed_phase
			)
		local_climate = local_climate.duplicate()
		local_climate.wind_m_s = speed
		var hazard := (
			windfall_rate(d, local_climate, stress[i], size[i], not alive[i]) * exposure_dt
		)
		if not alive[i]:
			hazard += .6 * dt / ForestClimate.YEAR_S
		if rng.randf() < 1 - exp(-hazard):
			if alive[i]:
				_die(i)
			fallen[i] = 1
			yaw[i] = fposmod(direction.angle(), TAU)


func fallen_transform(id: int) -> Transform3D:
	var direction := Vector3(cos(yaw[id]), 0, sin(yaw[id]))
	var end := positions[id] + direction * _height(id)
	end.y = land.height_at(end.x, end.z)
	var axis := (end - positions[id]).normalized()
	var side := Vector3.UP.cross(axis).normalized()
	return Transform3D(
		Basis(side, axis, side.cross(axis)).scaled(Vector3.ONE * size[id]),
		positions[id] + Vector3.UP * .18
	)


func shelter_at(point: Vector3, radius: float) -> bool:
	for i in species.size():
		if fallen[i] and dead_c[i] > .01:
			var end := positions[i] + Vector3(cos(yaw[i]), 0, sin(yaw[i])) * _height(i)
			if (
				Geometry3D.get_closest_point_to_segment(point, positions[i], end).distance_to(point)
				< radius
			):
				return true
	return false


func _export_meal(id: int, request: float, seeds: bool) -> Vector3:
	if request <= 0 or not is_finite(request) or id < 0 or id >= species.size():
		return Vector3.ZERO
	var d: ForestPlantDefinition = land.settings.plants[species[id]]
	var available := (
		minf(fruit_c[id], maxf(0, seed_c[id] - reserved_seed_c[id]))
		if seeds
		else biomass_c[id] * .0002
	)
	var c := minf(request, available)
	var meal := Vector3(c, c / d.cn_ratio, c / d.cp_ratio) * .9999998
	if seeds:
		seed_c[id] -= meal.x
		seed_n[id] -= meal.y
		seed_p[id] -= meal.z
		fruit_c[id] = minf(fruit_c[id], seed_c[id] - reserved_seed_c[id])
	else:
		biomass_c[id] -= meal.x
		biomass_n[id] -= meal.y
		biomass_p[id] -= meal.z
		leaf_carbon[id] = minf(leaf_carbon[id], biomass_c[id])
		size[id] = pow(maxf(0, biomass_c[id] / d.biomass_kg_c), 1.0 / 3)
	exported_kg_c += meal.x
	exported_kg_n += meal.y
	exported_kg_p += meal.z
	revision += 1
	return meal


func harvest_fruit(id: int, request: float) -> Vector3:
	return _export_meal(id, request, true)


func harvest_nectar(id: int, request: float) -> Vector3:
	return _export_meal(id, request, false)


func reserve_seed(id: int) -> float:
	var d: ForestPlantDefinition = land.settings.plants[species[id]]
	var c := d.seed_cost_kg_c
	if seed_c[id] - reserved_seed_c[id] < c or fruit_c[id] < c:
		return 0
	reserved_seed_c[id] += c
	fruit_c[id] = minf(fruit_c[id], seed_c[id] - reserved_seed_c[id])
	return c


func drop_seed(id: int, c: float, point: Vector3, water: ForestWatershed) -> bool:
	var d: ForestPlantDefinition = land.settings.plants[species[id]]
	assert(c > 0 and reserved_seed_c[id] + 1e-10 >= c and seed_c[id] + 1e-10 >= c)
	reserved_seed_c[id] = maxf(0, reserved_seed_c[id] - c)
	seed_c[id] -= c
	seed_n[id] -= c / d.cn_ratio
	seed_p[id] -= c / d.cp_ratio
	fruit_c[id] = minf(fruit_c[id], seed_c[id] - reserved_seed_c[id])
	var cell := water.index_at(point.x, point.z)
	var valid := (
		point.x > 1
		and point.z > 1
		and point.x < land.settings.extent - 1
		and point.z < land.settings.extent - 1
	)
	valid = (
		valid
		and water.depth[cell] < d.flood_depth_m
		and water.soil[cell] > .2
		and _light_at(point.x, point.z) >= d.recruitment_light
	)
	valid = valid and absf(point.x - land.channel_x(point.z)) >= d.minimum_channel_distance
	for i in species.size():
		if alive[i] and positions[i].distance_squared_to(point) < 4:
			valid = false
	if not valid or species.size() >= MAX_INDIVIDUALS:
		if soil != null:
			soil.deposit_elements(point, c, c / d.cn_ratio, c / d.cp_ratio)
		litter_kg_c += c
		litter_kg_n += c / d.cn_ratio
		litter_kg_p += c / d.cp_ratio
		return false
	_append(
		species[id],
		Vector3(point.x, land.height_at(point.x, point.z) - .1, point.z),
		pow(c / d.biomass_kg_c, 1.0 / 3),
		0,
		c
	)
	recruits += 1
	revision += 1
	return true


func harvest_dead(id: int, request: float) -> Vector3:
	if request <= 0 or dead_c[id] <= 0:
		return Vector3.ZERO
	var fraction := minf(1, request / dead_c[id])
	var meal := (
		Vector3(dead_c[id] * fraction, dead_n[id] * fraction, dead_p[id] * fraction) * .9999998
	)
	dead_c[id] -= meal.x
	dead_n[id] -= meal.y
	dead_p[id] -= meal.z
	exported_kg_c += meal.x
	exported_kg_n += meal.y
	exported_kg_p += meal.z
	return meal


func _compatible_configuration(saved: Variant) -> bool:
	if not saved is Dictionary:
		return false
	var current := _configuration()
	if saved == current:
		return true
	# Pre-resistance worlds retain all previous ecological trait checks.
	for traits in current.traits:
		traits.erase("wind_resistance_m_s")
	return saved == current
