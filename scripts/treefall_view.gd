extends Node3D

## Detached presentation events. The coupled model has already booked deadwood;
## motion/audio never read or write that model, including on busy-worker frames.
var events := {}
var observer: Camera3D
var players: Array[AudioStreamPlayer3D] = []
var crack: AudioStreamWAV
var impact: AudioStreamWAV
var emitted := []


func configure(camera: Camera3D) -> void:
	observer = camera
	crack = sound(false)
	impact = sound(true)
	for index in 8:
		var player := AudioStreamPlayer3D.new()
		player.max_distance = 200
		player.unit_size = 12
		player.volume_db = -9
		add_child(player)
		players.append(player)


func begin(id: int, from: Transform3D, to: Transform3D, state: Color, height: float) -> void:
	var duration := clampf(2.2 + sqrt(height) * .35, 2.8, 4.6)
	events[id] = {"from": from, "to": to, "state": state, "elapsed": 0.0, "duration": duration}
	_emit(id, false, from.origin)


func advance(dt: float) -> Dictionary:
	for player in players:
		player.stream_paused = dt <= 0
	var poses := {}
	for id in events.keys():
		var e: Dictionary = events[id]
		var previous: float = e.elapsed
		e.elapsed = minf(e.duration + .4, e.elapsed + maxf(0, dt))
		if previous < e.duration and e.elapsed >= e.duration:
			_emit(id, true, e.to.origin)
		poses[id] = pose(e)
		if e.elapsed >= e.duration + .4:
			events.erase(id)
	return poses


static func pose(e: Dictionary) -> Dictionary:
	var t: float = clampf(e.elapsed / e.duration, 0, 1)
	# A visible creaking lean, then accelerating descent to the model's contact pose.
	var amount := .025 * pow(t / .28, 2) if t < .28 else .025 + .975 * pow((t - .28) / .72, 2.2)
	var state: Color = e.state
	state.r *= 1 - smoothstep(e.duration, e.duration + .4, e.elapsed)
	state.a = 0
	return {"transform": e.from.interpolate_with(e.to, amount), "state": state}


func clear() -> void:
	events.clear()
	for player in players:
		player.stop()


func snapshot() -> Dictionary:
	return events.duplicate(true)


static func valid(saved: Variant, fallen: Variant) -> bool:
	if not saved is Dictionary or not fallen is PackedByteArray:
		return false
	for id in saved:
		if not id is int or id < 0 or id >= fallen.size() or not fallen[id]:
			return false
		var e: Variant = saved[id]
		if not e is Dictionary:
			return false
		for key in ["from", "to"]:
			if (
				not e.get(key) is Transform3D
				or not e[key].is_finite()
				or e[key].basis.determinant() <= 0
			):
				return false
		if not e.get("state") is Color:
			return false
		for value in [e.state.r, e.state.g, e.state.b, e.state.a]:
			if not is_finite(value):
				return false
		for key in ["elapsed", "duration"]:
			if not (e.get(key) is float or e.get(key) is int) or not is_finite(e[key]):
				return false
		if e.duration < 2.8 or e.duration > 4.6 or e.elapsed < 0 or e.elapsed >= e.duration + .4:
			return false
	return true


func _emit(id: int, hit: bool, point: Vector3) -> void:
	emitted.append({"id": id, "impact": hit})
	if emitted.size() > 32:
		emitted.pop_front()
	if observer == null or observer.position.distance_to(point) > 200:
		return
	var chosen: AudioStreamPlayer3D
	for player in players:
		if not player.playing:
			chosen = player
			break
	# A nearby fall can replace the most distant voice during a storm.
	if chosen == null:
		chosen = players[0]
		for player in players:
			if (
				player.position.distance_to(observer.position)
				> chosen.position.distance_to(observer.position)
			):
				chosen = player
		if point.distance_to(observer.position) >= chosen.position.distance_to(observer.position):
			return
	chosen.position = point
	chosen.stream = impact if hit else crack
	chosen.pitch_scale = .92 + float(id % 13) * .013
	chosen.play()


static func sound(hit: bool) -> AudioStreamWAV:
	var rate := 22050
	var seconds := 1.4 if hit else 1.05
	var count := int(rate * seconds)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 8507 if hit else 12031
	var low := 0.0
	for i in count:
		var t := float(i) / rate
		var noise := random.randf_range(-1, 1)
		low = lerpf(low, noise, .08 if hit else .23)
		var value := 0.0
		if hit:
			var envelope := (1 - exp(-t * 240)) * exp(-t * 4.2)
			value = (low * 1.2 + sin(t * TAU * 63) * .22 + noise * .15) * envelope
		else:
			# A dry series of short wood fractures over a strained low creak.
			var pulses := 0.0
			for onset in [.02, .19, .31, .56, .78]:
				if t >= onset:
					pulses += exp(-(t - onset) * 65)
			value = (
				noise * pulses * .38 + low * .15 * sin(t * TAU * (150 + 70 * t)) * (1 - t / seconds)
			)
		bytes.encode_s16(i * 2, int(clampf(value, -.95, .95) * 32767))
	var wav := AudioStreamWAV.new()
	wav.mix_rate = rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.data = bytes
	return wav
