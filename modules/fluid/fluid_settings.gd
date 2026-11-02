extends Resource
class_name FluidSettings

## World units: metres and seconds. Volume is m^3; 0.001 m^3 = one litre.
@export var room_size := Vector3(0.25, 1.0, 0.25)
@export var particle_radius: float = 0.002
@export var fluid_volume: float = 0.0008388608
@export var viscosity: float = 1.0
@export var gravity: float = 1.0
@export var boundary_radius_ratio: float = 1.0
@export var seed_value: int = 5116
## Reads particle buffers back from the GPU; may cause frame-time spikes.
@export var diagnostics_enabled: bool = false
## Geometry property: measured inset into this vessel's wall, not a fluid length.
@export var vessel_surface_inset: float = 0.0006

# Calibration from the verified metric example, not independently tunable knobs.
const REFERENCE_RADIUS := 0.1
const REFERENCE_DENSITY := 19.53125
const PRESSURE := 128.0
const REFERENCE_VISCOSITY := 2.5
const SUPPORT_RATIO := 8.0
const RESTITUTION := 0.3
const PARTICLE_BUDGET := 40000

func boundary_sample_count(surface_area: float) -> int:
	var r: float = particle_radius * boundary_radius_ratio
	return maxi(16, ceili(surface_area / (0.5 * PI * r * r)))

func derive() -> Dictionary:
	var error := validation_error()
	if not error.is_empty():
		push_error(error)
		return {}
	assert(particle_radius > 0.0 and fluid_volume > 0.0 and viscosity >= 0.0)
	var q: float = particle_radius / REFERENCE_RADIUS
	var number_density: float = REFERENCE_DENSITY / pow(q, 3)
	var n: int = maxi(1, roundi(fluid_volume * number_density))
	assert(n <= PARTICLE_BUDGET, "Requested volume/resolution exceeds the 40000 particle budget; reduce volume.")
	var h: float = SUPPORT_RATIO * particle_radius
	# Fixed-time geometric similarity: pressure scales as length^2,
	# and the unweighted viscosity coefficient as inverse length.
	var mu: float = REFERENCE_VISCOSITY * viscosity / q
	return {"radius": particle_radius, "h": h, "density": number_density,
		"pressure": PRESSURE * q * q, "viscosity": mu, "count": n,
		"spacing": pow(1.0 / number_density, 1.0 / 3.0),
		"boundary_radius": particle_radius * boundary_radius_ratio,
		"contact_epsilon": particle_radius * 0.00008,
		"density_floor": number_density * 0.0000001}

## Runtime checks also run in release builds, where assertions are stripped.
func validation_error() -> String:
	if not is_finite(particle_radius) or particle_radius <= 0.0: return "Particle radius must be finite and positive"
	if not is_finite(fluid_volume) or fluid_volume <= 0.0: return "Fluid volume must be finite and positive"
	if not is_finite(viscosity) or viscosity < 0.0: return "Viscosity must be finite and nonnegative"
	if not is_finite(gravity): return "Gravity must be finite"
	if not is_finite(boundary_radius_ratio) or boundary_radius_ratio <= 0.0: return "Boundary radius ratio must be finite and positive"
	if not room_size.is_finite() or room_size.x <= 2*particle_radius or room_size.y <= 2*particle_radius or room_size.z <= 2*particle_radius: return "Room must contain the particles"
	var density := REFERENCE_DENSITY / pow(particle_radius / REFERENCE_RADIUS, 3)
	var requested := fluid_volume * density
	if not is_finite(requested) or requested > PARTICLE_BUDGET + .499: return "Requested resolution exceeds the 40000 particle budget"
	var n := maxi(1,roundi(requested))
	var extent := (ceili(pow(float(n),1./3.))-1)*pow(1./density,1./3.)
	if extent+2*particle_radius >= minf(room_size.x,room_size.z) or room_size.y*.55+extent+particle_radius >= room_size.y: return "Initial fluid block does not fit room"
	return ""
