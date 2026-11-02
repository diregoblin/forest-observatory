class_name ForestSettings
extends Resource

@export var seed := 29017
@export var extent := 512.0
@export var terrain_resolution := 512
@export var water_resolution := 128
@export var water_step := 1.0  # Requested model seconds; native CFL may subdivide.
@export var water_cfl := 0.35
@export var manning_n := 0.055  # s / m^(1/3)
@export var water_theta := 0.8  # Parallel-face momentum weighting.
@export var max_froude := 1.0  # Declared local-inertial regime limit, not full SWE.
@export var rainfall_m_s := 30.0 / 1000.0 / 3600.0
@export var headwater_m3_s := 2.0
@export var headwater_length := 12.0
@export var headwater_width := 14.0
@export var soil_interval_s := 30.0
@export var soil_profile: ForestSoilProfile = preload("res://data/soils/loam.tres")
@export var evaporation_m_s := 0.12 / 1000.0 / 3600.0
@export var water_display_interval_s := 0.1  # Wall time; never a physics coefficient.
@export var dam_fraction := .61
@export var dam_width := 44.0
@export var dam_height := 2.7
@export var tree_attempts := 4600
@export var grass_attempts := 22000
@export_range(0.0, 1.0) var initial_fallen_fraction := 0.0  # Fraction of placed trees, not herbs.
@export var ecology_interval := 86400.0  # Groundcover interval in biological seconds.
@export var initial_speed := 1.0  # Shared requested water seconds per wall second.
@export var day_speed_multiplier := 360.0  # Solar seconds per hydrological second.
@export var year_speed_multiplier := 13140.0  # Biological seconds per hydrological second.
@export var ecology_step_s := 0.5  # Shared fixed tick in hydrological SI seconds.
@export var start_day := 135.0  # 15 May of a 365-day scenario year.
@export var start_hour := 12.0
@export var latitude_deg := 60.0
@export var optimum_soil_moisture := .65
@export var moisture_penalty := 1.7
@export var flood_tolerance := .15
@export var flood_biomass := .03
@export var growth_per_tick := .018
@export var fungus: ForestFungusDefinition = preload("res://data/fungi/fairy_ring.tres")
@export var fungal_species: Array[Resource] = []
@export var fungi_resolution := 128
@export var fungi_cell_m := .25
@export var fungi_plot_centers := PackedVector2Array(
	[Vector2(.375, .557), Vector2(.70, .30), Vector2(.20, .78)]
)
@export var fungi_initial_age_s := 120.0 * 30.0 * 86400.0
@export var plants: Array[Resource] = []


func validate() -> void:
	assert(extent > 0 and terrain_resolution > 0 and water_resolution > 1)
	assert(
		(
			is_finite(initial_fallen_fraction)
			and initial_fallen_fraction >= 0
			and initial_fallen_fraction <= 1
		)
	)
	assert(water_step > 0 and water_step <= 5)
	assert(water_cfl > 0 and water_cfl <= .5 and manning_n > 0)
	assert(water_theta >= 0 and water_theta <= 1 and max_froude > 0)
	assert(rainfall_m_s >= 0 and headwater_m3_s >= 0 and evaporation_m_s >= 0)
	assert(soil_interval_s > 0 and water_display_interval_s > 0)
	soil_profile.validate()
	assert(ecology_interval > 0 and growth_per_tick > 0)
	assert(is_finite(initial_speed) and initial_speed > 0)
	assert(is_finite(day_speed_multiplier) and day_speed_multiplier > 0)
	assert(is_finite(year_speed_multiplier) and year_speed_multiplier > 0)
	assert(is_finite(ecology_step_s) and ecology_step_s > 0 and ecology_step_s <= water_step)
	# Solar geometry is analytic/interpolated; only biological resolution limits ticks.
	assert(ecology_step_s <= year_water_s() / 365.0)
	assert(start_hour >= 0 and start_hour < 24)
	assert(start_day >= 1 and start_day < 366 and absf(latitude_deg) < 89)
	assert(dam_fraction > 0 and dam_fraction < 1 and dam_width > 0)
	assert(not plants.is_empty())
	fungus.validate()
	for definition in fungal_species:
		assert(definition is ForestFungusDefinition)
		definition.validate()
	assert(fungi_resolution >= 16 and fungi_resolution <= 512 and fungi_cell_m > 0)
	assert(fungi_resolution * fungi_cell_m <= extent and fungi_initial_age_s >= 0)
	assert(not fungi_plot_centers.is_empty())
	for center in fungi_plot_centers:
		assert(center.x >= 0 and center.x <= 1 and center.y >= 0 and center.y <= 1)
	var identities := {}
	for plant in plants:
		assert(plant is ForestPlantDefinition and plant.weight > 0)
		plant.validate()
		assert(not identities.has(plant.species_id), "Duplicate species id")
		identities[plant.species_id] = true


func day_water_s() -> float:
	return ForestClimate.DAY_S / day_speed_multiplier


func fungus_for_plot(index: int) -> ForestFungusDefinition:
	return fungus if fungal_species.is_empty() else fungal_species[index % fungal_species.size()]


func year_water_s() -> float:
	return ForestClimate.YEAR_S / year_speed_multiplier
