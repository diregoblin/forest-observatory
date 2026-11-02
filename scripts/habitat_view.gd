class_name ForestHabitatView
extends Node3D

## Bounded representatives of model pools, actual homes/tracks and spatial sound.
## No ecological stocks or decisions advance in this view.
# Presentation limits only; they never alter ecology or save configuration.
@export var insect_view_distance_m := 18.0
@export var footprint_view_distance_m := 40.0
@export var home_view_distance_m := 60.0
@export var rootplate_view_distance_m := 100.0
var last_submitted_instances := 0
var last_visibility_updates := 0

var terrain: Terrain3D
var habitat: ForestHabitat
var observer: Camera3D
var bugs := MultiMeshInstance3D.new()
var footprints := MultiMeshInstance3D.new()
var homes := MultiMeshInstance3D.new()
var rootplates := MultiMeshInstance3D.new()
var sound := AudioStreamPlayer3D.new()
var chirp: AudioStreamWAV
var rustle: AudioStreamWAV
var last_sound_s := -10.0
var last_seen_positions := PackedVector3Array()
var paused := false
var _track_geometry_cache := {}
var _candidates := {}
var _display_dirty := true
var _last_camera_position := Vector3(INF, INF, INF)
var _last_parent_transform := Transform3D.IDENTITY
var _last_distances := PackedFloat64Array()


func _batch(node: MultiMeshInstance3D, mesh: Mesh, count: int, color: Color) -> void:
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_colors = true
	node.multimesh.use_custom_data = node == bugs
	node.multimesh.mesh = mesh
	node.multimesh.instance_count = count
	node.multimesh.visible_instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func configure(model: ForestHabitat, camera: Camera3D, ground: Terrain3D = null) -> void:
	terrain = ground
	_track_geometry_cache.clear()
	habitat = model
	observer = camera
	var bug := SphereMesh.new()
	bug.radius = .022
	bug.height = .028
	bug.radial_segments = 6
	bug.rings = 3
	_batch(bugs, bug, 128, Color(.68, .49, .12))
	var insect_material := ShaderMaterial.new()
	insect_material.shader = load("res://shaders/habitat_insects.gdshader")
	bugs.material_override = insect_material
	bugs.extra_cull_margin = 1
	var print_mesh := PlaneMesh.new()
	print_mesh.size = Vector2(2, 2)
	_batch(footprints, print_mesh, ForestHabitat.TRACK_LIMIT * 2, Color.WHITE)
	var print_material := ShaderMaterial.new()
	print_material.shader = preload("res://shaders/footprint.gdshader")
	footprints.material_override = print_material
	var entrance := SphereMesh.new()
	entrance.radius = 1
	entrance.height = .07
	entrance.radial_segments = 10
	entrance.rings = 3
	_batch(homes, entrance, 256, Color(.10, .075, .045))
	var root := CylinderMesh.new()
	root.top_radius = 1
	root.bottom_radius = 1
	root.height = .20
	root.radial_segments = 8
	_batch(rootplates, root, 256, Color(.19, .135, .07))
	chirp = _tone(true)
	rustle = _tone(false)
	sound.max_distance = 45
	sound.unit_size = 6
	sound.volume_db = -17
	add_child(sound)
	refresh({})


func refresh(climate: Dictionary) -> void:
	# Called only while the main thread owns the models. Cache all bounded
	# candidates, so camera-only updates during a worker tick read no model data.
	_candidates = {bugs: [], footprints: [], homes: [], rootplates: []}
	var t: float = climate.get("weather_time_s", 0.0)
	set_weather_time(t)
	var active: bool = (
		float(climate.get("temperature_c", 15.0)) > 7
		and climate.get("rain_fraction", 0.0) < .2
		and climate.get("wind_m_s", 0.0) < 10
	)
	if active:
		for k in ForestHabitat.GRID * ForestHabitat.GRID:
			if habitat.insect_carbon(habitat.center(k)) < 1e-7:
				continue
			var point := habitat.center(k)
			var which: int = habitat.insect_sites[k]
			if which >= 0:
				point = habitat.plants.positions[which]
			var height := .08
			if which >= 0:
				var plant_trait: ForestPlantDefinition = habitat.plants.land.settings.plants[
					habitat.plants.species[which]
				]
				height = (
					.25
					if habitat.plants.fallen[which]
					else minf(2, plant_trait.reference_height_m * habitat.plants.size[which] * .8)
				)
			point.y += height
			_candidates[bugs].append(
				[
					Transform3D(Basis.IDENTITY, point),
					Color.WHITE,
					Color(float(k), .45 if height > .1 else .12, 0, 0)
				]
			)
	var geometry_cache := {}
	for track in habitat.tracks:
		var point: Vector3 = track.position
		if habitat.water.depth[habitat.water.index_at(point.x, point.z)] > .02:
			continue
		var fade := clampf(1 - (habitat.elapsed_s - track.born_s) / track.life_s, 0, 1)
		var key := Vector4(point.x, point.z, track.yaw, track.size)
		var poses: Array = _track_geometry_cache.get(key, [])
		if poses.is_empty():
			poses = _track_poses(point, track.yaw, track.size)
		geometry_cache[key] = poses
		for pose in poses:
			_candidates[footprints].append([pose, Color(1, 1, 1, smoothstep(0, .8, fade)), Color()])
	_track_geometry_cache = geometry_cache
	for id in habitat.animals.species.size():
		var d: ForestAnimalDefinition = habitat.animals.definitions[habitat.animals.species[id]]
		if not habitat.animals.alive[id] or d.flight_height_m > 0:
			continue
		var point := habitat.animals.home_positions[id]
		if not habitat.animals._dry(point, d):
			continue
		var radius := maxf(.12, d.selection_radius_m * .7)
		_candidates[homes].append(
			[
				Transform3D(
					Basis.from_scale(Vector3(radius, 1, radius * .75)), point + Vector3.UP * .01
				),
				Color.WHITE,
				Color()
			]
		)
	for id in habitat.plants.species.size():
		if not habitat.plants.fallen[id] or habitat.plants.dead_c[id] <= .01:
			continue
		var radius := clampf(habitat.plants.size[id] * .65, .25, 1.8)
		var position := habitat.plants.positions[id] + Vector3.UP * radius * .7
		var basis := Basis(Vector3.RIGHT, PI / 2).scaled(Vector3(radius, 1, radius))
		_candidates[rootplates].append([Transform3D(basis, position), Color.WHITE, Color()])
	_display_dirty = true
	advance_display()
	_sounds(climate)


