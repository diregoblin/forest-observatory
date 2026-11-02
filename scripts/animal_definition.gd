class_name ForestAnimalDefinition
extends Resource

## Scenario traits, not calibrated physiological or locomotion measurements.
@export var species_id: StringName
@export var display_name := ""
@export var latin_name := ""
@export_multiline var description := ""
@export var source_url := ""
@export var life_cycle := "Многолетнее животное"
@export var initial_count := 1
@export var founder_pair_spacing_m := 18.0
@export var initial_age_years := 1.0
@export var initial_elements := Vector3(1.2, .12, .012)  # kg C, N, P.
@export var minimum_body_carbon_kg := .8
@export var maximum_body_carbon_kg := 1.5
@export var assimilation_fraction := .6
@export var intake_carbon_kg_day := .24
# Minimum useful available edible reserve at a patch, not a minimum dt/bite.
# Prevents spending days on vanishing asymptotic remnants; stocks stay in plants.
@export var minimum_edible_carbon_kg := .00008
@export var basal_carbon_kg_day := .045
@export var movement_carbon_kg_m := .00008
@export var carbon_energy_kj_kg := 40000.0
@export var hungry_fraction := .78
@export var sated_fraction := .92
@export var feeding_bout_s := 21600.0
@export var resting_bout_s := 14400.0
@export var surveying_bout_s := 1800.0
@export var excursion_distance_m := 3.0
@export var lifespan_years := 9.0
@export var gait := "walk"
@export var home_range_m := 55.0
@export var shelter_kind := "лёжка"
@export var fruit_diet := false
@export var vegetation_fallback := false  # Fruit eaters may also consume existing plant biomass.
@export var rooting_pressure_day := 0.0  # Disturbance/day spent successfully feeding on the ground.
@export var insect_diet := false
@export var scavenges := false
@export var flight_height_m := 0.0
@export var can_swim := false
@export var swim_speed_fraction := .4
@export var swim_cost_multiplier := 2.5
@export var sense_radius_m := 12.0
@export var bite_reach_m := 1.0
@export var cover_minimum_height_m := 1.2
@export var flood_depth_m := .12
@export var max_slope := 1.0
@export var action_step_s := 900.0
@export var movement_m_biological_s := .00015  # Compressed scenario: 12.96 m / biological day.
@export var maximum_segment_m := .6
@export var selection_radius_m := .48
@export var selection_height_m := .92
@export var reproduction_enabled := false
@export var trophic_role: StringName = &"herbivore"
@export var prey_species: Array[StringName] = []
@export var escape_multiplier := 2.0
@export var chase_multiplier := 1.4
@export var capture_reach_m := .65
@export var hunting_bout_s := 172800.0
@export var hunting_rest_s := 43200.0
# Visible solar hours; biology retains the existing accelerated year clock.
@export var sleep_duration_h := 0.0
@export var sleep_start_hour := 9.0
@export var sleep_period_h := 24.0
@export var sleep_phase_spread_h := .75
@export var sleep_metabolism_fraction := .65
@export var sleep_wake_reserve_fraction := .35
@export var alarm_memory_s := 86400.0
@export var maturity_days := 120.0
@export var gestation_days := 30.0
@export var reproduction_cooldown_days := 60.0
@export var reproduction_reserve_fraction := .12
@export var litter_size := 2
@export var newborn_fraction := .16
@export var mating_radius_m := 12.0
@export var breeding_start_day := 60.0
@export var breeding_end_day := 245.0
# Shared primitive builder; every species supplies morphology, not renderer branches.
@export var part_shapes := PackedStringArray()
@export var part_dimensions: Array[Vector3] = []
@export var part_offsets: Array[Vector3] = []
@export var part_rotations: Array[Vector3] = []
@export var part_colors: Array[Color] = []
@export var part_roles := PackedStringArray()
## Optional anatomical hinges in the same local coordinates as offsets.
## Several pieces (ear lining, paw, tail tip, feathers) can share one hinge.
@export var part_pivots: Array[Vector3] = []
## Positive-X shoulder for articulated wings; mirrored for the left side.
@export var wing_shoulder := Vector3.ZERO


