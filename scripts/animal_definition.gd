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
@export var initial_age_years := 1.0
@export var initial_elements := Vector3(1.2, .12, .012)  # kg C, N, P.
@export var minimum_body_carbon_kg := .8
@export var maximum_body_carbon_kg := 1.5
@export var assimilation_fraction := .6
@export var intake_carbon_kg_day := .16
# Minimum useful available edible reserve at a patch, not a minimum dt/bite.
# Prevents spending days on vanishing asymptotic remnants; stocks stay in plants.
@export var minimum_edible_carbon_kg := .00008
@export var basal_carbon_kg_day := .045
@export var movement_carbon_kg_m := .00008
@export var carbon_energy_kj_kg := 40000.0
@export var hungry_fraction := .78
@export var lifespan_years := 9.0
@export var sense_radius_m := 12.0
@export var bite_reach_m := 1.0
@export var cover_minimum_height_m := 1.2
@export var flood_depth_m := .12
@export var max_slope := 1.0
@export var action_step_s := 900.0
@export var movement_m_biological_s := .0006  # Compressed scenario: 51.84 m / biological day.
@export var maximum_segment_m := .6
@export var selection_radius_m := .48
@export var selection_height_m := .92
# A population/reproduction model is intentionally not silently enabled here.
@export var reproduction_enabled := false
# Shared primitive builder; every species supplies morphology, not renderer branches.
@export var part_shapes := PackedStringArray()
@export var part_dimensions: Array[Vector3] = []
@export var part_offsets: Array[Vector3] = []
@export var part_rotations: Array[Vector3] = []
@export var part_colors: Array[Color] = []


func validate() -> void:
	assert(not str(species_id).is_empty() and initial_count >= 0)
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
	assert(sense_radius_m > bite_reach_m and bite_reach_m > 0)
	assert(flood_depth_m >= 0 and max_slope > 0 and action_step_s > 0)
	assert(movement_m_biological_s >= 0 and maximum_segment_m > 0)
	assert(selection_radius_m > 0 and selection_height_m > 0)
	assert(
		not reproduction_enabled, "Reproduction is not implemented; do not claim a population model"
	)
	for values in [part_dimensions, part_offsets, part_rotations, part_colors]:
		assert(values.size() == part_shapes.size())
	for i in part_shapes.size():
		assert(part_shapes[i] in ["ellipsoid", "box", "cylinder", "cone"])
		assert(part_dimensions[i].x > 0 and part_dimensions[i].y > 0 and part_dimensions[i].z > 0)
