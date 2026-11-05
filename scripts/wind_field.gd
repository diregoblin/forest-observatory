class_name ForestWindField
extends RefCounted

## Submitted presentation field in m/s. Seeded, advected gust envelopes and a
## coarse canopy attenuation; no atmospheric solver or biological model writes.
const MAX_BEND_M := .75
var extent := 512.0
var resolution := 32
var shelter_resolution := 64
var interval_s := .1
var elapsed_s := 0.0
var phase := Vector2.ZERO
var blend := 1.0
var accumulator := 0.0
var previous: Image
var current: Image
var previous_texture: ImageTexture
var current_texture: ImageTexture
var shelter: Image
var shelter_texture: ImageTexture
var canopy := {}
var density := PackedFloat64Array()
var height_sum := PackedFloat64Array()
var shelter_dirty := false
var last_update_usec := 0
var updates := 0
var seed_phase := Vector2.ZERO


func configure(settings: ForestSettings) -> void:
	extent = settings.extent
	resolution = settings.wind_resolution
	shelter_resolution = settings.wind_shelter_resolution
	interval_s = settings.wind_display_interval_s
	var random := RandomNumberGenerator.new()
	random.seed = settings.seed + 54037
	seed_phase = Vector2(random.randf_range(-500, 500), random.randf_range(-500, 500))
	density.resize(shelter_resolution * shelter_resolution)
	height_sum.resize(density.size())
	shelter = Image.create(shelter_resolution, shelter_resolution, false, Image.FORMAT_RGF)
	shelter.fill(Color(1, 1, 0))
	shelter_texture = ImageTexture.create_from_image(shelter)
	current = _image(Vector2.ZERO, Vector2.ZERO)
	previous = current.duplicate()
	current_texture = ImageTexture.create_from_image(current)
	previous_texture = ImageTexture.create_from_image(previous)


func clear_canopy() -> void:
	canopy.clear()
	density.fill(0)
	height_sum.fill(0)
	shelter_dirty = true


func submit_canopy(id: int, position: Vector2, radius: float, height: float, leaves: float) -> void:
	# Quantize small display interpolation changes before touching the grid.
	var descriptor := Vector4(snappedf(radius, .05), snappedf(height, .1), snappedf(leaves, .02), 0)
	var old: Dictionary = canopy.get(id, {})
	if (
		not old.is_empty()
		and old.shape == descriptor
		and old.position.distance_squared_to(position) < .01
	):
		return
	if not old.is_empty():
		_stamp(old.position, old.shape, -1.0)
		canopy.erase(id)
	if radius > 0 and height >= 1.0 and leaves > 0:
		canopy[id] = {"position": position, "shape": descriptor}
		_stamp(position, descriptor, 1.0)
	shelter_dirty = true


func _stamp(position: Vector2, shape: Vector4, sign_value: float) -> void:
	var cell := extent / shelter_resolution
	var spread := maxf(cell * .65, shape.x * 1.3)
	var reach := spread * 2.0
	var first := Vector2i((position - Vector2.ONE * reach) / cell)
	var last := Vector2i((position + Vector2.ONE * reach) / cell)
	# Integrated obstruction scales with actual crown footprint, including
	# subcell crowns. This is stand-scale shelter, not a per-branch CFD wake.
	var strength := shape.z * shape.x * shape.x / (2 * spread * spread)
	for z in range(maxi(0, first.y), mini(shelter_resolution - 1, last.y) + 1):
		for x in range(maxi(0, first.x), mini(shelter_resolution - 1, last.x) + 1):
			var p := (Vector2(x, z) + Vector2.ONE * .5) * cell
			var weight := (
				sign_value
				* strength
				* exp(-p.distance_squared_to(position) / (2 * spread * spread))
			)
			var index := z * shelter_resolution + x
			density[index] += weight
			height_sum[index] += weight * shape.y


func flush_shelter() -> void:
	if not shelter_dirty:
		return
	var pixels := PackedFloat32Array()
	pixels.resize(density.size() * 2)
	for i in density.size():
		var cover := maxf(0.0, density[i])
		pixels[2 * i] = .2 + .8 * exp(-cover * 2.8)
		pixels[2 * i + 1] = maxf(1, height_sum[i] / cover) if cover > .000001 else 1.0
	shelter = Image.create_from_data(
		shelter_resolution, shelter_resolution, false, Image.FORMAT_RGF, pixels.to_byte_array()
	)
	shelter_texture.update(shelter)
	shelter_dirty = false


func envelope(position: Vector2) -> float:
	var p := position + seed_phase
	# Compact, staggered packets with a broad transverse envelope. Transport
	# uses the accumulated wind displacement, so a weather turn cannot teleport
	# an entire field as absolute_time * new_direction would.
	var a := pow(maxf(0.0, cos(p.x * .061 + p.y * .027)), 4)
	var b := pow(maxf(0.0, cos(p.x * -.019 + p.y * .043)), 2)
	return .48 + 1.25 * a * (.35 + .65 * b) + .18 * b


