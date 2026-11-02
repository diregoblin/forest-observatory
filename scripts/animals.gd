class_name ForestAnimals
extends RefCounted

## Resource-driven herbivore/predator individuals, reproduction and finite transfers. Index is retained as the stable ID, even
## after death. All movements are executed here, never in the view.
const DEFAULT = preload("res://data/animals/hare.tres")
const FOX = preload("res://data/animals/fox.tres")
const THRUSH = preload("res://data/animals/thrush.tres")
const VOLE = preload("res://data/animals/bank_vole.tres")
const BOAR = preload("res://data/animals/boar.tres")
const BIN_M := 8.0
const HISTORY_LIMIT := 16
# Cosmetic only: monotone personal records, never population totals or starting age.
const DISTINCTIONS := [
	{
		"title": "Гроза подлеска",
		"metric": "consumed_c_kg",
		"minimum": .75,
		"reason": "Основательно познакомился с местной растительностью."
	},
	{
		"title": "Ушёл за хлебом",
		"metric": "distance_m",
		"minimum": 100.0,
		"reason": "Намотал немало лесных дорог."
	},
	{
		"title": "Мастер тихого часа",
		"metric": "rested_s",
		"minimum": 3 * ForestClimate.DAY_S,
		"reason": "Знает толк в долгом отдыхе и уютных укрытиях."
	},
	{
		"title": "Местная легенда",
		"metric": "lived_s",
		"minimum": 30 * ForestClimate.DAY_S,
		"reason": "Прожил в наблюдаемом лесу целый модельный месяц."
	}
]
var land: ForestLandscape
var plants
var water
var soil
var definitions: Array = []
var species_members: Array = []  # Derived append-only ID index; not authoritative state.
var species := PackedInt32Array()
var positions := PackedVector3Array()
var previous_positions := PackedVector3Array()
var yaw := PackedFloat64Array()
var age_years := PackedFloat64Array()
var energy_kj := PackedFloat64Array()
var biomass_c := PackedFloat64Array()
var biomass_n := PackedFloat64Array()
var biomass_p := PackedFloat64Array()
var alive := PackedByteArray()
var actions := PackedStringArray()
var alarm_remaining := PackedFloat64Array()
var danger_positions := PackedVector3Array()
var targets := PackedInt32Array()
var wander_yaw := PackedFloat64Array()
var routines := PackedStringArray()
var routine_time := PackedFloat64Array()
var fatigue := PackedFloat64Array()
var excursion_targets := PackedVector3Array()
var histories: Array = []
var life_records: Array = []
var home_positions := PackedVector3Array()
var food_memories := PackedInt32Array()
var danger_until_s := PackedFloat64Array()
var home_changes := PackedInt32Array()
var known_food_sites: Array = []
var _habitat_ref: WeakRef
var habitat: RefCounted:
	get:
		return _habitat_ref.get_ref() if _habitat_ref != null else null
	set(value):
		_habitat_ref = weakref(value) if value != null else null
var path_history: Array = []  # Per tick: {times: PackedFloat64Array, points: PackedVector3Array}.
var bins := {}
var _insect_site_bins := {}
var _insect_index_active := false  # Valid only inside this model's coupled step.
var rng := RandomNumberGenerator.new()
var elapsed_s := 0.0
var ticks := 0
var revision := 0
var total_distance_m := 0.0
var respired_c_kg := 0.0
var consumed_totals := PackedFloat64Array([0, 0, 0])
# Compatibility/display vector only. Never use float32 for cumulative accounting.
var consumed_cnp: Vector3:
	get:
		return Vector3(consumed_totals[0], consumed_totals[1], consumed_totals[2])
var excreted_cnp := Vector3.ZERO
var carcass_to_soil_cnp := Vector3.ZERO
var initial_cnp := Vector3.ZERO
var deaths := 0
var decision_checks := 0
var sexes := PackedByteArray()
var mothers := PackedInt32Array()
var fathers := PackedInt32Array()
var born_at := PackedFloat64Array()  # -1: scenario founder, not a simulated past.
var phenotypes: Array = []
var gestation_remaining := PackedFloat64Array()
var gestation_c := PackedFloat64Array()
var gestation_n := PackedFloat64Array()
var gestation_p := PackedFloat64Array()  # Owned float64 escrow, included in totals.
var killed_by := PackedInt32Array()
var pregnancy_fathers := PackedInt32Array()
var reproduction_cooldown := PackedFloat64Array()
var prey_targets := PackedInt32Array()
var kills := PackedInt32Array()
var births := 0
var predation_deaths := 0


func _init(
	l: ForestLandscape, plant_model, water_model, soil_model, species_definitions: Array = []
) -> void:
	land = l
	plants = plant_model
	water = water_model
	soil = soil_model
	definitions = (
		species_definitions.duplicate()
		if not species_definitions.is_empty()
		else [DEFAULT, FOX, VOLE, THRUSH, BOAR]
	)
	rng.seed = land.settings.seed + 41873
	var identities := {}
	for definition in definitions:
		definition.validate()
		assert(not identities.has(definition.species_id))
		identities[definition.species_id] = true
	_rebuild_bins()
	var observation := land.settings.fungi_plot_centers[0] * land.settings.extent
	var founder_groups: Array[Dictionary] = []
	for s in definitions.size():
		var sites := _founder_sites(definitions[s])
		var center := observation
		for _individual in definitions[s].initial_count:
			# Pairs share a local patch, but different pairs/species occupy
			# separated suitable sites across the domain, not one observation plot.
			if _individual % 2 == 0:
				center = _founder_center(
					sites, founder_groups, definitions[s].founder_pair_spacing_m, observation
				)
			var spawn := _spawn_position(center, definitions[s])
			var offset := Vector3(1.8, 0, 1.2) if _individual % 2 else Vector3.ZERO
			if definitions[s].trophic_role == &"predator":
				offset += Vector3(18, 0, 9)
			var candidate := spawn + offset
			candidate.x = clampf(candidate.x, 1, land.settings.extent - 1)
			candidate.z = clampf(candidate.z, 1, land.settings.extent - 1)
			candidate.y = land.height_at(candidate.x, candidate.z)
			if _founder_ground(candidate, definitions[s]):
				spawn = candidate
			if _individual % 2 == 0:
				founder_groups.append(
					{
						"point": Vector2(spawn.x, spawn.z),
						"spacing": definitions[s].founder_pair_spacing_m
					}
				)
			_append_animal(s, spawn)
	initial_cnp = element_totals()


func _append_animal(
	s: int,
	position: Vector3,
	mother := -1,
	father := -1,
	birth_time := -1.0,
	elements := Vector3.ZERO
) -> void:
	var definition: ForestAnimalDefinition = definitions[s]
	var newborn := mother >= 0
	var mass: Vector3 = elements if newborn else definition.initial_elements
	var id := species.size()
	species.append(s)
	species_members[s].append(id)
	home_positions.append(position)
	food_memories.append(-1)
	danger_until_s.append(0)
	home_changes.append(0)
	known_food_sites.append([])
	positions.append(position)
	previous_positions.append(position)
	yaw.append(0)
	age_years.append(0.0 if newborn else definition.initial_age_years)
	biomass_c.append(mass.x)
	biomass_n.append(mass.y)
	biomass_p.append(mass.z)
	energy_kj.append(
		(
			(
				mass.x
				- (
					definition.minimum_body_carbon_kg
					* (definition.newborn_fraction if newborn else 1.0)
				)
			)
			* definition.carbon_energy_kj_kg
		)
	)
	alive.append(1)
	actions.append("rest")
	alarm_remaining.append(0)
	danger_positions.append(position)
	targets.append(-1)
	wander_yaw.append(rng.randf() * TAU)
	routines.append("forage")
	routine_time.append(0)
	fatigue.append(0)
	excursion_targets.append(position)
	histories.append([])
	life_records.append(_empty_life_record())
	path_history.append(
		{"times": PackedFloat64Array([0]), "points": PackedVector3Array([position])}
	)
	sexes.append(rng.randi_range(0, 1) if newborn else id % 2)
	mothers.append(mother)
	fathers.append(father)
	born_at.append(birth_time)
	phenotypes.append(_phenotype(mother, father))
	gestation_remaining.append(0)
	gestation_c.append(0)
	gestation_n.append(0)
	gestation_p.append(0)
	killed_by.append(-1)
	pregnancy_fathers.append(-1)
	reproduction_cooldown.append(0)
	prey_targets.append(-1)
	kills.append(0)
	_event(
		id,
		"born" if newborn else "initial",
		"Родители #%d и #%d" % [mother, father] if newborn else "Заданное начальное состояние",
		birth_time
	)


func _gestation_amount(id: int) -> Vector3:
	return Vector3(gestation_c[id], gestation_n[id], gestation_p[id])


