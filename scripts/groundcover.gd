class_name ForestGroundcover
extends RefCounted

## Aggregated ground cover, not individual trees. Consumes water/soil fields.
var biomass := PackedFloat64Array()
var ticks := 0
var elapsed := 0.0
var settings: ForestSettings


func _init(water: ForestWatershed) -> void:
	settings = water.landscape.settings
	biomass.resize(water.resolution * water.resolution)
	for j in water.resolution:
		for i in water.resolution:
			var x := (i + .5) * water.cell_size
			var z := (j + .5) * water.cell_size
			biomass[j * water.resolution + i] = .55 + .2 * sin(x * .04) * cos(z * .03)


func step(dt: float, water: ForestWatershed) -> void:
	elapsed += dt
	while elapsed >= settings.ecology_interval:
		elapsed -= settings.ecology_interval
		ticks += 1
		for k in biomass.size():
			var suitable := clampf(
				(
					1.0
					- (
						absf(water.soil[k] - settings.optimum_soil_moisture)
						* settings.moisture_penalty
					)
				),
				0,
				1
			)
			var target := (
				suitable if water.depth[k] < settings.flood_tolerance else settings.flood_biomass
			)
			biomass[k] = move_toward(biomass[k], target, settings.growth_per_tick)
