class_name ForestAnimalsView
extends Node3D

## Presentation only: resource-driven primitive builder; stable individual silhouettes.
## Small populations use one merged mesh per animal, not one draw call per body part.
var model: ForestAnimals
var batches: Array[MultiMeshInstance3D] = []
var mesh_faces: Array[PackedVector3Array] = []
var displayed_transforms := {}
var submitted_transforms := {}
var submitted_colors := {}
var submitted_visibility := {}
var primitive_meshes := {}
var body_material := ShaderMaterial.new()
var animation_players: Array[AnimationPlayer] = []
var animation_poses := {}
var animation_clips := {}
var animation_times := {}
var face_tags: Array[PackedColorArray] = []
var head_pivots := PackedVector3Array()
var wing_hinges := PackedVector3Array()
var animation_transitions := {}
var motion_library: AnimationLibrary = load("res://data/animation/animal_motion.tres")
var last_gpu_writes := 0
var selection_cache := {}  # At most one immutable posed mesh per displayed ID.
var motion_bounds: Array[Dictionary] = []
var display_bounds_cache := {}
var captured_frame := {}
var displayed_heights := {}


func _init() -> void:
	body_material.shader = preload("res://shaders/animal_motion.gdshader")


func _primitive(shape: String) -> Mesh:
	if primitive_meshes.has(shape):
		return primitive_meshes[shape]
	if shape in ["barrel", "taper", "leaf", "plume", "feather"]:
		primitive_meshes[shape] = ForestAnimalGeometry.build(shape)
		return primitive_meshes[shape]
	var mesh: PrimitiveMesh
	match shape:
		"box":
			mesh = BoxMesh.new()
			mesh.size = Vector3.ONE
		"cylinder", "cone":
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.0 if shape == "cone" else .5
			mesh.bottom_radius = .5
			mesh.height = 1
			mesh.radial_segments = 8
		_:
			mesh = SphereMesh.new()
			mesh.radius = .5
			mesh.height = 1
			mesh.radial_segments = 10
			mesh.rings = 5
	primitive_meshes[shape] = mesh
	return mesh


func configure(animals: ForestAnimals) -> void:
	model = animals
	refresh()


