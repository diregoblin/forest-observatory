class_name ForestGroundcover
extends RefCounted

## Read-only occupancy derived from the authoritative plant arrays. It is NOT
## another biomass/food reserve, and cannot regrow independently of plants.
var biomass := PackedFloat64Array()  # Historical shader API: dimensionless cover.
var ticks := 0
var elapsed := 0.0
var settings: ForestSettings
var plants: ForestTrees
var resolution := 0
var cell_size := 0.0


func _init(water: ForestWatershed) -> void:
	settings = water.landscape.settings
	resolution = water.resolution
	cell_size = water.cell_size
	biomass.resize(resolution * resolution)


func bind_plants(model: ForestTrees) -> void:
	plants = model
	refresh()


func refresh() -> void:
	biomass.fill(0)
	if plants == null:
		return
	for i in plants.species.size():
		if not plants.alive[i]:
			continue
		var d: ForestPlantDefinition = settings.plants[plants.species[i]]
		if d.growth_form == &"tree":
			continue
		var cell := plants.root_cells[i]
		biomass[cell] += PI * pow(d.crown_radius_m * plants.size[i], 2) / (cell_size * cell_size)
	for i in biomass.size():
		biomass[i] = 1.0 - exp(-biomass[i])


func step(_dt: float, _water: ForestWatershed) -> void:
	# Signature retained for consumers; no independent biological clock/state.
	refresh()