func _set_gestation(id: int, amount: Vector3) -> void:
	gestation_c[id] = amount.x
	gestation_n[id] = amount.y
	gestation_p[id] = amount.z


static func _valid_escrow(state: Dictionary, id: int) -> bool:
	for field in ["gestation_c", "gestation_n", "gestation_p"]:
		if not is_finite(state[field][id]) or state[field][id] < 0:
			return false
	return (
		state.killed_by[id] >= -1
		and state.killed_by[id] < state.species.size()
		and (state.killed_by[id] < 0 or not state.alive[id])
	)


func _phenotype(mother: int, father: int) -> Dictionary:
	var result := {}
	for key in ["build", "length", "ears", "ear_angle", "coat", "markings"]:
		result[key] = (
			rng.randf()
			if mother < 0
			else clampf(
				(
					(phenotypes[mother][key] + phenotypes[father][key]) * .5
					+ rng.randf_range(-.13, .13)
				),
				0,
				1
			)
		)
	return result


static func _age_fraction(d: ForestAnimalDefinition, age: float) -> float:
	return lerpf(d.newborn_fraction, 1.0, clampf(age * 365.0 / d.maturity_days, 0, 1))


func _growth_fraction(id: int) -> float:
	return _age_fraction(definitions[species[id]], age_years[id])


func _minimum_carbon(id: int) -> float:
	return definitions[species[id]].minimum_body_carbon_kg * _growth_fraction(id)


func _maximum_carbon(id: int) -> float:
	return definitions[species[id]].maximum_body_carbon_kg * _growth_fraction(id)


func _nearest_threat(id: int) -> int:
	var nearest: float = definitions[species[id]].sense_radius_m
	var threat := -1
	var prey_species: StringName = definitions[species[id]].species_id
	for s in definitions.size():
		if not definitions[s].prey_species.has(prey_species):
			continue
		for other in species_members[s]:
			if not alive[other]:
				continue
			var distance := positions[id].distance_to(positions[other])
			# Preserve the original global-ID tie break, including newborns.
			if distance < nearest or (threat >= 0 and distance == nearest and other < threat):
				nearest = distance
				threat = other
	return threat


func _concealed(id: int) -> bool:
	# Running from a nearby predator is not the same as remaining still in cover.
	# Detection is still local: _hunt checks its sensing radius before calling here.
	if actions[id] == "flee":
		return false
	var d: ForestAnimalDefinition = definitions[species[id]]
	for plant in _nearby(positions[id], 1.8):
		var plant_definition: ForestPlantDefinition = land.settings.plants[plants.species[plant]]
		if (
			plants.alive[plant]
			and plant_definition.reference_height_m * plants.size[plant] >= d.cover_minimum_height_m
		):
			return true
	return false


func _hunt(id: int, dt: float, event_time: float) -> void:
	var d: ForestAnimalDefinition = definitions[species[id]]
	var reserve := (
		(biomass_c[id] - _minimum_carbon(id)) / (_maximum_carbon(id) - _minimum_carbon(id))
	)
	var nearest := INF
	var target := -1
	prey_targets[id] = -1
	# Bounded hunting trips, interrupted by rest after a catch or fruitless search.
	# Critical hunger can interrupt recovery; neither rest nor search creates food.
	if routines[id] == "recover" and reserve >= .2:
		routine_time[id] += dt
		if routine_time[id] < d.hunting_rest_s:
			_set_action(id, "rest", event_time)
			life_records[id].rested_s += dt
			return
		routines[id] = "forage"
		routine_time[id] = 0
	elif routines[id] == "recover":
		routines[id] = "forage"
		routine_time[id] = 0
	if reserve >= d.hungry_fraction:
		routine_time[id] = 0
		_set_action(id, "rest", event_time)
		life_records[id].rested_s += dt
		return
	routine_time[id] += dt
	if routine_time[id] >= d.hunting_bout_s and reserve >= .2:
		routines[id] = "recover"
		routine_time[id] = 0
		_set_action(id, "rest", event_time)
		life_records[id].rested_s += dt
		return
	if reserve < d.hungry_fraction:
		for other in species.size():
			if not alive[other] or not d.prey_species.has(definitions[species[other]].species_id):
				continue
			if positions[other].distance_to(home_positions[id]) > d.home_range_m:
				continue
			var distance := positions[id].distance_to(positions[other])
			if distance > d.sense_radius_m:
				continue  # Do not inspect cover outside local perception.
			var range_m: float = d.sense_radius_m * (.4 if _concealed(other) else 1.0)
			if distance <= range_m and distance < nearest and _dry(positions[other], d):
				nearest = distance
				target = other
	prey_targets[id] = target
	if target >= 0:
		if nearest <= d.capture_reach_m:
			_consume_prey(id, target, event_time, dt)
		else:
			_move(
				id,
				(positions[target] - positions[id]).normalized(),
				minf(nearest, d.movement_m_biological_s * d.chase_multiplier * dt)
			)
			_set_action(id, "hunt", event_time)
		return
	# Persistent local patrol legs instead of redrawing a random heading each
	# locomotion substep. No global prey positions are used to pick a search goal.
	var direction := excursion_targets[id] - positions[id]
	direction.y = 0
	if direction.length() < d.bite_reach_m:
		_choose_excursion_goal(id, d)
		direction = excursion_targets[id] - positions[id]
		direction.y = 0
	var moved := _move(
		id, direction.normalized(), minf(direction.length(), d.movement_m_biological_s * dt)
	)
	if not moved:
		_choose_excursion_goal(id, d)
	_set_action(id, "search_prey", event_time)


func _consume_prey(id: int, prey: int, event_time: float, dt := -1.0) -> void:
	assert(alive[id] and alive[prey])
	var d: ForestAnimalDefinition = definitions[species[id]]
	var food := Vector3(biomass_c[prey], biomass_n[prey], biomass_p[prey]) + _gestation_amount(prey)
	if habitat != null:
		var request := (
			d.intake_carbon_kg_day * (d.action_step_s if dt < 0 else dt) / ForestClimate.DAY_S
		)
		request = minf(
			request, maxf(0, _maximum_carbon(id) - biomass_c[id]) / d.assimilation_fraction
		)
		var portion := food * minf(1, request / maxf(food.x, 1e-12))
		_assimilate_meal(id, portion)
		habitat.add_carcass(prey, positions[prey], food - portion)
		_remember_food(id, "carcass", prey, positions[prey], event_time)
	var fraction := minf(
		d.assimilation_fraction, maxf(0, _maximum_carbon(id) - biomass_c[id]) / maxf(food.x, 1e-12)
	)
	if habitat == null:
		var assimilated := food * fraction
		biomass_c[id] += assimilated.x
		biomass_n[id] += assimilated.y
		biomass_p[id] += assimilated.z
		_record_consumed(food)
		life_records[id].consumed_c_kg += food.x
		_deposit(prey, food - assimilated)
	biomass_c[prey] = 0
	biomass_n[prey] = 0
	biomass_p[prey] = 0
	_set_gestation(prey, Vector3.ZERO)
	gestation_remaining[prey] = 0
	pregnancy_fathers[prey] = -1
	energy_kj[prey] = 0
	alive[prey] = 0
	killed_by[prey] = id
	actions[prey] = "dead"
	targets[prey] = -1
	deaths += 1
	predation_deaths += 1
	kills[id] += 1
	routines[id] = "recover"
	routine_time[id] = 0
	_event(
		prey, "dead", "Поймана хищником #%d; запасы переданы, не продублированы" % id, event_time
	)
	_set_action(id, "eat", event_time)
	_event(id, "kill", "Добыча #%d" % prey, event_time)
	prey_targets[id] = -1