func _create_body(id: int) -> void:
	var definition: ForestAnimalDefinition = model.definitions[model.species[id]]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var tags := PackedColorArray()
	var head := Vector3.ZERO
	var genes: Dictionary = model.phenotypes[id]
	var shape_scale := Vector3(lerpf(.82, 1.18, genes.build), 1, lerpf(.86, 1.14, genes.length))
	for j in definition.part_shapes.size():
		if not definition.part_roles.is_empty() and definition.part_roles[j] == "head":
			head = definition.part_offsets[j] * shape_scale
			break  # The skull, not the last muzzle/cheek detail, owns head rotation.
	for i in definition.part_shapes.size():
		var dimensions: Vector3 = definition.part_dimensions[i]
		var offset: Vector3 = definition.part_offsets[i]
		var rotations: Vector3 = definition.part_rotations[i]
		var color: Color = definition.part_colors[i]
		var role: String = (
			definition.part_roles[i] if not definition.part_roles.is_empty() else "body"
		)
		dimensions *= shape_scale
		offset *= shape_scale
		var adjustment := Basis.IDENTITY
		if role == "ear":
			var length := lerpf(.72, 1.28, genes.ears)
			var angle := lerpf(.4, 1.7, genes.ear_angle)
			var asymmetry: float = (genes.markings - .5) * 24 * signf(offset.x)
			if definition.part_pivots.is_empty():
				offset.y += dimensions.y * (length - 1) * .5
				dimensions.y *= length
				rotations.z *= angle
				rotations.x += asymmetry
			else:
				# Stretch/turn the entire anatomical group about its shared base.
				# Independent per-piece elongation detaches tips on short ears.
				var hinge: Vector3 = definition.part_pivots[i] * shape_scale
				var axis := Basis.from_euler(rotations * PI / 180)
				adjustment = (
					Basis.from_euler(Vector3(asymmetry, 0, rotations.z * (angle - 1)) * PI / 180)
					* axis
					* Basis.from_scale(Vector3(1, length, 1))
					* axis.inverse()
				)
				offset = hinge + adjustment * (offset - hinge)
		if role not in ["eye", "nose", "white"]:
			color *= Color(
				lerpf(.64, 1.15, genes.coat),
				lerpf(.68, 1.08, genes.coat),
				lerpf(.76, .9, genes.coat),
				1
			)
			if role in ["body", "haunch", "tail"]:
				color = color.darkened(genes.markings * .32)
		var mesh := _primitive(definition.part_shapes[i])
		# Primitive dimensions belong to its local axes before rotation. Global
		# scaling truncated a rotated fox muzzle and disconnected its nose.
		var basis := (
			adjustment * Basis.from_euler(rotations * PI / 180) * Basis.from_scale(dimensions)
		)
		var code := 0
		var pivot := offset
		if role in ["head", "eye", "nose"]:
			code = 1
			pivot = head
		elif role == "ear":
			code = 2
			pivot.y -= dimensions.y * .4
		elif role in ["leg", "paw"]:
			code = 3
			pivot.y += dimensions.y * .4
		elif role == "tail":
			code = 4
		elif role == "wing":
			code = 5
		elif role == "flight_wing":
			code = 6
		elif role == "flight_tip":
			code = 7
		elif role == "flight_leg":
			code = 8
		if not definition.part_pivots.is_empty():
			pivot = definition.part_pivots[i] * shape_scale
		var tag := Color(pivot.x, pivot.y, pivot.z, code)
		surface.set_custom(0, tag)
		var arrays := mesh.surface_get_arrays(0)
		for _corner in arrays[Mesh.ARRAY_INDEX].size():
			tags.append(tag)
		ForestPlantMeshBuilder._append(
			surface, mesh, Transform3D(basis, offset), color.srgb_to_linear()
		)
	var geometry := ForestPlantMeshBuilder.commit_indexed(surface)
	geometry.surface_set_material(0, body_material)
	mesh_faces.append(geometry.get_faces())
	face_tags.append(tags)
	var parts := {}
	for corner in tags.size():
		var tag: Color = tags[corner]
		var point: Vector3 = mesh_faces[-1][corner]
		parts[tag] = parts[tag].expand(point) if parts.has(tag) else AABB(point, Vector3.ZERO)
	motion_bounds.append(parts)
	head_pivots.append(head)
	wing_hinges.append(definition.wing_shoulder * shape_scale)
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_colors = true
	batch.multimesh.mesh = geometry
	batch.multimesh.instance_count = 1
	add_child(batch)
	batch.extra_cull_margin = .25
	batch.set_instance_shader_parameter("head_pivot", head)
	batch.set_instance_shader_parameter("wing_hinge", wing_hinges[-1])
	batch.set_instance_shader_parameter("body_height", definition.selection_height_m)
	var player := AnimationPlayer.new()
	player.root_node = NodePath("..")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	batch.add_child(player)
	player.add_animation_library("", motion_library)
	animation_players.append(player)
	batches.append(batch)


func rebuild() -> void:
	selection_cache.clear()
	display_bounds_cache.clear()
	captured_frame = {}
	motion_bounds.clear()
	for batch in batches:
		batch.free()
	batches.clear()
	mesh_faces.clear()
	face_tags.clear()
	head_pivots.clear()
	wing_hinges.clear()
	animation_transitions.clear()
	animation_players.clear()
	animation_poses.clear()
	animation_clips.clear()
	animation_times.clear()
	submitted_transforms.clear()
	submitted_colors.clear()
	submitted_visibility.clear()
	refresh()


func refresh(display_alpha := 1.0) -> void:
	advance_display(capture_frame(), display_alpha)