func validate() -> void:
	assert(not str(species_id).is_empty() and initial_count >= 0)
	assert(founder_pair_spacing_m > 0 and is_finite(founder_pair_spacing_m))
	assert(initial_age_years >= 0 and lifespan_years > initial_age_years)
	assert(
		(
			initial_elements.x > minimum_body_carbon_kg
			and initial_elements.y >= 0
			and initial_elements.z >= 0
		)
	)
	assert(maximum_body_carbon_kg >= initial_elements.x and minimum_body_carbon_kg > 0)
	assert(assimilation_fraction > 0 and assimilation_fraction <= 1)
	assert(intake_carbon_kg_day > 0 and basal_carbon_kg_day > 0 and movement_carbon_kg_m >= 0)
	assert(minimum_edible_carbon_kg > 0 and is_finite(minimum_edible_carbon_kg))
	assert(carbon_energy_kj_kg > 0 and hungry_fraction > 0 and hungry_fraction < 1)
	assert(sated_fraction > hungry_fraction and sated_fraction <= 1)
	assert(feeding_bout_s > 0 and resting_bout_s > 0 and surveying_bout_s > 0)
	assert(excursion_distance_m > bite_reach_m and excursion_distance_m < sense_radius_m)
	assert(home_range_m >= sense_radius_m and flight_height_m >= 0)
	assert(is_finite(rooting_pressure_day) and rooting_pressure_day >= 0)
	assert(rooting_pressure_day == 0 or flight_height_m == 0)
	assert(swim_speed_fraction > 0 and swim_speed_fraction <= 1 and swim_cost_multiplier >= 1)
	assert(sense_radius_m > bite_reach_m and bite_reach_m > 0)
	assert(flood_depth_m >= 0 and max_slope > 0 and action_step_s > 0)
	assert(movement_m_biological_s >= 0 and maximum_segment_m > 0)
	assert(selection_radius_m > 0 and selection_height_m > 0)
	assert(trophic_role in [&"herbivore", &"predator"])
	assert(trophic_role != &"predator" or not prey_species.is_empty())
	assert(escape_multiplier >= 1 and chase_multiplier >= 1 and capture_reach_m > 0)
	assert(hunting_bout_s > 0 and hunting_rest_s > 0)
	assert(is_finite(sleep_start_hour) and sleep_start_hour >= 0 and sleep_start_hour < 24)
	assert(is_finite(sleep_period_h) and sleep_period_h > 0 and sleep_period_h <= 24)
	assert(
		is_finite(sleep_duration_h) and sleep_duration_h >= 0 and sleep_duration_h < sleep_period_h
	)
	assert(
		(
			is_finite(sleep_phase_spread_h)
			and sleep_phase_spread_h >= 0
			and sleep_phase_spread_h < sleep_period_h
		)
	)
	assert(sleep_metabolism_fraction > 0 and sleep_metabolism_fraction <= 1)
	assert(sleep_wake_reserve_fraction > 0 and sleep_wake_reserve_fraction < hungry_fraction)
	assert(is_finite(alarm_memory_s) and alarm_memory_s > 0)
	assert(maturity_days > 0 and gestation_days > 0 and reproduction_cooldown_days > 0)
	assert(reproduction_reserve_fraction > 0 and reproduction_reserve_fraction < 1)
	assert(litter_size > 0 and litter_size <= 4 and newborn_fraction > 0 and newborn_fraction < 1)
	assert(mating_radius_m > 0 and breeding_start_day >= 1 and breeding_end_day <= 365)
	assert(breeding_end_day > breeding_start_day)
	assert(part_roles.is_empty() or part_roles.size() == part_shapes.size())
	assert(part_pivots.is_empty() or part_pivots.size() == part_shapes.size())
	assert(wing_shoulder.is_finite())
	if part_roles.has("flight_wing") or part_roles.has("flight_tip"):
		assert(wing_shoulder.x > 0 and not part_pivots.is_empty())
	for values in [part_dimensions, part_offsets, part_rotations, part_colors]:
		assert(values.size() == part_shapes.size())
	for i in part_shapes.size():
		assert(
			(
				part_shapes[i]
				in [
					"ellipsoid",
					"box",
					"cylinder",
					"cone",
					"barrel",
					"taper",
					"leaf",
					"plume",
					"feather"
				]
			)
		)
		assert(part_dimensions[i].x > 0 and part_dimensions[i].y > 0 and part_dimensions[i].z > 0)
		assert(part_offsets[i].is_finite() and part_rotations[i].is_finite())
		if not part_pivots.is_empty():
			assert(part_pivots[i].is_finite())