func _reproduce(id: int, dt: float, event_time: float) -> void:
	var d: ForestAnimalDefinition = definitions[species[id]]
	reproduction_cooldown[id] = maxf(0, reproduction_cooldown[id] - dt)
	if gestation_remaining[id] > 0:
		gestation_remaining[id] = maxf(0, gestation_remaining[id] - dt)
		if gestation_remaining[id] == 0:
			var father := pregnancy_fathers[id]
			var remaining := _gestation_amount(id)
			for kit in d.litter_size:
				var mass := remaining / float(d.litter_size - kit)
				remaining -= mass
				_append_animal(species[id], positions[id], id, father, event_time, mass)
				births += 1
			_set_gestation(id, Vector3.ZERO)
			pregnancy_fathers[id] = -1
			reproduction_cooldown[id] = d.reproduction_cooldown_days * ForestClimate.DAY_S
			_event(
				id,
				"litter",
				"Родилось %d; масса передана из оплаченного запаса" % d.litter_size,
				event_time
			)
		return
	if (
		not d.reproduction_enabled
		or sexes[id] != 0
		or age_years[id] * 365 < d.maturity_days
		or reproduction_cooldown[id] > 0
	):
		return
	var day := fposmod(land.settings.start_day - 1 + event_time / ForestClimate.DAY_S, 365) + 1
	if day < d.breeding_start_day or day > d.breeding_end_day:
		return
	var cost := d.initial_elements * (d.newborn_fraction * d.litter_size)
	var reserve_margin := (
		(_maximum_carbon(id) - _minimum_carbon(id)) * d.reproduction_reserve_fraction
	)
	if (
		biomass_c[id] - cost.x < _minimum_carbon(id) + reserve_margin
		or biomass_n[id] < cost.y
		or biomass_p[id] < cost.z
	):
		return
	var mate := -1
	var nearest := d.mating_radius_m
	for other in species.size():
		if (
			not alive[other]
			or species[other] != species[id]
			or sexes[other] != 1
			or age_years[other] * 365 < d.maturity_days
		):
			continue
		if mothers[other] == id or fathers[id] == other:
			continue
		var distance := positions[id].distance_to(positions[other])
		if distance < nearest and biomass_c[other] > _minimum_carbon(other) + reserve_margin:
			nearest = distance
			mate = other
	if mate < 0:
		return
	biomass_c[id] -= cost.x
	biomass_n[id] -= cost.y
	biomass_p[id] -= cost.z
	_set_gestation(id, cost)
	gestation_remaining[id] = d.gestation_days * ForestClimate.DAY_S
	pregnancy_fathers[id] = mate
	energy_kj[id] = maxf(0, biomass_c[id] - _minimum_carbon(id)) * d.carbon_energy_kj_kg
	_event(
		id,
		"pregnant",
		"Партнёр #%d; C/N/P выводка заранее отложены из тела матери" % mate,
		event_time
	)


func _valid_population(state: Dictionary) -> bool:
	var count: int = state.species.size()
	var founders := 0
	for d in definitions:
		founders += d.initial_count
	if (
		count < founders
		or state.births != count - founders
		or state.predation_deaths < 0
		or state.predation_deaths > state.deaths
	):
		return false
	for field in [
		"home_positions",
		"food_memories",
		"danger_until_s",
		"home_changes",
		"known_food_sites",
		"sexes",
		"mothers",
		"fathers",
		"born_at",
		"phenotypes",
		"gestation_remaining",
		"gestation_c",
		"gestation_n",
		"gestation_p",
		"killed_by",
		"pregnancy_fathers",
		"reproduction_cooldown",
		"prey_targets",
		"kills",
		"alive"
	]:
		if state[field].size() != count:
			return false
	var founder_index := 0
	for s in definitions.size():
		for _founder in definitions[s].initial_count:
			if state.species[founder_index] != s:
				return false
			founder_index += 1
	for id in count:
		if state.species[id] < 0 or state.species[id] >= definitions.size() or state.sexes[id] > 1:
			return false
		if not state.phenotypes[id] is Dictionary or state.phenotypes[id].size() != 6:
			return false
		for key in ["build", "length", "ears", "ear_angle", "coat", "markings"]:
			var value: Variant = state.phenotypes[id].get(key)
			if not value is float or not is_finite(value) or value < 0 or value > 1:
				return false
		if not is_finite(state.born_at[id]) or state.born_at[id] > state.elapsed_s:
			return false
		if id < founders:
			if state.mothers[id] != -1 or state.fathers[id] != -1 or state.born_at[id] != -1:
				return false
		else:
			var mother: int = state.mothers[id]
			var father: int = state.fathers[id]
			if mother < 0 or father < 0 or mother >= id or father >= id or state.born_at[id] < 0:
				return false
			if (
				state.species[mother] != state.species[id]
				or state.species[father] != state.species[id]
				or state.sexes[mother] != 0
				or state.sexes[father] != 1
			):
				return false
		for field in ["gestation_remaining", "reproduction_cooldown"]:
			if not is_finite(state[field][id]) or state[field][id] < 0:
				return false
		if (
			not _valid_escrow(state, id)
			or state.kills[id] < 0
			or state.prey_targets[id] < -1
			or state.prey_targets[id] >= count
		):
			return false
		var father: int = state.pregnancy_fathers[id]
		if state.gestation_remaining[id] > 0:
			if (
				father < 0
				or father >= count
				or state.sexes[id] != 0
				or state.sexes[father] != 1
				or state.species[father] != state.species[id]
				or not state.alive[id]
				or state.gestation_c[id] <= 0
			):
				return false
		elif (
			father != -1
			or (
				state.gestation_c[id] != 0
				or state.gestation_n[id] != 0
				or state.gestation_p[id] != 0
			)
		):
			return false
	return true


func _empty_life_record() -> Dictionary:
	return {"consumed_c_kg": 0.0, "distance_m": 0.0, "rested_s": 0.0, "lived_s": 0.0}


func _spawn_position(observation: Vector2, definition: ForestAnimalDefinition) -> Vector3:
	var origin := Vector3(observation.x, 0, observation.y)
	var nearest := -1
	var distance := 28.0
	for id in _nearby(origin, distance):
		if not _edible(id, definition):
			continue
		var d: float = Vector2(plants.positions[id].x, plants.positions[id].z).distance_to(
			observation
		)
		if d < distance and _founder_ground(plants.positions[id], definition):
			nearest = id
			distance = d
	if nearest >= 0:
		origin = plants.positions[nearest] + Vector3(1.4, 0, .8)
	for attempt in 24:
		var candidate := (
			origin + Vector3(cos(attempt * 2.4), 0, sin(attempt * 2.4)) * (attempt * .7)
		)
		candidate.x = clampf(candidate.x, 1, land.settings.extent - 1)
		candidate.z = clampf(candidate.z, 1, land.settings.extent - 1)
		candidate.y = land.height_at(candidate.x, candidate.z)
		if _founder_ground(candidate, definition):
			return candidate
	# Explicit fallback initial condition; model immediately reports blocked state.
	origin.y = land.height_at(origin.x, origin.z)
	return origin


func _founder_ground(point: Vector3, definition: ForestAnimalDefinition) -> bool:
	if not _dry(point, definition):
		return false
	var slope := (
		Vector2(
			land.height_at(point.x + 1, point.z) - land.height_at(point.x - 1, point.z),
			land.height_at(point.x, point.z + 1) - land.height_at(point.x, point.z - 1)
		)
		* .5
	)
	return slope.length() <= definition.max_slope


func _founder_sites(definition: ForestAnimalDefinition) -> PackedVector2Array:
	var food := PackedVector2Array()
	var shelter := PackedVector2Array()
	var food_cells := {}
	var shelter_cells := {}
	for id in plants.positions.size():
		if not plants.alive[id] or not _founder_ground(plants.positions[id], definition):
			continue
		var point: Vector3 = plants.positions[id]
		var cell := _bin(point)
		if _edible(id, definition) and not food_cells.has(cell):
			food.append(Vector2(point.x, point.z))
			food_cells[cell] = true
		if not shelter_cells.has(cell):
			shelter.append(Vector2(point.x, point.z))
			shelter_cells[cell] = true
	return shelter if food.is_empty() else food


func _founder_center(
	sites: PackedVector2Array, occupied: Array[Dictionary], spacing: float, fallback: Vector2
) -> Vector2:
	var best := fallback
	var best_score := -INF
	for candidate in sites:
		var score := -candidate.distance_squared_to(fallback) if occupied.is_empty() else INF
		for group in occupied:
			var gap := maxf(spacing, group.spacing)
			score = minf(score, candidate.distance_squared_to(group.point) / (gap * gap))
		if score > best_score:
			best_score = score
			best = candidate
	return best


func _rebuild_bins() -> void:
	_insect_index_active = false
	species_members.clear()
	for _definition in definitions:
		species_members.append([])
	for id in species.size():
		species_members[species[id]].append(id)
	bins.clear()
	for id in plants.positions.size():
		if not plants.alive[id]:
			continue
		var key := _bin(plants.positions[id])
		if not bins.has(key):
			bins[key] = []
		bins[key].append(id)


func _bin(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / BIN_M), floori(point.z / BIN_M))


func _nearby(point: Vector3, radius: float) -> Array:
	var result := []
	var center := _bin(point)
	var count := ceili(radius / BIN_M)
	for z in range(center.y - count, center.y + count + 1):
		for x in range(center.x - count, center.x + count + 1):
			for id in bins.get(Vector2i(x, z), []):
				var offset: Vector3 = plants.positions[id] - point
				if Vector2(offset.x, offset.z).length_squared() <= radius * radius:
					result.append(id)
	return result


func _edible_carbon(id: int) -> float:
	if id < 0 or id >= plants.positions.size() or not plants.alive[id]:
		return 0
	return plants.biomass_c[id] * land.settings.plants[plants.species[id]].edible_fraction


func _edible(id: int, definition: ForestAnimalDefinition) -> bool:
	return _food_carbon(id, definition) >= definition.minimum_edible_carbon_kg


