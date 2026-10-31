class_name ForestAnimals
extends RefCounted

## One resource-driven herbivore model. Index is retained as the stable ID, even
## after death. All movements are executed here, never in the view.
const DEFAULT = preload("res://data/animals/hare.tres")
const BIN_M := 8.0
const HISTORY_LIMIT := 16
var land: ForestLandscape
var plants
var water
var soil
var definitions: Array = []
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
var targets := PackedInt32Array()
var wander_yaw := PackedFloat64Array()
var histories: Array = []
var path_history: Array = []  # Per tick: {times: PackedFloat64Array, points: PackedVector3Array}.
var bins := {}
var rng := RandomNumberGenerator.new()
var elapsed_s := 0.0
var ticks := 0
var revision := 0
var total_distance_m := 0.0
var respired_c_kg := 0.0
var consumed_cnp := Vector3.ZERO
var excreted_cnp := Vector3.ZERO
var carcass_to_soil_cnp := Vector3.ZERO
var initial_cnp := Vector3.ZERO
var deaths := 0
var decision_checks := 0


func _init(
	l: ForestLandscape, plant_model, water_model, soil_model, species_definitions: Array = []
) -> void:
	land = l
	plants = plant_model
	water = water_model
	soil = soil_model
	definitions = (
		species_definitions.duplicate() if not species_definitions.is_empty() else [DEFAULT]
	)
	rng.seed = land.settings.seed + 41873
	var identities := {}
	for definition in definitions:
		definition.validate()
		assert(not identities.has(definition.species_id))
		identities[definition.species_id] = true
	_rebuild_bins()
	var observation := land.settings.fungi_plot_centers[0] * land.settings.extent
	for s in definitions.size():
		for _individual in definitions[s].initial_count:
			var spawn := _spawn_position(observation, definitions[s])
			_append_animal(s, spawn)
	initial_cnp = element_totals()


func _append_animal(s: int, position: Vector3) -> void:
	var definition: ForestAnimalDefinition = definitions[s]
	species.append(s)
	positions.append(position)
	previous_positions.append(position)
	yaw.append(0)
	age_years.append(definition.initial_age_years)
	biomass_c.append(definition.initial_elements.x)
	biomass_n.append(definition.initial_elements.y)
	biomass_p.append(definition.initial_elements.z)
	energy_kj.append(
		(
			(definition.initial_elements.x - definition.minimum_body_carbon_kg)
			* definition.carbon_energy_kj_kg
		)
	)
	alive.append(1)
	actions.append("rest")
	targets.append(-1)
	wander_yaw.append(rng.randf() * TAU)
	histories.append([])
	path_history.append(
		{"times": PackedFloat64Array([0]), "points": PackedVector3Array([position])}
	)
	_event(species.size() - 1, "initial", "Заданное начальное состояние")


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
		if d < distance and _dry(plants.positions[id], definition):
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
		if _dry(candidate, definition):
			return candidate
	# Explicit fallback initial condition; model immediately reports blocked state.
	origin.y = land.height_at(origin.x, origin.z)
	return origin


func _rebuild_bins() -> void:
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
	return _edible_carbon(id) >= definition.minimum_edible_carbon_kg


func step(biological_dt: float) -> void:
	assert(is_finite(biological_dt) and biological_dt > 0)
	_rebuild_bins()  # Once per shared tick, not every locomotion substep.
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
				dt = minf(dt, definition.maximum_segment_m / definition.movement_m_biological_s)
		for id in species.size():
			if alive[id]:
				_act(id, dt, elapsed_s + progressed)
				age_years[id] += dt / ForestClimate.YEAR_S
				_metabolize(id, dt)
				if (
					biomass_c[id] <= definitions[species[id]].minimum_body_carbon_kg + 1e-12
					or age_years[id] >= definitions[species[id]].lifespan_years
				):
					_die(id, elapsed_s + progressed + dt)
			path_history[id].times.append(progressed + dt)
			path_history[id].points.append(positions[id])
		progressed += dt
	elapsed_s += biological_dt
	ticks += 1
	revision += 1


