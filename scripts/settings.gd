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
@export var ecology_interval := 60.0
@export var start_day := 135.0  # 15 May of a 365-day scenario year.
@export var latitude_deg := 60.0
@export var optimum_soil_moisture := .65
@export var moisture_penalty := 1.7
@export var flood_tolerance := .15
@export var flood_biomass := .03
@export var growth_per_tick := .018
@export var plants: Array[Resource] = []


func validate() -> void:
	assert(extent > 0 and terrain_resolution > 0 and water_resolution > 1)
	assert(water_step > 0 and water_step <= 5)
	assert(water_cfl > 0 and water_cfl <= .5 and manning_n > 0)
	assert(water_theta >= 0 and water_theta <= 1 and max_froude > 0)
	assert(rainfall_m_s >= 0 and headwater_m3_s >= 0 and evaporation_m_s >= 0)
	assert(soil_interval_s > 0 and water_display_interval_s > 0)
	soil_profile.validate()
	assert(ecology_interval > 0 and growth_per_tick > 0)
	assert(start_day >= 1 and start_day < 366 and absf(latitude_deg) < 89)
	assert(dam_fraction > 0 and dam_fraction < 1 and dam_width > 0)
	assert(not plants.is_empty())
	var identities := {}
	for plant in plants:
		assert(plant is ForestPlantDefinition and plant.weight > 0)
		plant.validate()
		assert(not identities.has(plant.species_id), "Duplicate species id")
		identities[plant.species_id] = true