func step(biological_dt: float) -> void:
	assert(is_finite(biological_dt) and biological_dt > 0)
	_rebuild_bins()  # Once per shared tick, not every locomotion substep.
	_rebuild_insect_index()
	previous_positions = positions.duplicate()
	for id in species.size():
		path_history[id] = {
			"times": PackedFloat64Array([0]), "points": PackedVector3Array([positions[id]])
		}
	var progressed := 0.0
	while progressed < biological_dt:
		var dt := biological_dt - progressed
		for definition in definitions:
			dt = minf(dt, definition.action_step_s)
			if definition.movement_m_biological_s > 0:
				dt = minf(
					dt,
					(
						definition.maximum_segment_m
						/ (
							definition.movement_m_biological_s
							* maxf(definition.escape_multiplier, definition.chase_multiplier)
						)
					)
				)
		for id in species.size():
			if alive[id]:
				life_records[id].lived_s += dt
				_act(id, dt, elapsed_s + progressed)
				age_years[id] += dt / ForestClimate.YEAR_S
				_metabolize(id, dt)
				if (
					biomass_c[id] <= _minimum_carbon(id) + 1e-12
					or age_years[id] >= definitions[species[id]].lifespan_years
				):
					_die(id, elapsed_s + progressed + dt)
			path_history[id].times.append(progressed + dt)
			path_history[id].points.append(positions[id])
		for id in species.size():
			if alive[id]:
				_reproduce(id, dt, elapsed_s + progressed + dt)
		progressed += dt
	elapsed_s += biological_dt
	ticks += 1
	revision += 1
	_insect_index_active = false


func _act(id: int, dt: float, event_time: float) -> void:
	var definition: ForestAnimalDefinition = definitions[species[id]]
	if not _dry(home_positions[id], definition):
		var replacement := _find_home(id)
		if replacement != home_positions[id] and _dry(replacement, definition):
			home_positions[id] = replacement
			home_changes[id] += 1
			if habitat != null:
				habitat.flooded_homes += 1
			_event(id, "home", "Старое убежище затоплено; выбрано сухое место", event_time)
	var threat := _nearest_threat(id)
	if threat >= 0:
		danger_positions[id] = positions[threat]
		danger_until_s[id] = event_time + 5 * ForestClimate.DAY_S
		alarm_remaining[id] = definition.alarm_memory_s
	else:
		alarm_remaining[id] = maxf(0, alarm_remaining[id] - dt)
	if threat >= 0 or alarm_remaining[id] > 0:
		var direction: Vector3 = positions[id] - danger_positions[id]
		direction.y = 0
		if direction.length_squared() < 1e-8:
			direction = Vector3(cos(wander_yaw[id]), 0, sin(wander_yaw[id]))
		_move(
			id,
			direction.normalized(),
			definition.movement_m_biological_s * definition.escape_multiplier * dt,
			danger_positions[id]
		)
		routines[id] = "forage"
		routine_time[id] = 0
		_set_action(id, "flee", event_time)
		return
	var reserve_fraction := (
		(biomass_c[id] - _minimum_carbon(id)) / (_maximum_carbon(id) - _minimum_carbon(id))
	)
	if (
		habitat != null
		and definition.scavenges
		and reserve_fraction < definition.sated_fraction
		and _scavenge(id, dt, event_time, definition)
	):
		return
	if habitat != null and habitat.weather.get("wind_m_s", 0.0) > 12 and reserve_fraction > .35:
		_home_action(id, dt, event_time, definition)
		return
	if (
		definition.insect_diet
		and habitat != null
		and reserve_fraction < definition.sated_fraction
		and habitat.insect_carbon(positions[id]) >= definition.minimum_edible_carbon_kg
	):
		var request := minf(
			definition.intake_carbon_kg_day * dt / ForestClimate.DAY_S,
			(_maximum_carbon(id) - biomass_c[id]) / definition.assimilation_fraction
		)
		var insect_food: Vector3 = habitat.harvest_insects(positions[id], maxf(0, request))
		if insect_food.x > 0:
			_assimilate_meal(id, insect_food)
			_remember_food(id, "insects", habitat.cell(positions[id]), positions[id], event_time)
			_ground_feeding(id, dt, event_time, insect_food.x, request)
			return
	if _sleep_action(id, dt, event_time, reserve_fraction, definition):
		return
	if definition.trophic_role == &"predator" and not _nearby_fruit(id, definition):
		_hunt(id, dt, event_time)
		return
	if _routine_action(id, dt, event_time, reserve_fraction, definition):
		return
	var hungry := reserve_fraction < definition.sated_fraction
	if (
		hungry
		and definition.insect_diet
		and habitat != null
		and _seek_insects(id, dt, event_time, definition)
	):
		return
	var target := -1
	var score := INF
	for plant_id in _nearby(positions[id], definition.sense_radius_m):
		decision_checks += 1
		if not plants.alive[plant_id]:
			continue
		if hungry and _remembered_empty(id, "plant", plant_id, event_time):
			continue
		var plant_trait: ForestPlantDefinition = land.settings.plants[plants.species[plant_id]]
		if hungry and not _edible(plant_id, definition):
			continue
		if (
			not hungry
			and (
				plant_trait.reference_height_m * plants.size[plant_id]
				< definition.cover_minimum_height_m
			)
		):
			continue
		var distance: float = positions[id].distance_to(plants.positions[plant_id])
		if plants.positions[plant_id].distance_to(home_positions[id]) > definition.home_range_m:
			continue
		if (
			danger_until_s[id] > event_time
			and (
				plants.positions[plant_id].distance_to(danger_positions[id])
				< definition.sense_radius_m
			)
		):
			distance += definition.sense_radius_m
		if food_memories[id] == plant_id:
			distance *= .75
		if distance < score and _dry(plants.positions[plant_id], definition):
			target = plant_id
			score = distance
	targets[id] = target
	if target >= 0 and score <= definition.bite_reach_m:
		if hungry:
			if not _edible(target, definition):
				targets[id] = -1
				_set_action(id, "seek_food", event_time)
				return
			var request := minf(
				definition.intake_carbon_kg_day * dt / ForestClimate.DAY_S,
				(_maximum_carbon(id) - biomass_c[id]) / definition.assimilation_fraction
			)
			request = minf(request, _food_carbon(target, definition))
			var eats_fruit: bool = (
				definition.fruit_diet
				and plants.fruit_c[target] >= definition.minimum_edible_carbon_kg
			)
			var food: Vector3 = (
				plants.harvest_fruit(target, maxf(0, request))
				if eats_fruit
				else plants.harvest(target, maxf(0, request))
			)
			assert(food.x >= 0 and food.y >= 0 and food.z >= 0 and food.x <= request + 1e-6)
			_assimilate_meal(id, food)
			if not eats_fruit:
				_ground_feeding(id, dt, event_time, food.x, request)
			else:
				_set_action(id, "eat", event_time)
			if food.x > 0:
				food_memories[id] = target
				_remember_food(
					id,
					"plant",
					target,
					plants.positions[target],
					event_time,
					_food_carbon(target, definition) < definition.minimum_edible_carbon_kg
				)
				if eats_fruit and habitat != null:
					habitat.carry_seed(id, target)
			routine_time[id] += dt
			fatigue[id] = minf(1, fatigue[id] + dt / (2 * ForestClimate.DAY_S))
			if routine_time[id] >= definition.feeding_bout_s:
				_begin_excursion(id, definition)
		else:
			_set_action(id, "shelter", event_time)
			life_records[id].rested_s += dt
		return
	if not hungry and target < 0:
		_set_action(id, "rest", event_time)
		life_records[id].rested_s += dt
		return
	var direction: Vector3
	if target >= 0:
		direction = plants.positions[target] - positions[id]
	elif hungry and _seek_remembered_food(id, dt, event_time, definition):
		return
	else:
		wander_yaw[id] += rng.randf_range(-.3, .3)
		direction = Vector3(sin(wander_yaw[id]), 0, cos(wander_yaw[id]))
	direction.y = 0
	direction = direction.normalized()
	var moved := _move(id, direction, definition.movement_m_biological_s * dt)
	_set_action(id, ("seek_food" if hungry else "seek_cover") if moved else "blocked", event_time)
	if not hungry:
		_begin_excursion(id, definition)


func _begin_excursion(id: int, definition: ForestAnimalDefinition) -> void:
	routines[id] = "explore"
	routine_time[id] = 0
	_choose_excursion_goal(id, definition)


func _choose_excursion_goal(id: int, definition: ForestAnimalDefinition) -> void:
	wander_yaw[id] += rng.randf_range(1.0, 5.0)
	var offset := (
		Vector3(sin(wander_yaw[id]), 0, cos(wander_yaw[id])) * definition.excursion_distance_m
	)
	var goal := positions[id] + offset
	goal.x = clampf(goal.x, 1, land.settings.extent - 1)
	goal.z = clampf(goal.z, 1, land.settings.extent - 1)
	goal.y = land.height_at(goal.x, goal.z)
	excursion_targets[id] = goal


