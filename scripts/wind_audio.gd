class_name ForestWindAudio
extends AudioStreamPlayer

## Listener ambience driven by exactly the interpolated field used for plants.
## Existing positional bird calls and animal rustles remain independent.
static var noise: AudioStreamWAV
var field: ForestWindField
var observer: Camera3D
var surface_height: Callable
var local_speed_m_s := 0.0
var level := 0.0


func configure(wind: ForestWindField, camera: Camera3D, height_sampler: Callable) -> void:
	field = wind
	observer = camera
	surface_height = height_sampler
	if noise == null:
		noise = _noise()
	stream = noise
	volume_db = -80
	play()


func update(dt: float, paused: bool) -> void:
	stream_paused = paused
	if paused or field == null:
		return
	var point := observer.global_position
	var ground: float = surface_height.call(point)
	if not is_finite(ground):
		ground = point.y - 1.7
	local_speed_m_s = field.sample_at(Vector2(point.x, point.z), maxf(0, point.y - ground)).length()
	var target := .075 * pow(clampf(local_speed_m_s / 8.0, 0, 1.5), .85)
	level = lerpf(level, target, 1.0 - exp(-dt / .18))
	volume_db = linear_to_db(maxf(.0001, level))


static func _noise() -> AudioStreamWAV:
	var rate := 22050
	var count := rate * 3
	var values := PackedFloat32Array()
	values.resize(count)
	var random := RandomNumberGenerator.new()
	random.seed = 72019
	for i in count:
		values[i] = random.randf_range(-1, 1)
	# Warm one full loop before recording: no discontinuity in the filter state
	# at the loop boundary. Broad filtered noise, no musical or spoken content.
	var low := 0.0
	var slow := 0.0
	var samples := PackedByteArray()
	samples.resize(count * 2)
	for pass_index in 2:
		for i in count:
			low = lerpf(low, values[i], .16)
			slow = lerpf(slow, low, .006)
			if pass_index == 1:
				samples.encode_s16(i * 2, int(clampf((low - slow) * 1.2, -1, 1) * 32767))
	var result := AudioStreamWAV.new()
	result.mix_rate = rate
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.loop_mode = AudioStreamWAV.LOOP_FORWARD
	result.loop_begin = 0
	result.loop_end = count
	result.data = samples
	return result
