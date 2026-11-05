class_name ForestLandscape
extends RefCounted

var settings: ForestSettings
var noise := FastNoiseLite.new()
var habitat_noise := FastNoiseLite.new()
var ravine_head_floor := 0.0
var ravine_mouth_floor := 0.0
var ravine_branches: Array[Vector4] = []


func _init(config: ForestSettings) -> void:
	settings = config
	noise.seed = settings.seed
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	habitat_noise.seed = settings.seed + 2153
	habitat_noise.frequency = 3.8 / settings.extent
	habitat_noise.fractal_octaves = 2
	var head := spring_position()
	var mouth := spring_mouth()
	ravine_mouth_floor = _base_height(mouth.x, mouth.y)
	ravine_head_floor = minf(
		_base_height(head.x, head.y) - 4.25,
		maxf(
			_base_height(head.x, head.y) - settings.ravine_depth_m,
			ravine_mouth_floor + settings.spring_min_drop_m
		)
	)
	# Passive side incisions: head z, confluence z, signed head offset, width.
	var reach := mouth.y - head.y
	ravine_branches.assign(
		[
			Vector4(head.y + reach * .02, head.y + reach * .38, -settings.extent * .055, 6),
			Vector4(head.y + reach * .30, head.y + reach * .70, settings.extent * .065, 8),
			Vector4(head.y + reach * .53, head.y + reach * .89, -settings.extent * .045, 7)
		]
	)


func habitat_at(x: float, z: float) -> Vector4:
	# Shared continuous site mosaic, never a camera-dependent biome switch.
	var distance := absf(x - channel_x(z))
	# Broad forest stands on the slopes, with smaller genuine openings between.
	var opening := 1.0 - smoothstep(-.32, -.03, habitat_noise.get_noise_2d(x, z))
	var clearing_center := settings.fungi_plot_centers[0] * settings.extent
	opening = maxf(opening, 1.0 - smoothstep(22, 42, Vector2(x, z).distance_to(clearing_center)))
	var shore_patch := smoothstep(-.18, .16, habitat_noise.get_noise_2d(x + 781, z * 1.8))
	var sand := (1.0 - smoothstep(7, 23, distance)) * shore_patch
	var meadow := (1.0 - smoothstep(25, 55, distance)) * (1.0 - sand)
	var forest := (1.0 - sand - meadow) * (1.0 - opening)
	return Vector4(forest, maxf(0, 1.0 - forest - meadow - sand), meadow, sand)


func stand_at(x: float, z: float) -> float:
	# Jittered Voronoi stands, about 90 m across. One stable selection variate
	# per stand; species/resources interpret it, landscape knows no species IDs.
	var span := settings.extent / 5.5
	var grid := Vector2i(floori(x / span), floori(z / span))
	var best := INF
	var value := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := grid + Vector2i(dx, dz)
			var code := hash(Vector3i(key.x, key.y, settings.seed)) & 0x7fffffff
			var center := (
				(
					Vector2(key)
					+ Vector2(.2 + .6 * (code % 997) / 997.0, .2 + .6 * (code % 991) / 991.0)
				)
				* span
			)
			var distance := Vector2(x, z).distance_squared_to(center)
			if distance < best:
				best = distance
				value = float(code % 65521) / 65521.0
	return value


func channel_x(z: float) -> float:
	var size := settings.extent
	return (
		size
		* (.48828125 + .056640625 * sin(z / size * 7.68) + .01953125 * sin(z / size * 16.384 + 1.0))
	)


func height_at(x: float, z: float) -> float:
	var base := _base_height(x, z)
	if not settings.spring_enabled:
		return base
	var head := spring_position()
	var mouth := spring_mouth()
	if z < head.y - 9 or z > mouth.y + 14:
		return base
	var t := clampf((z - head.y) / (mouth.y - head.y), 0, 1)
	var signed_cross := x - ravine_x(z)
	var half_width := settings.ravine_half_width_m * lerpf(.65, 1.65, t)
	half_width *= (
		1
		+ .13 * sin(t * TAU * 2.3)
		+ (.20 * sin(t * TAU * 1.7 + .6) if signed_cross > 0 else -.12 * cos(t * TAU * 2.1))
	)
	var floor_height := ravine_floor(t)
	var gate := smoothstep(head.y - 8, head.y, z) * (1 - smoothstep(mouth.y, mouth.y + 14, z))
	var result := _incise(
		base, floor_height, absf(signed_cross), half_width, lerpf(3.2, 4.2, t), gate
	)
	for branch in ravine_branches:
		if z < branch.x - 4 or z > branch.y:
			continue
		var u := clampf((z - branch.x) / (branch.y - branch.x), 0, 1)
		var join_t := (branch.y - head.y) / (mouth.y - head.y)
		var join_floor := ravine_floor(join_t)
		var source_x := ravine_x(branch.x) + branch.z
		var source_floor := _base_height(source_x, branch.x) - 1.5
		var branch_x := lerpf(source_x, ravine_x(branch.y), u) + signf(branch.z) * 2 * sin(PI * u)
		var branch_floor := lerpf(maxf(source_floor, join_floor + 3), join_floor, u)
		var branch_gate := smoothstep(branch.x - 4, branch.x + 7, z)
		result = minf(
			result,
			_incise(
				base, branch_floor, absf(x - branch_x), branch.w * lerpf(.45, 1, u), .6, branch_gate
			)
		)
	return result