func _routine_action(
	id: int, dt: float, event_time: float, reserve: float, definition: ForestAnimalDefinition
) -> bool:
	# Low reserves interrupt excursions; none of these activities manufacture food.
	if reserve < .2:
		routines[id] = "forage"
		routine_time[id] = 0
		return false  # Hunger must win even over high fatigue, not restart an excursion.
	if routines[id] == "forage":
		if reserve >= definition.sated_fraction or fatigue[id] >= .7:
			_begin_excursion(id, definition)
		else:
			return false
	targets[id] = -1
	routine_time[id] += dt
	if routines[id] == "explore":
		var direction := excursion_targets[id] - positions[id]
		direction.y = 0
		if direction.length() < definition.bite_reach_m or routine_time[id] > ForestClimate.DAY_S:
			routines[id] = "survey"
			routine_time[id] = 0
		else:
			var moved := _move(
				id,
				direction.normalized(),
				minf(direction.length(), definition.movement_m_biological_s * dt)
			)
			fatigue[id] = minf(1, fatigue[id] + dt / ForestClimate.DAY_S)
			_set_action(id, "explore" if moved else "blocked", event_time)
			return true
	if routines[id] == "survey":
		_set_action(id, "survey", event_time)
		if routine_time[id] >= definition.surveying_bout_s:
			routines[id] = "recover"
			routine_time[id] = 0
		return true
	_home_action(id, dt, event_time, definition)
	if routine_time[id] >= definition.resting_bout_s and fatigue[id] < .3:
		routines[id] = "forage"
		routine_time[id] = 0
	return true


func solar_hour(event_time: float) -> float:
	return fposmod(
		(
			land.settings.start_hour
			+ (
				event_time
				* land.settings.day_speed_multiplier
				/ land.settings.year_speed_multiplier
				/ 3600.0
			)
		),
		24
	)


func _sleep_action(
	id: int, dt: float, event_time: float, reserve: float, d: ForestAnimalDefinition
) -> bool:
	# A stable behavioral phase from append-only ID, independent of cosmetic genes/RNG.
	var phase := (fposmod(id * .61803398875, 1) * 2 - 1) * d.sleep_phase_spread_h
	var in_window := (
		fposmod(solar_hour(event_time) - d.sleep_start_hour - phase, d.sleep_period_h)
		< d.sleep_duration_h
	)
	var threshold := d.sleep_wake_reserve_fraction if actions[id] == "sleep" else d.sated_fraction
	if not in_window or reserve < threshold or not _dry(positions[id], d):
		return false
	if positions[id].distance_to(home_positions[id]) > d.bite_reach_m:
		_home_action(id, dt, event_time, d)
		return true
	_set_action(id, "sleep", event_time)
	life_records[id].rested_s += dt
	fatigue[id] = maxf(0, fatigue[id] - dt / d.resting_bout_s)
	routines[id] = "forage"
	routine_time[id] = 0
	prey_targets[id] = -1
	return true


func _move(
	id: int, direction: Vector3, maximum_distance: float, danger := Vector3(INF, INF, INF)
) -> bool:
	var definition: ForestAnimalDefinition = definitions[species[id]]
	var escaping := danger.is_finite()
	var best := positions[id]
	var best_swimming := false
	var best_score := positions[id].distance_squared_to(danger) if escaping else -INF
	for angle in [0.0, .785398, -.785398, 1.570796, -1.570796, 2.356194, -2.356194, PI]:
		var candidate := positions[id] + direction.rotated(Vector3.UP, angle) * maximum_distance
		if (
			candidate.x <= 0
			or candidate.z <= 0
			or candidate.x >= land.settings.extent
			or candidate.z >= land.settings.extent
		):
			continue
		if not escaping and candidate.distance_to(home_positions[id]) > definition.home_range_m:
			if (
				candidate.distance_to(home_positions[id])
				> positions[id].distance_to(home_positions[id])
			):
				continue
		candidate.y = land.height_at(candidate.x, candidate.z)
		var wet := (
			not _dry(candidate, definition)
			or not _dry(positions[id].lerp(candidate, .5), definition)
		)
		var swimming := definition.can_swim and definition.flight_height_m <= 0 and wet
		if swimming:
			candidate = (
				positions[id]
				+ (
					direction.rotated(Vector3.UP, angle)
					* maximum_distance
					* definition.swim_speed_fraction
				)
			)
			candidate.y = land.height_at(candidate.x, candidate.z)
		if (
			definition.flight_height_m <= 0
			and not swimming
			and absf(candidate.y - positions[id].y) > maximum_distance * definition.max_slope
		):
			continue
		if (
			definition.flight_height_m <= 0
			and not definition.can_swim
			and (
				not _dry(candidate, definition)
				or not _dry(positions[id].lerp(candidate, .5), definition)
			)
		):
			continue
		var score := candidate.distance_squared_to(danger) if escaping else 0.0
		if score > best_score:
			best = candidate
			best_score = score
			best_swimming = swimming
		if not escaping:
			break
	var offset := best - positions[id]
	var distance := Vector2(offset.x, offset.z).length()
	if distance <= 0:
		return false
	positions[id] = best
	yaw[id] = atan2(offset.x, offset.z)
	total_distance_m += distance
	life_records[id].distance_m += distance
	var carbon := minf(
		biomass_c[id],
		(
			distance
			* definition.movement_carbon_kg_m
			* (definition.swim_cost_multiplier if best_swimming else 1.0)
		)
	)
	biomass_c[id] -= carbon
	respired_c_kg += carbon
	return true


func _dry(position: Vector3, definition: ForestAnimalDefinition) -> bool:
	return water.depth[water.index_at(position.x, position.z)] <= definition.flood_depth_m


func is_swimming(id: int) -> bool:
	var d: ForestAnimalDefinition = definitions[species[id]]
	return bool(alive[id]) and d.can_swim and d.flight_height_m <= 0 and not _dry(positions[id], d)


func _metabolize(id: int, dt: float) -> void:
	var definition: ForestAnimalDefinition = definitions[species[id]]
	var resting_rate := definition.sleep_metabolism_fraction if actions[id] == "sleep" else 1.0
	var carbon := minf(
		biomass_c[id],
		(
			definition.basal_carbon_kg_day
			* pow(_growth_fraction(id), .75)
			* resting_rate
			* dt
			/ ForestClimate.DAY_S
		)
	)
	biomass_c[id] -= carbon
	respired_c_kg += carbon
	energy_kj[id] = (maxf(0, biomass_c[id] - _minimum_carbon(id)) * definition.carbon_energy_kj_kg)
	# Excess assimilated N/P cannot accumulate forever as fictitious animal growth.
	var excess := Vector3(
		0,
		maxf(0, biomass_n[id] - definition.initial_elements.y),
		maxf(0, biomass_p[id] - definition.initial_elements.z)
	)
	biomass_n[id] -= excess.y
	biomass_p[id] -= excess.z
	_deposit(id, excess)


func _record_consumed(food: Vector3) -> void:
	consumed_totals[0] += food.x
	consumed_totals[1] += food.y
	consumed_totals[2] += food.z


func _deposit(id: int, amount: Vector3) -> void:
	if amount.length_squared() > 0:
		soil.deposit(positions[id], amount, true)
		excreted_cnp += amount


func _die(id: int, event_time := -1.0) -> void:
	if not alive[id]:
		return
	var amount := Vector3(biomass_c[id], biomass_n[id], biomass_p[id]) + _gestation_amount(id)
	if habitat != null:
		habitat.add_carcass(id, positions[id], amount)
	else:
		soil.deposit(positions[id], amount, true)
		carcass_to_soil_cnp += amount
	biomass_c[id] = 0
	biomass_n[id] = 0
	biomass_p[id] = 0
	energy_kj[id] = 0
	_set_gestation(id, Vector3.ZERO)
	gestation_remaining[id] = 0
	pregnancy_fathers[id] = -1
	alive[id] = 0
	actions[id] = "dead"
	targets[id] = -1
	deaths += 1
	_event(
		id,
		"dead",
		(
			"Останки остаются на месте; доступна падаль"
			if habitat != null
			else "Биомасса передана почве ровно один раз"
		),
		event_time
	)


func _set_action(id: int, action: String, event_time: float) -> void:
	if actions[id] != action:
		actions[id] = action
		_event(id, action, "", event_time)


func _event(id: int, action: String, detail := "", event_time := -1.0) -> void:
	histories[id].append(
		{"time_s": elapsed_s if event_time < 0 else event_time, "action": action, "detail": detail}
	)
	if histories[id].size() > HISTORY_LIMIT:
		histories[id].pop_front()