func capture_frame() -> Dictionary:
	# Called only while the model owner is joined. Detach all moving data.
	while batches.size() < model.species.size():
		_create_body(batches.size())
	# Loading an earlier generation can remove later IDs; do not retain ghost meshes.
	while batches.size() > model.species.size():
		var removed := batches.size() - 1
		selection_cache.erase(removed)
		display_bounds_cache.erase(removed)
		motion_bounds.pop_back()
		submitted_transforms.erase(removed)
		submitted_colors.erase(removed)
		submitted_visibility.erase(removed)
		batches.pop_back().free()
		mesh_faces.pop_back()
		face_tags.pop_back()
		head_pivots.resize(removed)
		wing_hinges.resize(removed)
		animation_transitions.erase(removed)
		animation_players.pop_back()
		animation_poses.erase(removed)
		animation_times.erase(removed)
		animation_clips.erase(removed)
	var bodies: Array[Dictionary] = []
	for id in model.species.size():
		var remains: float = model.habitat.carcass_carbon(id) if model.habitat != null else 0.0
		var hidden: bool = (
			(not model.alive[id] and remains < .00001)
			if model.habitat != null
			else model.killed_by[id] >= 0
		)
		var d: ForestAnimalDefinition = model.definitions[model.species[id]]
		var fraction: float = (
			maxf(.1, model.biomass_c[id] / d.initial_elements.x)
			if model.alive[id]
			else model._growth_fraction(id)
		)
		if not model.alive[id] and model.habitat != null:
			fraction = maxf(.001, remains / d.initial_elements.x)
		var scale := clampf(pow(fraction, 1.0 / 3.0), .42, 1.15)
		var basis := Basis(Vector3.UP, model.yaw[id]).scaled(Vector3.ONE * scale)
		if model.alive[id] and model.actions[id] == "sleep":
			basis *= Basis.from_scale(Vector3(1.04, .66, 1.04))
		if not model.alive[id]:
			basis *= Basis(Vector3.FORWARD, PI / 2)
		var points: PackedVector3Array = model.path_history[id].points.duplicate()
		var swimming := model.is_swimming(id)
		var flying := (
			d.flight_height_m > 0
			and model.alive[id]
			and (
				model.actions[id] in ["seek_food", "seek_cover", "explore", "flee"]
				or not model._dry(model.positions[id], d)
			)
		)
		for k in points.size():
			if not model.alive[id]:
				points[k].y += .1
			if swimming:
				var cell: int = model.water.index_at(points[k].x, points[k].z)
				points[k].y = maxf(
					points[k].y,
					(
						model.water.bed[cell]
						+ model.water.depth[cell]
						- d.selection_height_m * scale * .38
					)
				)
			if flying:
				points[k].y += d.flight_height_m
		var start_basis := basis
		if captured_frame.get("bodies", []).size() > id:
			start_basis = captured_frame.bodies[id].basis
		bodies.append(
			{
				"points": points,
				"times": model.path_history[id].times.duplicate(),
				"basis": basis,
				"start_basis": start_basis,
				"hidden": hidden,
				"height": d.selection_height_m,
				"color": Color.WHITE if model.alive[id] else Color(.55, .5, .45),
				"clip": _motion_clip(id),
				"travel_clip": _motion_clip(id, true),
				"alive": bool(model.alive[id])
			}
		)
	captured_frame = {
		"end_s": model.elapsed_s / model.land.settings.year_speed_multiplier,
		"step_s": model.land.settings.ecology_step_s,
		"bodies": bodies
	}
	return captured_frame


func advance_display(frame: Dictionary, alpha: float, smooth_turns := false) -> void:
	# No model reads here: safe even while the worker rewrites arrays/paths.
	displayed_transforms.clear()
	displayed_heights.clear()
	last_gpu_writes = 0
	var parent_transform := global_transform if is_inside_tree() else transform
	for id in batches.size():
		var hidden: bool = id >= frame.bodies.size() or frame.bodies[id].hidden
		var multi := batches[id].multimesh
		var visible_count := 0 if hidden else 1
		if submitted_visibility.get(id, -1) != visible_count:
			multi.visible_instance_count = visible_count
			submitted_visibility[id] = visible_count
			last_gpu_writes += 1
		if hidden:
			continue
		var body: Dictionary = frame.bodies[id]
		var basis: Basis = body.basis
		if smooth_turns:
			basis = Transform3D(body.start_basis).interpolate_with(Transform3D(basis), alpha).basis
		var submitted := Transform3D(basis, _path_position(body, alpha))
		if submitted_transforms.get(id) != submitted:
			multi.set_instance_transform(0, submitted)
			submitted_transforms[id] = submitted
			last_gpu_writes += 1
		displayed_transforms[id] = parent_transform * submitted
		displayed_heights[id] = body.height
		if is_inside_tree():
			var t: float = maxf(0, frame.end_s - frame.step_s * (1 - alpha)) + id * .371
			_animate(id, _display_clip(body, alpha), t if body.alive else 0.0)
		if submitted_colors.get(id) != body.color:
			multi.set_instance_color(0, body.color)
			submitted_colors[id] = body.color
			last_gpu_writes += 1


