extends Resource
class_name FluidLiquid

## Gameplay presets for the existing single-phase Newtonian SPH equations.
## Viscosity is a relative solver multiplier, not a measurement in Pa.s.
@export var id: String = "water"
@export var display_name: String = "Water"
@export_range(0.0, 20.0) var viscosity: float = 0.35
## Alpha controls optical absorption, not particle alpha or physical density.
@export var tint: Color = Color(0.08, 0.42, 0.58, 0.0)

func valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() and is_finite(viscosity) and viscosity >= 0.0 and viscosity <= 20.0 and is_finite(tint.r) and is_finite(tint.g) and is_finite(tint.b) and is_finite(tint.a)