func display_position(id: int, alpha := 1.0) -> Vector3:
	var path: Dictionary = path_history[id]
	var target_time: float = path.times[-1] * clampf(alpha, 0, 1)
	for i in range(1, path.times.size()):
		if target_time <= path.times[i]:
			var weight: float = (
				(target_time - path.times[i - 1]) / maxf(1e-12, path.times[i] - path.times[i - 1])
			)
			return path.points[i - 1].lerp(path.points[i], weight)
	return positions[id]


func inspect(id: int) -> Dictionary:
	if id < 0 or id >= species.size():
		return {}
	var definition: ForestAnimalDefinition = definitions[species[id]]
	var labels := {
		"rest": "отдыхает",
		"sleep": "спит",
		"eat": "ест",
		"root": "роет почву и кормится",
		"shelter": "в укрытии",
		"seek_food": "ищет местный корм",
		"seek_cover": "идёт в укрытие",
		"explore": "обходит окрестности",
		"survey": "осматривается и прислушивается",
		"blocked": "проход затоплен или слишком крут",
		"flee": "убегает от хищника",
		"hunt": "преследует добычу",
		"search_prey": "ищет добычу",
		"dead": "погибла"
	}
	var movement_note := (
		"Сценарно %.2f м / биологические сутки, не скорость бега"
		% (definition.movement_m_biological_s * ForestClimate.DAY_S)
	)
	var distinctions := []
	for rule in DISTINCTIONS:
		if life_records[id][rule.metric] >= rule.minimum:
			distinctions.append({"title": rule.title, "reason": rule.reason})
	return {
		"kind": "animal",
		"id": id,
		"stable_id": id,
		"species_id": definition.species_id,
		"title": "%s #%d" % [definition.display_name, id],
		"subtitle": definition.latin_name,
		"display_name": definition.display_name,
		"latin_name": definition.latin_name,
		"description": definition.description,
		"source_url": definition.source_url,
		"life_cycle": definition.life_cycle,
		"age_years": age_years[id],
		"initial_age": born_at[id] < 0,
		"alive": bool(alive[id]),
		"stage":
		(
			("детёныш" if age_years[id] * 365 < definition.maturity_days else "взрослая особь")
			if alive[id]
			else "погибла"
		),
		"state": actions[id],
		"action": actions[id],
		"position": positions[id],
		"energy_kj": energy_kj[id],
		"target_plant_id": targets[id],
		"elements_kg": Vector3(biomass_c[id], biomass_n[id], biomass_p[id]),
		"history": histories[id].duplicate(true),
		"distinctions": distinctions,
		"selection_radius_m": definition.selection_radius_m,
		"selection_height_m": definition.selection_height_m,
		"movement_note": movement_note,
		"initial_age_source":
		(
			"Начальный возраст задан сценарием; далее возрастает по общим биологическим часам"
			if born_at[id] < 0
			else "Родилась в наблюдаемом мире; возраст отсчитывается от рождения"
		),
		"details":
		{
			"Действие":
			("плывёт · " if is_swimming(id) else "") + labels.get(actions[id], actions[id]),
			"Энергия": "%.0f кДж" % energy_kj[id],
			"Суточный ритм": "Сон по солнечным часам; голод и опасность будят",
			"Тревога": "Помнит угрозу" if alarm_remaining[id] > 0 else "Нет замеченной угрозы",
			"Корм":
			(
				(
					"Добыча #%d" % prey_targets[id]
					if prey_targets[id] >= 0
					else "Местная добыча не замечена"
				)
				if definition.trophic_role == &"predator"
				else (
					"Растение #%d" % targets[id] if targets[id] >= 0 else "Местный корм не выбран"
				)
			),
			"Шкала движения": movement_note,
			"Порои":
			(
				(
					"Нарушение покрова в местной ячейке: %.1f %%"
					% (100 * habitat.rooting[water.index_at(positions[id].x, positions[id].z)])
				)
				if habitat != null and definition.rooting_pressure_day > 0
				else "Не роющий вид"
			),
			"Возраст":
			"Начальный возраст задан сценарием" if born_at[id] < 0 else "Родилась в симуляции",
			"Пол": "самка" if sexes[id] == 0 else "самец",
			"Родители":
			(
				"Заданная исходная особь"
				if mothers[id] < 0
				else "#%d и #%d" % [mothers[id], fathers[id]]
			),
			"Выводок":
			(
				"До рождения %.1f биодня" % (gestation_remaining[id] / ForestClimate.DAY_S)
				if gestation_remaining[id] > 0
				else "Нет ожидаемого выводка"
			),
			"Удачные охоты": str(kills[id]),
			"Кормовые места":
			"%d / 4 помнятся; истощённые временно пропускаются" % known_food_sites[id].size(),
			"Останки":
			(
				"%.4f кг C осталось на месте" % habitat.carcass_carbon(id)
				if habitat != null and not alive[id]
				else "—"
			),
			"Дом":
			(
				"%s · %.1f м от дома · смен %d"
				% [
					definition.shelter_kind,
					positions[id].distance_to(home_positions[id]),
					home_changes[id]
				]
			),
			"Знакомый корм":
			"Растение #%d" % food_memories[id] if food_memories[id] >= 0 else "Ещё не найден",
			"Память опасности":
			"Избегает места встречи" if danger_until_s[id] > elapsed_s else "Нет свежей опасности"
		},
		"reproduction":
		"Ресурсно-ограниченное" if definition.reproduction_enabled else "Отключено для этого вида"
	}


func element_totals() -> Vector3:
	var total := Vector3.ZERO
	for id in species.size():
		total += Vector3(biomass_c[id], biomass_n[id], biomass_p[id]) + _gestation_amount(id)
	return total


func metrics() -> Dictionary:
	return {
		"count": species.size(),
		"alive": alive.count(1),
		"deaths": deaths,
		"elapsed_s": elapsed_s,
		"distance_m": total_distance_m,
		"respired_c_kg": respired_c_kg,
		"consumed_cnp": consumed_cnp,
		"excreted_cnp": excreted_cnp,
		"carcass_to_soil_cnp": carcass_to_soil_cnp,
		"initial_cnp": initial_cnp,
		"elements": element_totals(),
		"decision_checks": decision_checks,
		"reproduction_implemented": true,
		"births": births,
		"predation_deaths": predation_deaths
	}


func _configuration() -> Dictionary:
	var traits := []
	for definition in definitions:
		var values := {}
		for property in definition.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				values[property.name] = definition.get(property.name)
		traits.append(values)
	return {
		"seed": land.settings.seed,
		"extent": land.settings.extent,
		"definitions": traits,
		"start_hour": land.settings.start_hour,
		"day_multiplier": land.settings.day_speed_multiplier,
		"year_multiplier": land.settings.year_speed_multiplier
	}


func snapshot() -> Dictionary:
	var state := {"version": 8, "configuration": _configuration(), "rng_state": rng.state}
	for field in _state_fields():
		var value: Variant = get(field)
		state[field] = (
			value.duplicate(true)
			if value is Array or value is Dictionary
			else (
				value.duplicate()
				if (
					typeof(value)
					in [
						TYPE_PACKED_INT32_ARRAY,
						TYPE_PACKED_FLOAT64_ARRAY,
						TYPE_PACKED_VECTOR3_ARRAY,
						TYPE_PACKED_BYTE_ARRAY,
						TYPE_PACKED_STRING_ARRAY
					]
				)
				else value
			)
		)
	return state


func _state_fields() -> Array:
	return [
		"home_positions",
		"food_memories",
		"danger_until_s",
		"home_changes",
		"known_food_sites",
		"sexes",
		"mothers",
		"fathers",
		"born_at",
		"phenotypes",
		"gestation_remaining",
		"gestation_c",
		"gestation_n",
		"gestation_p",
		"killed_by",
		"pregnancy_fathers",
		"reproduction_cooldown",
		"prey_targets",
		"kills",
		"births",
		"predation_deaths",
		"species",
		"positions",
		"previous_positions",
		"yaw",
		"age_years",
		"energy_kj",
		"biomass_c",
		"biomass_n",
		"biomass_p",
		"alive",
		"actions",
		"alarm_remaining",
		"danger_positions",
		"targets",
		"wander_yaw",
		"routines",
		"routine_time",
		"fatigue",
		"excursion_targets",
		"histories",
		"life_records",
		"path_history",
		"elapsed_s",
		"ticks",
		"revision",
		"total_distance_m",
		"respired_c_kg",
		"consumed_totals",
		"excreted_cnp",
		"carcass_to_soil_cnp",
		"initial_cnp",
		"deaths",
		"decision_checks"
	]