static func _path_segment(body: Dictionary, alpha: float) -> int:
	var target_time: float = body.times[-1] * clampf(alpha, 0, 1)
	for i in range(1, body.times.size()):
		if target_time <= body.times[i]:
			return i
	return body.times.size() - 1


static func _path_position(body: Dictionary, alpha: float) -> Vector3:
	var i := _path_segment(body, alpha)
	if i == 0:
		return body.points[0]
	var target_time: float = body.times[-1] * clampf(alpha, 0, 1)
	var weight: float = (
		(target_time - body.times[i - 1]) / maxf(1e-12, body.times[i] - body.times[i - 1])
	)
	return body.points[i - 1].lerp(body.points[i], weight)


static func _display_clip(body: Dictionary, alpha: float) -> String:
	if not body.alive:
		return "idle"
	var segment := _path_segment(body, alpha)
	var moving: bool = (
		segment > 0 and body.points[segment].distance_squared_to(body.points[segment - 1]) > 1e-10
	)
	# An animal can arrive and eat within one tick. Its final action must not
	# replace locomotion over the earlier, still moving part of the captured path.
	if moving:
		return body.get("travel_clip", body.clip)
	return "idle" if body.clip in ["walk", "hop", "fly", "swim"] else body.clip


func display_shape(id: int) -> Dictionary:
	# HUD/follow needs only a conservative posed bound, NOT every mesh corner.
	# Each tagged body part undergoes an affine motion: its eight AABB corners
	# enclose the fully deformed geometry. Exact triangle picking remains below.
	if not displayed_transforms.has(id):
		return {}
	var pose: PackedFloat32Array = animation_poses.get(id, PackedFloat32Array())
	var height: float = displayed_heights[id]
	var cached: Dictionary = display_bounds_cache.get(id, {})
	if (
		cached.get("mesh") != batches[id].multimesh.mesh
		or cached.get("pose") != pose
		or cached.get("height") != height
	):
		var bounds := batches[id].multimesh.mesh.get_aabb()
		if not pose.is_empty():
			var first := true
			for tag in motion_bounds[id]:
				var part: AABB = motion_bounds[id][tag]
				for corner in 8:
					var point := ForestAnimalMotion.deform(
						part.get_endpoint(corner),
						tag,
						head_pivots[id],
						pose,
						height,
						wing_hinges[id]
					)
					bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
					first = false
		cached = {
			"mesh": batches[id].multimesh.mesh,
			"pose": pose.duplicate(),
			"height": height,
			"bounds": bounds
		}
		display_bounds_cache[id] = cached
	return {
		"transform": displayed_transforms[id], "bounds": displayed_transforms[id] * cached.bounds
	}


func selection_shape(id: int) -> Dictionary:
	if not displayed_transforms.has(id):
		selection_cache.erase(id)
		return {}
	var pose: PackedFloat32Array = animation_poses.get(id, PackedFloat32Array())
	var height: float = displayed_heights[id]
	var cached: Dictionary = selection_cache.get(id, {})
	if (
		cached.get("mesh") == batches[id].multimesh.mesh
		and cached.get("pose") == pose
		and cached.get("height") == height
		and cached.get("transform") == displayed_transforms[id]
	):
		return cached.shape
	var s: int = id
	var faces := mesh_faces[s]
	var bounds := batches[s].multimesh.mesh.get_aabb()
	if animation_poses.has(id):
		faces = faces.duplicate()
		bounds = AABB()
		for j in faces.size():
			faces[j] = ForestAnimalMotion.deform(
				faces[j],
				face_tags[s][j],
				head_pivots[s],
				animation_poses[id],
				height,
				wing_hinges[s]
			)
			bounds = AABB(faces[j], Vector3.ZERO) if j == 0 else bounds.expand(faces[j])
	var shape := {
		"transform": displayed_transforms[id],
		"faces": faces,
		"bounds": displayed_transforms[id] * bounds
	}
	selection_cache[id] = {
		"mesh": batches[id].multimesh.mesh,
		"pose": pose.duplicate(),
		"height": height,
		"transform": displayed_transforms[id],
		"shape": shape
	}
	return shape


