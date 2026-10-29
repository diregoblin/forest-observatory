class_name ForestSettings
extends Resource

@export var seed := 29017
@export var extent := 512.0
@export var terrain_resolution := 512
@export var water_resolution := 64
@export var water_step := .2
@export var rainfall_intensity := .0006
@export var headwater_flow := 8.0
@export var headwater_length := 12.0
@export var headwater_width := 14.0
@export var exchange_rate := .8
@export var donor_fraction := .8
@export var infiltration_rate := .00035
@export var evaporation_rate := .00008
@export var soil_drying_rate := .0001
@export var outlet_rate := .4
@export var dam_fraction := .61
@export var dam_width := 44.0
@export var dam_height := 2.7
@export var tree_attempts := 4600
@export var grass_attempts := 22000
@export var ecology_interval := 2.0
@export var optimum_soil_moisture := .65
@export var moisture_penalty := 1.7
@export var flood_tolerance := .15
@export var flood_biomass := .03
@export var growth_per_tick := .018
@export var plants: Array[Resource] = []


func validate() -> void:
	assert(extent > 0 and terrain_resolution > 0 and water_resolution > 1)
	assert(water_step > 0 and water_step <= .5)
	assert(donor_fraction > 0 and donor_fraction < 1 and exchange_rate > 0)
	assert(rainfall_intensity >= 0 and headwater_flow >= 0)
	assert(ecology_interval > 0 and growth_per_tick > 0)
	assert(dam_fraction > 0 and dam_fraction < 1 and dam_width > 0)
	assert(not plants.is_empty())
	var identities := {}
	for plant in plants:
		assert(plant is ForestPlantDefinition and plant.weight > 0)
		assert(not identities.has(plant.species_id), "Duplicate species id")
		identities[plant.species_id] = true