# gdlint: disable=max-returns
func restore(state: Dictionary) -> bool:
	# Full validation first: bad save never partly mutates animals or soil.
	if (
		state.get("version", 0) != 8
		or state.get("configuration", {}) != _configuration()
		or not state.get("rng_state") is int
	):
		return false
	for field in _state_fields():
		if not state.has(field) or typeof(state[field]) != typeof(get(field)):
			return false
	var count: int = state.species.size()
	if not _valid_population(state):
		return false
	for field in [
		"home_positions",
		"food_memories",
		"danger_until_s",
		"home_changes",
		"known_food_sites",
		"positions",
		"previous_positions",
		"yaw",
		"age_years",
		"energy_kj",
		"biomass_c",
		"biomass_n",
		"biomass_p",
		"alive",
		"actions",
		"alarm_remaining",
		"danger_positions",
		"targets",
		"wander_yaw",
		"routines",
		"routine_time",
		"fatigue",
		"excursion_targets",
		"histories",
		"life_records",
		"path_history"
	]:
		if state[field].size() != count:
			return false
	for field in [
		"elapsed_s",
		"ticks",
		"revision",
		"total_distance_m",
		"respired_c_kg",
		"deaths",
		"decision_checks"
	]:
		if not is_finite(state[field]) or state[field] < 0:
			return false
	if state.consumed_totals.size() != 3:
		return false
	for amount in state.consumed_totals:
		if not is_finite(amount) or amount < 0:
			return false
	for field in ["excreted_cnp", "carcass_to_soil_cnp", "initial_cnp"]:
		if not _valid_elements(state[field]):
			return false
	var recorded_distance := 0.0
	var recorded_food := 0.0
	for id in count:
		if not state.known_food_sites[id] is Array or state.known_food_sites[id].size() > 4:
			return false
		for memory in state.known_food_sites[id]:
			if (
				not memory is Dictionary
				or memory.get("kind") not in ["plant", "carcass", "insects"]
				or not memory.get("source") is int
				or memory.source < 0
			):
				return false
			if (
				(memory.kind == "plant" and memory.source >= plants.species.size())
				or (memory.kind == "carcass" and memory.source >= count)
				or (
					memory.kind == "insects"
					and (habitat == null or memory.source >= habitat.insect_sites.size())
				)
			):
				return false
			if (
				not memory.get("position") is Vector3
				or not memory.position.is_finite()
				or memory.position.x < 0
				or memory.position.z < 0
				or memory.position.x >= land.settings.extent
				or memory.position.z >= land.settings.extent
			):
				return false
			for key in ["seen_s", "empty_until_s"]:
				if not memory.get(key) is float or not is_finite(memory[key]) or memory[key] < 0:
					return false
		if (
			not is_finite(state.danger_until_s[id])
			or state.danger_until_s[id] < 0
			or state.home_changes[id] < 0
		):
			return false
		if state.food_memories[id] < -1 or state.food_memories[id] >= plants.positions.size():
			return false
		if state.routines[id] not in ["forage", "explore", "survey", "recover"]:
			return false
		if not is_finite(state.routine_time[id]) or state.routine_time[id] < 0:
			return false
		if not is_finite(state.fatigue[id]) or state.fatigue[id] < 0 or state.fatigue[id] > 1:
			return false
		if state.species[id] < 0 or state.species[id] >= definitions.size() or state.alive[id] > 1:
			return false
		if (
			not is_finite(state.alarm_remaining[id])
			or state.alarm_remaining[id] < 0
			or state.alarm_remaining[id] > definitions[state.species[id]].alarm_memory_s
		):
			return false
		for field in ["age_years", "energy_kj", "biomass_c", "biomass_n", "biomass_p"]:
			if not is_finite(state[field][id]) or state[field][id] < 0:
				return false
		for field in ["yaw", "wander_yaw"]:
			if not is_finite(state[field][id]):
				return false
		for field in [
			"positions",
			"previous_positions",
			"excursion_targets",
			"danger_positions",
			"home_positions"
		]:
			var point: Vector3 = state[field][id]
			if (
				not point.is_finite()
				or point.x < 0
				or point.z < 0
				or point.x > land.settings.extent
				or point.z > land.settings.extent
			):
				return false
		if not (
			state.actions[id]
			in [
				"rest",
				"sleep",
				"eat",
				"root",
				"shelter",
				"seek_food",
				"seek_cover",
				"explore",
				"survey",
				"blocked",
				"flee",
				"hunt",
				"search_prey",
				"dead"
			]
		):
			return false
		var definition: ForestAnimalDefinition = definitions[state.species[id]]
		if not _valid_life_record(
			state.life_records[id],
			state.elapsed_s,
			INF if definition.trophic_role == &"predator" else definition.intake_carbon_kg_day
		):
			return false
		recorded_distance += state.life_records[id].distance_m
		recorded_food += state.life_records[id].consumed_c_kg
		var expected_energy := (
			maxf(
				0,
				(
					state.biomass_c[id]
					- (
						definition.minimum_body_carbon_kg
						* _age_fraction(definition, state.age_years[id])
					)
				)
			)
			* definition.carbon_energy_kj_kg
		)
		if (
			absf(state.energy_kj[id] - expected_energy) > 1e-6
			or (
				state.biomass_c[id]
				> (
					(
						definition.maximum_body_carbon_kg
						* _age_fraction(definition, state.age_years[id])
					)
					+ 1e-6
				)
			)
		):
			return false
		if (
			not state.alive[id]
			and (
				state.biomass_c[id] != 0
				or state.biomass_n[id] != 0
				or state.biomass_p[id] != 0
				or state.actions[id] != "dead"
			)
		):
			return false
		if state.targets[id] < -1 or state.targets[id] >= plants.positions.size():
			return false
		if not state.histories[id] is Array or state.histories[id].size() > HISTORY_LIMIT:
			return false
		for event in state.histories[id]:
			if (
				not event is Dictionary
				or not event.get("time_s") is float
				or not is_finite(event.time_s)
				or event.time_s < 0
				or not event.get("action") is String
				or not event.get("detail") is String
			):
				return false
		var path: Variant = state.path_history[id]
		if (
			not path is Dictionary
			or not path.get("times") is PackedFloat64Array
			or not path.get("points") is PackedVector3Array
			or path.times.size() != path.points.size()
			or path.times.is_empty()
			or path.times[0] != 0
		):
			return false
		for p in path.times.size():
			var point: Vector3 = path.points[p]
			if (
				not is_finite(path.times[p])
				or path.times[p] < 0
				or not point.is_finite()
				or point.x < 0
				or point.z < 0
				or point.x > land.settings.extent
				or point.z > land.settings.extent
			):
				return false
			if p > 0 and path.times[p] <= path.times[p - 1]:
				return false
			if p > 0:
				var offset: Vector3 = point - path.points[p - 1]
				if Vector2(offset.x, offset.z).length() > definition.maximum_segment_m + 5e-5:
					return false
		if path.points[-1] != state.positions[id] or path.points[0] != state.previous_positions[id]:
			return false
	if recorded_distance > state.total_distance_m + 1e-8 * maxf(1, state.total_distance_m):
		return false
	if recorded_food > state.consumed_totals[0] + 1e-8 * maxf(1, state.consumed_totals[0]):
		return false
	for field in _state_fields():
		var value: Variant = state[field]
		set(
			field,
			(
				value.duplicate(true)
				if value is Array or value is Dictionary
				else (
					value.duplicate()
					if (
						typeof(value)
						in [
							TYPE_PACKED_INT32_ARRAY,
							TYPE_PACKED_FLOAT64_ARRAY,
							TYPE_PACKED_VECTOR3_ARRAY,
							TYPE_PACKED_BYTE_ARRAY,
							TYPE_PACKED_STRING_ARRAY
						]
					)
					else value
				)
			)
		)
	rng.state = state.rng_state
	_rebuild_bins()
	return true


func _valid_elements(amount: Vector3) -> bool:
	return amount.is_finite() and amount.x >= 0 and amount.y >= 0 and amount.z >= 0


func _valid_life_record(
	value: Variant, maximum_lived_s: float, intake_carbon_kg_day: float
) -> bool:
	if not value is Dictionary or value.size() != _empty_life_record().size():
		return false
	for key in _empty_life_record():
		if not value.get(key) is float or not is_finite(value[key]) or value[key] < 0:
			return false
	var intake_limit: float = (
		INF
		if is_inf(intake_carbon_kg_day)
		else value.lived_s / ForestClimate.DAY_S * intake_carbon_kg_day
	)
	return (
		value.lived_s <= maximum_lived_s + 1e-5
		and value.rested_s <= value.lived_s + 1e-5
		and value.consumed_c_kg <= intake_limit + 1e-6 * maxf(1, intake_limit)
	)


func _food_carbon(id: int, definition: ForestAnimalDefinition) -> float:
	if definition.fruit_diet:
		var fruit: float = (
			plants.fruit_c[id]
			if id >= 0 and id < plants.species.size() and plants.alive[id]
			else 0.0
		)
		if fruit >= definition.minimum_edible_carbon_kg or not definition.vegetation_fallback:
			return fruit
	return _edible_carbon(id)