func _surface_height(point: Vector3) -> float:
	if terrain != null:
		return terrain.data.get_height(point)
	return habitat.plants.land.height_at(point.x, point.z)


func _track_poses(point: Vector3, yaw: float, size: float) -> Array:
	var result := []
	for side in [-1, 1]:
		var p := point + Vector3(side * size * .3, 0, 0).rotated(Vector3.UP, yaw)
		p.y = _surface_height(p) + .025
		var normal := (
			Vector3(
				_surface_height(p - Vector3(.2, 0, 0)) - _surface_height(p + Vector3(.2, 0, 0)),
				.4,
				_surface_height(p - Vector3(0, 0, .2)) - _surface_height(p + Vector3(0, 0, .2))
			)
			. normalized()
		)
		var forward := Vector3(sin(yaw), 0, cos(yaw))
		var right := normal.cross(forward).normalized()
		forward = right.cross(normal)
		result.append(Transform3D(Basis(right * size * .22, normal, forward * size * .34), p))
	return result


func advance_display() -> void:
	# Safe with the worker running: only submitted geometry and camera transforms.
	last_visibility_updates = 0
	if observer == null or _candidates.is_empty():
		return
	var camera_position := observer.global_position
	var distances := PackedFloat64Array(
		[
			insect_view_distance_m,
			footprint_view_distance_m,
			home_view_distance_m,
			rootplate_view_distance_m
		]
	)
	if (
		not _display_dirty
		and camera_position == _last_camera_position
		and global_transform == _last_parent_transform
		and distances == _last_distances
	):
		return
	_last_camera_position = camera_position
	_last_parent_transform = global_transform
	_last_distances = distances.duplicate()
	_display_dirty = false
	last_submitted_instances = 0
	bugs.material_override.set_shader_parameter("view_distance_m", insect_view_distance_m)
	var nodes := [bugs, footprints, homes, rootplates]
	for index in nodes.size():
		var node: MultiMeshInstance3D = nodes[index]
		var count := 0
		var limit_squared: float = maxf(0, distances[index]) ** 2
		var batch_transform := node.global_transform
		for record in _candidates[node]:
			var pose: Transform3D = record[0]
			if (
				distances[index] <= 0
				or (
					(batch_transform * pose.origin).distance_squared_to(camera_position)
					> limit_squared
				)
			):
				continue
			if count >= node.multimesh.instance_count:
				break
			node.multimesh.set_instance_transform(count, pose)
			node.multimesh.set_instance_color(count, record[1])
			if node == bugs:
				node.multimesh.set_instance_custom_data(count, record[2])
			count += 1
		node.multimesh.visible_instance_count = count
		last_submitted_instances += count
	last_visibility_updates = 1


func set_weather_time(t: float) -> void:
	if bugs.material_override is ShaderMaterial:
		bugs.material_override.set_shader_parameter("weather_time", t)


func _sounds(climate: Dictionary) -> void:
	var a := habitat.animals
	var old := last_seen_positions.size()
	last_seen_positions.resize(a.positions.size())
	var elapsed: float = climate.get("weather_time_s", 0.0)
	var ready := not paused and elapsed - last_sound_s > 3 and not sound.playing
	for id in a.species.size():
		var moved := id < old and a.positions[id].distance_squared_to(last_seen_positions[id]) > .04
		last_seen_positions[id] = a.positions[id]
		if not ready or not a.alive[id] or a.positions[id].distance_to(observer.position) > 35:
			continue
		var bird: bool = a.definitions[a.species[id]].flight_height_m > 0
		var singing: bool = (
			bird
			and a.actions[id] not in ["sleep", "flee", "eat"]
			and climate.get("hour", 12.0) > 4
			and climate.get("hour", 12.0) < 20
			and climate.get("rain_fraction", 0.0) < .15
		)
		if not singing and not moved:
			continue
		sound.position = a.positions[id] + Vector3.UP * (1.8 if singing else .1)
		sound.stream = chirp if singing else rustle
		sound.play()
		last_sound_s = elapsed
		ready = false


func _tone(bird: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 22050
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var samples := PackedByteArray()
	var duration := .7 if bird else .18
	var rng := RandomNumberGenerator.new()
	rng.seed = 3401
	for i in int(duration * stream.mix_rate):
		var t := float(i) / stream.mix_rate
		var envelope := pow(sin(PI * t / duration), 2)
		var signal_value: float
		if bird:
			signal_value = (
				sin(TAU * (1800 * t + 900 * t * t + .5 * sin(45 * t))) * maxf(0, sin(t * 32)) * .17
			)
		else:
			signal_value = rng.randf_range(-1, 1) * .10 + sin(t * 800) * .025
		var sample := int(clampf(signal_value * envelope, -1, 1) * 32767)
		samples.append(sample & 255)
		samples.append((sample >> 8) & 255)
	stream.data = samples
	return stream
