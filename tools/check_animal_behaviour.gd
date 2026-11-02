extends "res://tools/check_population.gd"


class FloodedExit:
	extends RefCounted
	var depth := PackedFloat64Array([0, 1])
	var center := Vector3.ZERO

	func index_at(x: float, z: float) -> int:
		# Straight away from the predator is flooded; oblique exits remain dry.
		return 1 if x < center.x - .1 and absf(z - center.z) < .1 else 0


func sleeper(hour: float) -> Dictionary:
	var w := chamber()
	w.animals.land.settings.start_hour = hour
	var d = w.animals.definitions[0]
	d.sleep_duration_h = 6
	d.sleep_start_hour = 10
	d.sleep_phase_spread_h = 0
	w.animals.positions[0] = w.plants.positions[0]
	w.animals.home_positions[0] = w.animals.positions[0]
	w.animals.biomass_c[0] = d.maximum_body_carbon_kg - .001
	w.animals._metabolize(0, 0)
	return w


func _run() -> void:
	var w := sleeper(12)
	var initial := total(w)
	var position: Vector3 = w.animals.positions[0]
	var food: Vector3 = w.plants.element_totals()
	var carbon: float = w.animals.biomass_c[0]
	w.animals.step(900)
	assert(w.animals.actions[0] == "sleep" and w.animals.positions[0] == position)
	assert(w.plants.element_totals() == food and w.animals.biomass_c[0] < carbon)
	var d = w.animals.definitions[0]
	assert(
		(
			absf(
				(
					carbon
					- w.animals.biomass_c[0]
					- (
						d.basal_carbon_kg_day
						* d.sleep_metabolism_fraction
						* 900
						/ ForestClimate.DAY_S
					)
				)
			)
			< 1e-10
		)
	)
	assert((total(w) - initial).length() < 2e-6)
	var clone := sleeper(12)
	assert(clone.animals.restore(w.animals.snapshot()))
	clone.soil.elements = w.soil.elements
	for candidate in [w, clone]:
		candidate.animals.step(26280)
	assert(w.animals.snapshot() == clone.animals.snapshot(), "Sleep continuation is exact")
	var returning := sleeper(12)
	returning.animals.home_positions[0] += Vector3(3,0,0)
	returning.animals.home_positions[0].y = returning.animals.land.height_at(returning.animals.home_positions[0].x, returning.animals.home_positions[0].z)
	var home_distance: float = returning.animals.positions[0].distance_to(returning.animals.home_positions[0])
	returning.animals.step(900)
	assert(returning.animals.actions[0] in ["seek_cover","blocked"])
	assert(returning.animals.positions[0].distance_to(returning.animals.home_positions[0]) < home_distance, "Sleep starts with a real journey home")
	var night := sleeper(0)
	night.animals.step(900)
	assert(
		night.animals.actions[0] != "sleep", "Same well-fed animal wakes outside its solar window"
	)
	# Crossing a window endpoint uses the actual world solar clock, not biological days.
	var dawn := sleeper(15.997)
	dawn.animals.step(900)
	assert(dawn.animals.actions[0] == "sleep")
	dawn.animals.step(900)
	assert(dawn.animals.actions[0] != "sleep")
	assert(
		(
			absf(
				(
					w.animals.solar_hour(w.animals.elapsed_s)
					- fposmod(
						(
							12
							+ (
								w.animals.elapsed_s
								* w.animals.land.settings.day_speed_multiplier
								/ w.animals.land.settings.year_speed_multiplier
								/ 3600
							)
						),
						24
					)
				)
			)
			< 1e-10
		)
	)
	# Hunger interrupts sleep and cannot immediately send a half-fed animal back to bed.
	w.animals.biomass_c[0] = (
		d.minimum_body_carbon_kg + .3 * (d.maximum_body_carbon_kg - d.minimum_body_carbon_kg)
	)
	w.animals._metabolize(0, 0)
	w.animals.step(900)
	assert(w.animals.actions[0] == "eat")
	for tick in 10:
		w.animals.step(900)
		assert(w.animals.actions[0] != "sleep")
	var flight := population(true, true)
	var animals: ForestAnimals = flight.animals
	var prey = animals.definitions[0]
	prey.movement_m_biological_s = .00015
	prey.sleep_duration_h = 6
	prey.sleep_start_hour = 10
	prey.sleep_phase_spread_h = 0
	animals.definitions[1].movement_m_biological_s = 0
	animals.positions[0] = flight.plants.positions[0]
	animals.positions[2] = animals.positions[0] + Vector3(8, 0, 0)
	animals.positions[2].y = animals.land.height_at(animals.positions[2].x, animals.positions[2].z)
	animals.actions[0] = "sleep"
	animals.actions[2] = "rest"
	var before: Vector3 = animals.positions[0]
	var distance := before.distance_to(animals.positions[2])
	var flight_budget := total(flight)
	animals.step(900)
	assert(
		animals.actions[0] == "flee",
		"A resting fox at eight metres is not ignored; danger wakes prey"
	)
	assert(animals.positions[0].distance_to(animals.positions[2]) > distance)
	assert(animals.alarm_remaining[0] > 0)
	# Move the predator out of sensing range: the remembered location is retained.
	animals.positions[2] += Vector3(100, 0, 0)
	var memory: Vector3 = animals.danger_positions[0]
	animals.step(900)
	assert(animals.actions[0] == "flee" and animals.danger_positions[0] == memory)
	assert(animals.restore(animals.snapshot()), "Alarm arrays and sleep actions round-trip")
	var saved := animals.snapshot()
	for mode in ["timer", "position", "clock"]:
		var corrupt := saved.duplicate(true)
		match mode:
			"timer":
				corrupt.alarm_remaining[0] = INF
			"position":
				corrupt.danger_positions[0] = Vector3(NAN, 0, 0)
			"clock":
				corrupt.configuration.day_multiplier *= 2
		assert(not animals.restore(corrupt) and animals.snapshot() == saved)
	# Explicitly test memory expiry rather than permitting permanent panic.
	animals.alarm_remaining[0] = 100
	animals.step(900)
	assert(animals.alarm_remaining[0] == 0 and animals.actions[0] != "flee")
	assert((total(flight) - flight_budget).length() < 1e-5)
	# Counter-control: a predator beyond the sensing radius causes no omniscient panic.
	var distant := population(true, true)
	distant.animals.positions[2] += Vector3(100, 0, 0)
	distant.animals.step(900)
	assert(distant.animals.actions[0] != "flee" and distant.animals.alarm_remaining[0] == 0)
	var detour := population(true, true)
	detour.animals.definitions[0].movement_m_biological_s = .00015
	detour.animals.definitions[0].max_slope = 100  # Isolate the water obstacle, not terrain slope.
	var obstacle := FloodedExit.new()
	obstacle.center = detour.animals.positions[0]
	detour.animals.water = obstacle
	detour.animals.positions[2] = obstacle.center + Vector3(8, 0, 0)
	var away_before: float = obstacle.center.distance_to(detour.animals.positions[2])
	detour.animals.step(900)
	assert(absf(detour.animals.positions[0].z - obstacle.center.z) > .1)
	assert(
		detour.animals.positions[0].distance_to(detour.animals.danger_positions[0]) > away_before
	)
	assert(obstacle.index_at(detour.animals.positions[0].x, detour.animals.positions[0].z) == 0)
	var visible_run := population(true, true)
	visible_run.animals.definitions[0].movement_m_biological_s = .00015
	visible_run.animals.positions[0] = visible_run.plants.positions[0]
	visible_run.animals.positions[2] = visible_run.animals.positions[0] + Vector3(10, 0, 0)
	assert(visible_run.animals._concealed(0), "Quiet prey has actual local plant cover")
	visible_run.animals.step(900)
	assert(visible_run.animals.actions[0] == "flee" and not visible_run.animals._concealed(0))
	assert(
		visible_run.animals.actions[2] == "hunt",
		"Fleeing prey is noticeable beyond stationary-cover range"
	)
	var report := {
		"passed": true,
		"solar_sleep_and_wake": true,
		"stationary_sleep_but_finite_metabolism": true,
		"sleep_continuation_exact": true,
		"hunger_wake_with_refeeding_hysteresis": true,
		"resting_predator_not_ignored": true,
		"danger_wakes_prey_and_increases_distance": true,
		"finite_local_threat_memory": true,
		"distant_predator_negative_control": true,
		"flooded_direct_escape_uses_dry_detour": true,
		"moving_prey_not_invisibly_concealed": true,
		"corrupt_memory_atomic_rejection": true,
		"cnp_conserved": true,
		"boundary": "Deterministic scenario behavior, not calibrated ethology"
	}
	FileAccess.open("res://artifacts/animal-behaviour-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("ANIMAL_BEHAVIOUR_CHECK ", JSON.stringify(report))
	quit()
