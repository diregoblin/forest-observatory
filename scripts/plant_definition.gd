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
@export var flower_start_day := 135.0
@export var flower_duration_days := 24.0
@export var insect_pollinated := false
@export var fruit_bearing := false
@export var fruit_start_day := 220.0
@export var fruit_duration_days := 65.0
@export var reproduction_per_year := 0.2
@export var dispersal_m := 8.0
@export var germination_fraction := .12
@export_range(0, 1) var nurse_log_affinity := 0.0
@export_range(0, 1) var snow_retention := .25
@export_range(0, 1) var trampling_resistance := .3
@export var recruitment_light := .15
@export var weight := 1.0
# Initial community affinities: forest / clearing / wet meadow / sandy shore.
# Scenario placement only, not a runtime survival gate or a calibrated niche.
@export var initial_habitat_weights := Vector4(1, 1, 1, 1)
@export var scale_range := Vector2(.72, 1.5)
@export var minimum_channel_distance := 14.0
@export var wind_strength := .015
# Presentation traits only; no extra biomass, RNG consumption or save state.
@export var canopy_texture: Texture2D
@export var canopy_leaf_span_m := .12
@export var canopy_color := Color(.40, .49, .43)
@export_range(0, 4) var canopy_layers := 0
@export_range(0, 1) var bark_markings := 0.0
@export var branch_radius_m := 0.0
@export_range(0, 1) var branch_droop := .1
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
@export var leaf_mass_fraction := .04  # Subset of live biomass, not another carbon owner.
@export var mycorrhiza_type: StringName = &"none"
@export var propagule_kind: StringName = &"seed"


func validate() -> void:
	for module in modules:
		assert(module.mesh != null and module.count > 0 and module.whorls > 0)
		assert(module.leaf_count >= 0 and module.leaflet_pairs >= 0)
		assert(module.leaf_size.x > 0 and module.leaf_size.y > 0)
		assert(module.bend.is_finite() and module.tip_offset.is_finite())
		assert(module.shape != "shoot" or module.mesh is CylinderMesh)
	assert(canopy_leaf_span_m > 0 and canopy_layers >= 0 and canopy_layers <= 4)
	assert(branch_radius_m >= 0 and branch_droop >= 0 and branch_droop <= 1)
	assert(canopy_layers == 0 or canopy_texture != null)
	assert(initial_habitat_weights.is_finite())
	for affinity in 4:
		assert(initial_habitat_weights[affinity] >= 0)
	assert(nurse_log_affinity >= 0 and nurse_log_affinity <= 1)
	assert(snow_retention >= 0 and snow_retention <= 1)
	assert(trampling_resistance >= 0 and trampling_resistance <= 1)
	assert(flower_start_day >= 1 and flower_start_day <= 365 and flower_duration_days > 0)
	assert(fruit_start_day >= 1 and fruit_start_day <= 365 and fruit_duration_days > 0)
	assert(growth_form in [&"tree", &"shrub", &"dwarf_shrub", &"herb", &"grass"])
	assert(leaf_mass_fraction >= 0 and leaf_mass_fraction <= .7)
	assert(mycorrhiza_type in [&"none", &"ecto", &"arbuscular", &"ericoid"])
	assert(propagule_kind in [&"seed", &"spore"])
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
