class_name ForestPlantDefinition
extends Resource

## A new species is a resource, not another branch in rendering or placement.
@export var species_id: StringName
@export var display_name := ""
@export var latin_name := ""
@export_multiline var description := ""
@export var source_url := ""
@export var growth_form: StringName = &"tree"
@export var life_cycle: StringName = &"perennial"
@export var initial_age_years := Vector2(8, 40)
@export var biomass_kg_c := 40.0  # Scenario carbon at size=1, not measured allometry.
@export var cn_ratio := 40.0
@export var cp_ratio := 500.0
@export var dead_decay_per_year := 0.12
@export var edible_fraction := 0.0
@export var mature_age_years := 8.0
@export var seed_cost_kg_c := 0.002
@export var reproduction_per_year := 0.2
@export var dispersal_m := 8.0
@export var germination_fraction := .12
@export var recruitment_light := .15
@export var weight := 1.0
@export var scale_range := Vector2(.72, 1.5)
@export var minimum_channel_distance := 14.0
@export var wind_strength := .015
@export var modules: Array[ForestPlantModule] = []
@export var deciduous := false
@export var leaf_on_day := 110.0
@export var leaf_off_day := 260.0
@export var leaf_transition_days := 30.0
@export var autumn_color := Color(.95, .62, .12)
@export var reference_height_m := 12.0
@export var max_height_m := 32.0
@export var crown_radius_m := 3.0
@export var height_growth_m_year := 0.65
@export var transpiration_m_s := 2.0 / 1000.0 / 86400.0
@export var minimum_light := 0.08
@export var flood_depth_m := 0.25
@export var stress_days := 16.0
@export var recovery_days := 8.0
@export var lethal_stress := 0.95
@export var lifespan_years := 200.0


func validate() -> void:
	assert(growth_form in [&"tree", &"shrub", &"dwarf_shrub", &"herb", &"grass"])
	assert(life_cycle in [&"annual", &"biennial", &"perennial"])
	assert(initial_age_years.x >= 0 and initial_age_years.y >= initial_age_years.x)
	assert(biomass_kg_c > 0 and cn_ratio > 0 and cp_ratio > 0)
	assert(is_finite(dead_decay_per_year) and dead_decay_per_year >= 0)
	assert(edible_fraction >= 0 and edible_fraction <= 1)
	assert(mature_age_years >= 0 and seed_cost_kg_c > 0 and reproduction_per_year >= 0)
	assert(dispersal_m >= 0 and germination_fraction >= 0 and germination_fraction <= 1)
	assert(recruitment_light >= 0 and recruitment_light < 1)
	assert(reference_height_m > 0 and max_height_m >= reference_height_m * scale_range.y)
	assert(crown_radius_m > 0 and height_growth_m_year >= 0 and transpiration_m_s >= 0)
	assert(minimum_light >= 0 and minimum_light < 1 and flood_depth_m > 0)
	assert(stress_days > 0 and recovery_days > 0 and lethal_stress > 0 and lethal_stress <= 1)
	assert(lifespan_years > 0 and scale_range.x > 0 and scale_range.y >= scale_range.x)
	assert(leaf_on_day > 0 and leaf_transition_days > 0)
	assert(
		(
			leaf_off_day > leaf_on_day + leaf_transition_days
			and leaf_off_day + leaf_transition_days <= 365
		)
	)