func _nearby_fruit(id: int, d: ForestAnimalDefinition) -> bool:
	if not d.fruit_diet or habitat == null:
		return false
	for plant in _nearby(positions[id], d.sense_radius_m):
		if (
			_edible(plant, d)
			and plants.positions[plant].distance_to(home_positions[id]) <= d.home_range_m
			and _dry(plants.positions[plant], d)
		):
			return true
	return false


func _scavenge(id: int, dt: float, event_time: float, d: ForestAnimalDefinition) -> bool:
	var target := -1
	var nearest := d.sense_radius_m
	var point := Vector3.ZERO
	for body in habitat.carcasses:
		if (
			body.c < d.minimum_edible_carbon_kg
			or _remembered_empty(id, "carcass", body.source, event_time)
		):
			continue
		var distance: float = positions[id].distance_to(body.position)
		if (
			distance < nearest
			and body.position.distance_to(home_positions[id]) <= d.home_range_m
			and (_dry(body.position, d) or d.can_swim)
		):
			target = body.source
			point = body.position
			nearest = distance
	if target < 0:
		return _seek_remembered_food(id, dt, event_time, d, "carcass")
	if nearest <= d.bite_reach_m:
		var request := minf(
			d.intake_carbon_kg_day * dt / ForestClimate.DAY_S,
			maxf(0, _maximum_carbon(id) - biomass_c[id]) / d.assimilation_fraction
		)
		var meal: Vector3 = habitat.harvest_carcass(target, request)
		_assimilate_meal(id, meal)
		_remember_food(
			id,
			"carcass",
			target,
			point,
			event_time,
			habitat.carcass_carbon(target) < d.minimum_edible_carbon_kg
		)
		_set_action(id, "eat", event_time)
		return meal.x > 0
	var direction := point - positions[id]
	direction.y = 0
	var moved := _move(
		id, direction.normalized(), minf(direction.length(), d.movement_m_biological_s * dt)
	)
	_set_action(id, "seek_food" if moved else "blocked", event_time)
	return moved


func _remember_food(
	id: int, kind: String, source: int, point: Vector3, time: float, empty := false
) -> void:
	var memories: Array = known_food_sites[id]
	for i in range(memories.size() - 1, -1, -1):
		if memories[i].kind == kind and memories[i].source == source:
			memories.remove_at(i)
	memories.append(
		{
			"kind": kind,
			"source": source,
			"position": point,
			"seen_s": time,
			"empty_until_s": time + 2 * ForestClimate.DAY_S if empty else 0.0
		}
	)
	while memories.size() > 4:
		memories.pop_front()
	known_food_sites[id] = memories


func _remembered_empty(id: int, kind: String, source: int, time: float) -> bool:
	for memory in known_food_sites[id]:
		if memory.kind == kind and memory.source == source and memory.empty_until_s > time:
			return true
	return false


func _seek_remembered_food(
	id: int, dt: float, time: float, d: ForestAnimalDefinition, only_kind := ""
) -> bool:
	for memory in known_food_sites[id].duplicate():
		if (
			(not only_kind.is_empty() and memory.kind != only_kind)
			or memory.empty_until_s > time
			or time - memory.seen_s > 30 * ForestClimate.DAY_S
		):
			continue
		var point: Vector3 = memory.position
		if point.distance_to(home_positions[id]) > d.home_range_m:
			continue
		var direction := point - positions[id]
		direction.y = 0
		if direction.length() <= d.bite_reach_m:
			# Only arrival updates a remembered remote patch's availability.
			_remember_food(id, memory.kind, memory.source, point, time, true)
			continue
		var moved := _move(
			id, direction.normalized(), minf(direction.length(), d.movement_m_biological_s * dt)
		)
		_set_action(id, "seek_food" if moved else "blocked", time)
		return moved
	return false


func _seek_insects(id: int, dt: float, event_time: float, d: ForestAnimalDefinition) -> bool:
	var target := Vector3(INF, INF, INF)
	var nearest := d.sense_radius_m
	var current_cell: int = habitat.cell(positions[id])
	for k in _nearby_insect_sites(positions[id], d.sense_radius_m):
		var site: int = habitat.insect_sites[k]
		if habitat.insect_carbon_in_cell(k) < d.minimum_edible_carbon_kg:
			continue
		var point: Vector3 = plants.positions[site] if site >= 0 else habitat.center(k)
		var distance := positions[id].distance_to(point)
		if current_cell == k or point.distance_to(home_positions[id]) > d.home_range_m:
			continue
		if distance < nearest and _dry(point, d):
			nearest = distance
			target = point
	if not target.is_finite():
		return false
	var direction := target - positions[id]
	direction.y = 0
	var moved := _move(
		id, direction.normalized(), minf(direction.length(), d.movement_m_biological_s * dt)
	)
	_set_action(id, "seek_food" if moved else "blocked", event_time)
	return moved


func _rebuild_insect_index() -> void:
	_insect_index_active = false
	_insect_site_bins.clear()
	if habitat == null:
		return
	# Sites/plant positions stay fixed during our step; finite food pools do not.
	# Index actual feeding points, not habitat-cell centres: a site can be off-centre.
	for k in habitat.insect_sites.size():
		var site: int = habitat.insect_sites[k]
		var point: Vector3 = plants.positions[site] if site >= 0 else habitat.center(k)
		var key := _bin(point)
		if not _insect_site_bins.has(key):
			_insect_site_bins[key] = []
		_insect_site_bins[key].append(k)
	_insect_index_active = true


func _nearby_insect_sites(point: Vector3, radius: float) -> Array:
	# Public/direct decisions outside a coupled step see fresh data without a cache.
	if not _insect_index_active:
		return range(habitat.insect_sites.size())
	var result := []
	var center := _bin(point)
	var count := ceili(radius / BIN_M)
	for z in range(center.y - count, center.y + count + 1):
		for x in range(center.x - count, center.x + count + 1):
			result.append_array(_insect_site_bins.get(Vector2i(x, z), []))
	# The reference scans habitat IDs ascending; retain its exact equal-score tie.
	result.sort()
	return result


func _ground_feeding(id: int, dt: float, event_time: float, eaten: float, requested: float) -> void:
	var d: ForestAnimalDefinition = definitions[species[id]]
	var rooted := false
	if habitat != null and d.rooting_pressure_day > 0 and eaten > 0:
		rooted = habitat.root_at(
			positions[id],
			(
				d.rooting_pressure_day
				* dt
				/ ForestClimate.DAY_S
				* minf(1, eaten / maxf(requested, 1e-12))
			)
		)
	_set_action(id, "root" if rooted else "eat", event_time)


func _assimilate_meal(id: int, food: Vector3) -> void:
	var d: ForestAnimalDefinition = definitions[species[id]]
	var assimilated := food * d.assimilation_fraction
	biomass_c[id] += assimilated.x
	biomass_n[id] += assimilated.y
	biomass_p[id] += assimilated.z
	_record_consumed(food)
	life_records[id].consumed_c_kg += food.x
	_deposit(id, food - assimilated)


func establish_homes() -> void:
	for id in species.size():
		home_positions[id] = _find_home(id)


func _find_home(id: int) -> Vector3:
	var d: ForestAnimalDefinition = definitions[species[id]]
	var best := positions[id]
	var score := INF
	for p in _nearby(positions[id], d.sense_radius_m):
		var plant_trait: ForestPlantDefinition = land.settings.plants[plants.species[p]]
		if (
			not (
				plants.alive[p]
				and plant_trait.reference_height_m * plants.size[p] >= d.cover_minimum_height_m
			)
			and not plants.fallen[p]
		):
			continue
		var point: Vector3 = plants.positions[p] + Vector3(.6, 0, .4)
		point.x = clampf(point.x, 1, land.settings.extent - 1)
		point.z = clampf(point.z, 1, land.settings.extent - 1)
		point.y = land.height_at(point.x, point.z)
		var distance: float = point.distance_to(positions[id]) * (.5 if plants.fallen[p] else 1.0)
		if _dry(point, d) and distance < score:
			best = point
			score = distance
	return best


func _home_action(id: int, dt: float, event_time: float, d: ForestAnimalDefinition) -> void:
	var direction := home_positions[id] - positions[id]
	direction.y = 0
	if direction.length() > d.bite_reach_m:
		var moved := _move(
			id, direction.normalized(), minf(direction.length(), d.movement_m_biological_s * dt)
		)
		_set_action(id, "seek_cover" if moved else "blocked", event_time)
	else:
		_set_action(id, "shelter", event_time)
		life_records[id].rested_s += dt
		fatigue[id] = maxf(0, fatigue[id] - dt / d.resting_bout_s)