func ravine_floor(t: float) -> float:
	# A steeper upper reach relaxes into the receiving valley; bounded riffles
	# leave the thalweg continuously downhill at the configured model scale.
	return (
		ravine_mouth_floor
		+ (ravine_head_floor - ravine_mouth_floor) * pow(1 - t, 1.35)
		+ .12 * sin(t * TAU * 4) * t * (1 - t)
	)


static func _incise(
	base: float, floor_height: float, cross: float, width: float, bottom: float, gate: float
) -> float:
	if cross >= width or floor_height >= base:
		return base
	var q := clampf((cross - bottom) / maxf(.1, width - bottom), 0, 1)
	var profile := .65 * q + .35 * q * q
	return lerpf(base, lerpf(floor_height, base, profile), gate)


func spring_position() -> Vector2:
	return settings.spring_fraction * settings.extent


func spring_mouth() -> Vector2:
	var z := settings.spring_mouth_fraction * settings.extent
	return Vector2(channel_x(z), z)


func ravine_x(z: float) -> float:
	var head := spring_position()
	var mouth := spring_mouth()
	var t := clampf((z - head.y) / (mouth.y - head.y), 0, 1)
	return (
		lerpf(head.x, mouth.x, t)
		+ settings.extent * sin(PI * t) * (-.012 + .010 * sin(t * TAU * 1.8 + .4))
	)


func initial_spring_depth(x: float, z: float) -> float:
	if not settings.spring_enabled or z < spring_position().y or z > spring_mouth().y:
		return 0.0
	# Declared initial stream storage, included in the initial water ledger.
	return .12 * (1.0 - smoothstep(1.5, 4.0, absf(x - ravine_x(z))))


func _base_height(x: float, z: float) -> float:
	var d := absf(x - channel_x(z))
	var hills := noise.get_noise_2d(x, z)
	var relief := pow(d / 100.0, 1.55) * 14.0
	var banks := 2.3 * (1.0 - exp(-pow(d / 12.0, 2.0)))
	var ripples := hills * 8.0 * smoothstep(12.0, 85.0, d)
	return 7.0 + (settings.extent - z) * 0.023 + relief + banks + ripples


func ground_color(x: float, z: float) -> Color:
	var d := absf(x - channel_x(z))
	var n := (noise.get_noise_2d(x * 2.0, z * 2.0) + 1.0) * 0.5
	var grass := Color(0.31, 0.38, 0.19).lerp(Color(0.47, 0.47, 0.29), n)
	var earth := Color(0.31, 0.29, 0.21)
	var color := earth.lerp(grass, smoothstep(7.0, 19.0, d))
	if settings.spring_enabled:
		var incision := maxf(0, _base_height(x, z) - height_at(x, z))
		var bare := smoothstep(1.4, 4.5, incision) * (.65 + .35 * n)
		var bank_earth := Color(.40, .33, .23).lerp(Color(.27, .25, .19), n)
		color = color.lerp(bank_earth, bare * .85)
	return color


func channel_barrier() -> ForestBarrier:
	var barrier := ForestBarrier.new()
	barrier.barrier_id = &"observation_barrier"
	var dx := settings.extent / settings.water_resolution
	var z := (int(settings.dam_fraction * settings.water_resolution) + 1) * dx
	var x := channel_x(z)
	barrier.start = Vector2(x - settings.dam_width / 2, z)
	barrier.end = Vector2(x + settings.dam_width / 2, z)
	barrier.crest = height_at(x, z) + settings.dam_height
	return barrier


func watercourse_distance(x: float, z: float) -> float:
	var distance := absf(x - channel_x(z))
	if settings.spring_enabled and z >= spring_position().y - 2 and z <= spring_mouth().y:
		distance = minf(distance, absf(x - ravine_x(z)))
	return distance


func bank_exposure(x: float, z: float) -> float:
	var incision := maxf(0, _base_height(x, z) - height_at(x, z))
	if incision < .5:
		return 0
	var gradient := (
		Vector2(
			height_at(x + 1, z) - height_at(x - 1, z), height_at(x, z + 1) - height_at(x, z - 1)
		)
		* .5
	)
	return smoothstep(.5, 2.5, incision) * smoothstep(.3, .85, gradient.length())