func _motion_clip(id: int, traveling := false) -> String:
	var d: ForestAnimalDefinition = model.definitions[model.species[id]]
	var action: String = model.actions[id]
	var moving := action in ["seek_food", "seek_cover", "explore", "flee", "hunt", "search_prey"]
	var clip := "idle"
	if model.is_swimming(id):
		clip = "swim"
	elif moving or traveling:
		clip = "fly" if d.flight_height_m > 0 else ("hop" if d.gait == "hop" else "walk")
	elif action == "sleep":
		clip = "sleep"
	elif action in ["eat", "root"]:
		clip = "feed"
	elif action == "survey":
		clip = "alert"
	return clip if model.alive[id] else "idle"


func _animate(id: int, clip: String, t: float) -> void:
	if animation_clips.get(id) == clip and animation_times.get(id) == t:
		return
	var player := animation_players[id]
	var target := ForestAnimalMotion.sample(clip, t)
	if wing_hinges[id].x > 0:
		if t < animation_times.get(id, t):
			animation_transitions.erase(id)
		elif animation_clips.has(id) and animation_clips[id] != clip:
			animation_transitions[id] = {"from": animation_poses[id].duplicate(), "start": t}
		if animation_transitions.has(id):
			var transition: Dictionary = animation_transitions[id]
			var weight := smoothstep(0, .18, t - transition.start)
			for c in target.size():
				target[c] = lerpf(transition.from[c], target[c], weight)
			if weight >= 1:
				animation_transitions.erase(id)
	if animation_clips.get(id) != clip:
		player.play(clip)
	player.seek(fposmod(t, motion_library.get_animation(clip).length), true)
	if wing_hinges[id].x > 0:
		# Cross-fade on the displayed clock only; CPU picking gets this same pose.
		for c in target.size():
			batches[id].set_instance_shader_parameter(
				"pose_" + ForestAnimalMotion.curves.channels[c], target[c]
			)
	animation_clips[id] = clip
	animation_times[id] = t
	animation_poses[id] = target


# gdlint: disable=max-returns
static func valid_frame(frame: Variant, population: int) -> bool:
	if not frame is Dictionary:
		return false
	for key in ["end_s", "step_s"]:
		if not frame.get(key) is float or not is_finite(frame[key]) or frame[key] < 0:
			return false
	if frame.step_s <= 0 or not frame.get("bodies") is Array or frame.bodies.size() > population:
		return false
	for body in frame.bodies:
		if not body is Dictionary:
			return false
		if (
			not body.get("points") is PackedVector3Array
			or not body.get("times") is PackedFloat64Array
		):
			return false
		if body.points.is_empty() or body.points.size() != body.times.size():
			return false
		var previous := -1.0
		for k in body.points.size():
			if (
				not body.points[k].is_finite()
				or not is_finite(body.times[k])
				or body.times[k] < 0
				or body.times[k] < previous
			):
				return false
			previous = body.times[k]
		for key in ["basis", "start_basis"]:
			if (
				not body.get(key) is Basis
				or not body[key].is_finite()
				or body[key].determinant() <= 0
			):
				return false
		if not body.get("height") is float or not is_finite(body.height) or body.height <= 0:
			return false
		if not body.get("color") is Color:
			return false
		for channel in [body.color.r, body.color.g, body.color.b, body.color.a]:
			if not is_finite(channel):
				return false
		if not body.get("hidden") is bool or not body.get("alive") is bool:
			return false
		if body.get("clip") not in ["idle", "walk", "hop", "fly", "swim", "sleep", "feed", "alert"]:
			return false
		# Optional for older presentation buffers; never changes model/save versions.
		if (
			body.has("travel_clip")
			and body.travel_clip not in ["walk", "hop", "fly", "swim", "idle"]
		):
			return false
	return true