func _act(id: int, dt: float, event_time: float) -> void:
	var definition: ForestAnimalDefinition = definitions[species[id]]
	var reserve_fraction := (
		(biomass_c[id] - definition.minimum_body_carbon_kg)
		/ (definition.maximum_body_carbon_kg - definition.minimum_body_carbon_kg)
	)
	var hungry := reserve_fraction < definition.hungry_fraction
	var target := -1
	var score := INF
	for plant_id in _nearby(positions[id], definition.sense_radius_m):
		decision_checks += 1
		if not plants.alive[plant_id]:
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
			_set_action(id, "eat", event_time)
			var request := minf(
				definition.intake_carbon_kg_day * dt / ForestClimate.DAY_S,
				(
					(definition.maximum_body_carbon_kg - biomass_c[id])
					/ definition.assimilation_fraction
				)
			)
			request = minf(request, _edible_carbon(target))
			var food: Vector3 = plants.harvest(target, maxf(0, request))
			assert(food.x >= 0 and food.y >= 0 and food.z >= 0 and food.x <= request + 1e-6)
			var assimilated := food * definition.assimilation_fraction
			biomass_c[id] += assimilated.x
			biomass_n[id] += assimilated.y
			biomass_p[id] += assimilated.z
			consumed_cnp += food
			_deposit(id, food - assimilated)
		else:
			_set_action(id, "shelter", event_time)
		return
	if not hungry and target < 0:
		_set_action(id, "rest", event_time)
		return
	var direction: Vector3
	if target >= 0:
		direction = plants.positions[target] - positions[id]
	else:
		wander_yaw[id] += rng.randf_range(-.3, .3)
		direction = Vector3(sin(wander_yaw[id]), 0, cos(wander_yaw[id]))
	direction.y = 0
	direction = direction.normalized()
	var moved := _move(id, direction, definition.movement_m_biological_s * dt)
	_set_action(id, ("seek_food" if hungry else "seek_cover") if moved else "blocked", event_time)


func _move(id: int, direction: Vector3, maximum_distance: float) -> bool:
	var definition: ForestAnimalDefinition = definitions[species[id]]
	for angle in [0.0, .785398, -.785398, 1.570796, -1.570796]:
		var candidate := positions[id] + direction.rotated(Vector3.UP, angle) * maximum_distance
		if (
			candidate.x <= 0
			or candidate.z <= 0
			or candidate.x >= land.settings.extent
			or candidate.z >= land.settings.extent
		):
			continue
		candidate.y = land.height_at(candidate.x, candidate.z)
		if absf(candidate.y - positions[id].y) > maximum_distance * definition.max_slope:
			continue
		if (
			not _dry(candidate, definition)
			or not _dry(positions[id].lerp(candidate, .5), definition)
		):
			continue
		var distance := (
			Vector2(candidate.x - positions[id].x, candidate.z - positions[id].z).length()
		)
		positions[id] = candidate
		yaw[id] = atan2(direction.x, direction.z) + angle
		total_distance_m += distance
		var carbon := minf(biomass_c[id], distance * definition.movement_carbon_kg_m)
		biomass_c[id] -= carbon
		respired_c_kg += carbon
		return distance > 0
	return false


func _dry(position: Vector3, definition: ForestAnimalDefinition) -> bool:
	return water.depth[water.index_at(position.x, position.z)] <= definition.flood_depth_m


func _metabolize(id: int, dt: float) -> void:
	var definition: ForestAnimalDefinition = definitions[species[id]]
	var carbon := minf(biomass_c[id], definition.basal_carbon_kg_day * dt / ForestClimate.DAY_S)
	biomass_c[id] -= carbon
	respired_c_kg += carbon
	energy_kj[id] = (
		maxf(0, biomass_c[id] - definition.minimum_body_carbon_kg) * definition.carbon_energy_kj_kg
	)
	# Excess assimilated N/P cannot accumulate forever as fictitious animal growth.
	var excess := Vector3(
		0,
		maxf(0, biomass_n[id] - definition.initial_elements.y),
		maxf(0, biomass_p[id] - definition.initial_elements.z)
	)
	biomass_n[id] -= excess.y
	biomass_p[id] -= excess.z
	_deposit(id, excess)


func _deposit(id: int, amount: Vector3) -> void:
	if amount.length_squared() > 0:
		soil.deposit(positions[id], amount, true)
		excreted_cnp += amount