func _image(offset: Vector2, mean_wind: Vector2) -> Image:
	var pixels := PackedFloat32Array()
	pixels.resize(resolution * resolution * 2)
	var cell := extent / resolution
	for z in resolution:
		for x in resolution:
			var p := (Vector2(x, z) + Vector2.ONE * .5) * cell - offset
			var velocity := mean_wind * envelope(p)
			var index := (z * resolution + x) * 2
			pixels[index] = velocity.x
			pixels[index + 1] = velocity.y
	return Image.create_from_data(
		resolution, resolution, false, Image.FORMAT_RGF, pixels.to_byte_array()
	)


func advance(dt: float, mean_wind: Vector2) -> void:
	if dt <= 0:
		return
	elapsed_s += dt
	phase += mean_wind * dt * .7
	accumulator += dt
	if accumulator >= interval_s:
		var started := Time.get_ticks_usec()
		accumulator = fmod(accumulator, interval_s)
		previous = current
		current = _image(phase - mean_wind * accumulator * .7, mean_wind)
		# Two persistent textures: copy previous on the CPU, no GPU readback.
		previous_texture.update(previous)
		current_texture.update(current)
		flush_shelter()
		last_update_usec = Time.get_ticks_usec() - started
		updates += 1
	blend = clampf(accumulator / interval_s, 0, 1)


static func bilinear(image: Image, uv: Vector2) -> Vector2:
	var size := Vector2(image.get_width(), image.get_height())
	var p := uv.clamp(Vector2.ZERO, Vector2.ONE) * size - Vector2.ONE * .5
	var x := floori(p.x)
	var y := floori(p.y)
	var wx := p.x - x
	var wy := p.y - y
	var a := image.get_pixel(clampi(x, 0, int(size.x) - 1), clampi(y, 0, int(size.y) - 1))
	var b := image.get_pixel(clampi(x + 1, 0, int(size.x) - 1), clampi(y, 0, int(size.y) - 1))
	var c := image.get_pixel(clampi(x, 0, int(size.x) - 1), clampi(y + 1, 0, int(size.y) - 1))
	var d := image.get_pixel(clampi(x + 1, 0, int(size.x) - 1), clampi(y + 1, 0, int(size.y) - 1))
	return Vector2(a.r, a.g).lerp(Vector2(b.r, b.g), wx).lerp(
		Vector2(c.r, c.g).lerp(Vector2(d.r, d.g), wx), wy
	)


func sample_at(position: Vector2, height_m := 0.0) -> Vector2:
	var uv := position / extent
	var velocity := bilinear(previous, uv).lerp(bilinear(current, uv), blend)
	var cover := bilinear(shelter, uv)
	var attenuation := lerpf(cover.x, 1.0, smoothstep(0, maxf(1, cover.y), maxf(0, height_m)))
	return velocity * attenuation


func apply(material: ShaderMaterial) -> void:
	if material.get_shader_parameter("wind_current") != current_texture:
		material.set_shader_parameter("spatial_wind_enabled", true)
		material.set_shader_parameter("wind_previous", previous_texture)
		material.set_shader_parameter("wind_current", current_texture)
		material.set_shader_parameter("wind_shelter", shelter_texture)
		material.set_shader_parameter("wind_extent", extent)
	material.set_shader_parameter("wind_blend", blend)


func deformer(pose: Transform3D, strength: float, alive: float) -> Callable:
	# Called only after a ray hits the conservative plant bound. Sample the
	# root's velocity/shelter once for all triangles, matching the vertex shader.
	var uv := Vector2(pose.origin.x, pose.origin.z) / extent
	var velocity := bilinear(previous, uv).lerp(bilinear(current, uv), blend) / 3.0
	var cover := bilinear(shelter, uv)
	var world_wind := Vector3(velocity.x, 0, velocity.y)
	var direction := Vector2(
		pose.basis.x.normalized().dot(world_wind), pose.basis.z.normalized().dot(world_wind)
	)
	var scale := maxf(.001, pose.basis.y.length())
	var maximum := MAX_BEND_M / scale
	return func(point: Vector3) -> Vector3:
		var height := maxf(0, point.y)
		var attenuation := lerpf(cover.x, 1.0, smoothstep(0, maxf(1, cover.y), height * scale))
		var bend := direction * attenuation * pow(height, 1.2) * strength * alive
		bend *= maximum / (maximum + bend.length())
		return point + Vector3(bend.x, 0, bend.y)


func deform(point: Vector3, pose: Transform3D, strength: float, alive: float) -> Vector3:
	return deformer(pose, strength, alive).call(point)
