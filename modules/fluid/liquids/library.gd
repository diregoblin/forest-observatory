extends RefCounted

# Load after the SceneTree starts. Eager resource preloads can create a
# FluidLiquid class/preload cycle when a typed command-line script is parsed.
const IDS = ["water", "ivory", "oil", "syrup", "slime"]

static func find_liquid(id: String) -> FluidLiquid:
	if id not in IDS: return null
	return load("res://modules/fluid/liquids/%s.tres" % id) as FluidLiquid

static func all() -> Array[FluidLiquid]:
	var result: Array[FluidLiquid] = []
	for id in IDS: result.append(find_liquid(id))
	return result