func _die(id: int, event_time := -1.0) -> void:
	if not alive[id]:
		return
	var amount := Vector3(biomass_c[id], biomass_n[id], biomass_p[id])
	soil.deposit(positions[id], amount, true)
	carcass_to_soil_cnp += amount
	biomass_c[id] = 0
	biomass_n[id] = 0
	biomass_p[id] = 0
	energy_kj[id] = 0
	alive[id] = 0
	actions[id] = "dead"
	targets[id] = -1
	deaths += 1
	_event(id, "dead", "Биомасса передана почве ровно один раз", event_time)


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
		"eat": "ест",
		"shelter": "в укрытии",
		"seek_food": "ищет местный корм",
		"seek_cover": "идёт в укрытие",
		"blocked": "проход затоплен или слишком крут",
		"dead": "погибла"
	}
	var movement_note := (
		"Сценарно %.2f м / биологические сутки, не скорость бега"
		% (definition.movement_m_biological_s * ForestClimate.DAY_S)
	)
	return {
		"kind": "animal",
		"id": id,
		"stable_id": id,
		"species_id": definition.species_id,
		"title": definition.display_name,
		"subtitle": definition.latin_name,
		"display_name": definition.display_name,
		"latin_name": definition.latin_name,
		"description": definition.description,
		"source_url": definition.source_url,
		"life_cycle": definition.life_cycle,
		"age_years": age_years[id],
		"initial_age": true,
		"alive": bool(alive[id]),
		"stage": "взрослая особь" if alive[id] else "погибла",
		"state": actions[id],
		"action": actions[id],
		"position": positions[id],
		"energy_kj": energy_kj[id],
		"target_plant_id": targets[id],
		"elements_kg": Vector3(biomass_c[id], biomass_n[id], biomass_p[id]),
		"history": histories[id].duplicate(true),
		"selection_radius_m": definition.selection_radius_m,
		"selection_height_m": definition.selection_height_m,
		"movement_note": movement_note,
		"initial_age_source":
		"Начальный возраст задан сценарием; далее возрастает по общим биологическим часам",
		"details":
		{
			"Действие": labels.get(actions[id], actions[id]),
			"Энергия": "%.0f кДж" % energy_kj[id],
			"Корм": "Растение #%d" % targets[id] if targets[id] >= 0 else "Местный корм не выбран",
			"Шкала движения": movement_note,
			"Возраст": "Начальный возраст задан сценарием",
			"Размножение": "Пока не реализовано"
		},
		"reproduction": "не реализовано"
	}


func element_totals() -> Vector3:
	var total := Vector3.ZERO
	for id in species.size():
		total += Vector3(biomass_c[id], biomass_n[id], biomass_p[id])
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
		"reproduction_implemented": false
	}


func _configuration() -> Dictionary:
	var traits := []
	for definition in definitions:
		var values := {}
		for property in definition.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				values[property.name] = definition.get(property.name)
		traits.append(values)
	return {"seed": land.settings.seed, "extent": land.settings.extent, "definitions": traits}


func snapshot() -> Dictionary:
	var state := {"version": 1, "configuration": _configuration(), "rng_state": rng.state}
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
		"targets",
		"wander_yaw",
		"histories",
		"path_history",
		"elapsed_s",
		"ticks",
		"revision",
		"total_distance_m",
		"respired_c_kg",
		"consumed_cnp",
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
		state.get("version", 0) != 1
		or state.get("configuration", {}) != _configuration()
		or not state.get("rng_state") is int
	):
		return false
	for field in _state_fields():
		if not state.has(field) or typeof(state[field]) != typeof(get(field)):
			return false
	var count: int = state.species.size()
	if state.species != species:
		return false  # No reproduction/removal yet: identities cannot change through load.
	for field in [
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
		"targets",
		"wander_yaw",
		"histories",
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
	for field in ["consumed_cnp", "excreted_cnp", "carcass_to_soil_cnp", "initial_cnp"]:
		if not _valid_elements(state[field]):
			return false
	for id in count:
		if state.species[id] < 0 or state.species[id] >= definitions.size() or state.alive[id] > 1:
			return false
		for field in ["age_years", "energy_kj", "biomass_c", "biomass_n", "biomass_p"]:
			if not is_finite(state[field][id]) or state[field][id] < 0:
				return false
		for field in ["yaw", "wander_yaw"]:
			if not is_finite(state[field][id]):
				return false
		for field in ["positions", "previous_positions"]:
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
			in ["rest", "eat", "shelter", "seek_food", "seek_cover", "blocked", "dead"]
		):
			return false
		var definition: ForestAnimalDefinition = definitions[state.species[id]]
		var expected_energy := (
			maxf(0, state.biomass_c[id] - definition.minimum_body_carbon_kg)
			* definition.carbon_energy_kj_kg
		)
		if (
			absf(state.energy_kj[id] - expected_energy) > 1e-6
			or state.biomass_c[id] > definition.maximum_body_carbon_kg + 1e-6
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
