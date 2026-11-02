class_name ForestFungusDefinition
extends Resource

## Species identity and functional guild; numeric kinetics remain illustrative.
@export var species_id := &"marasmius_oreades"
@export var display_name := "Опёнок луговой"
@export var latin_name := "Marasmius oreades"
@export var trophic_type: StringName = &"saprotroph"
@export var source_url := "https://www.first-nature.com/fungi/marasmius-oreades.php"
@export var exchange_radius_m := 4.0
@export var cap_profile: StringName = &"dome"
@export var stem_radius_m := .019
@export var cap_height_ratio := .65
@export var resource_capacity_kg_m2 := .05
@export var length_scale_m := .125
@export var time_scale_s := 30.0 * 86400.0
@export var mortality_s := .0475 / (30.0 * 86400.0)
@export var replenishment_s := .0075 / (30.0 * 86400.0)
@export var diffusion_ratio := 2.0
@export var initial_litter_kg_m2 := .6
@export var fruiting_s := .001 / 86400.0
@export var fruit_lifetime_s := 10.0 * 86400.0
@export var fruit_threshold_kg_m2 := .005
@export var initial_fruit_fraction := .025
@export var representative_body_kg := .00005
@export var cap_radius_m := .11
@export var stem_height_m := .19
@export var cap_color := Color(.70, .40, .17)
@export var stem_color := Color(.88, .81, .63)


func options(finite_litter := true, fruiting := true) -> Dictionary:
	return {
		"diffusion_b_m2_s": length_scale_m * length_scale_m / time_scale_s,
		"diffusion_r_m2_s": diffusion_ratio * length_scale_m * length_scale_m / time_scale_s,
		"uptake_m4_kg2_s": 1.0 / (resource_capacity_kg_m2 * resource_capacity_kg_m2 * time_scale_s),
		"mortality_s": mortality_s,
		"replenishment_s": replenishment_s,
		"resource_capacity_kg_m2": resource_capacity_kg_m2,
		"yield": 1.0,
		"fruiting_s": fruiting_s if fruiting else 0.0,
		"fruit_lifetime_s": fruit_lifetime_s,
		"fruit_threshold_kg_m2": fruit_threshold_kg_m2,
		"max_step_s": .2 * time_scale_s,
		"finite_litter": finite_litter,
		"ectomycorrhizal": finite_litter and trophic_type == &"ectomycorrhizal"
	}


func validate() -> void:
	assert(trophic_type in [&"saprotroph", &"ectomycorrhizal"])
	assert(cap_profile in [&"dome", &"funnel"] and exchange_radius_m > 0)
	assert(stem_radius_m > 0 and cap_height_ratio > 0)
	assert(resource_capacity_kg_m2 > 0 and length_scale_m > 0 and time_scale_s > 0)
	assert(mortality_s >= 0 and replenishment_s >= 0 and diffusion_ratio > 0)
	assert(initial_litter_kg_m2 >= 0 and fruiting_s >= 0 and fruit_lifetime_s > 0)
	assert(initial_fruit_fraction >= 0 and initial_fruit_fraction <= .1)
	assert(representative_body_kg > 0 and cap_radius_m > 0 and stem_height_m > 0)
