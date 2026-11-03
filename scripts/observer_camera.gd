class_name ForestObserverCamera
extends Camera3D

signal walking_changed(enabled: bool)

const EYE_HEIGHT := 1.7
const WALK_SPEED := 2.2
const FAST_WALK_SPEED := 5.0
const MAX_WALK_SLOPE := 1.1  # Rise/run; a camera constraint, not terrain physics.
const MAX_WADE_DEPTH := .45

var land: ForestLandscape
var barrier: ForestBarrier
var moving := false  # Looking with RMB; translation is independent of this.
var walking := false
var surface_height := Callable()
var water_surface := Callable()
var input_blocked := Callable()
var window_focused := true
var yaw := 0.0
var pitch := 0.0
var followed_id := -1
var followed_point := Vector3.ZERO


func follow(id: int, point: Vector3) -> void:
	set_walking(false)
	release_pointer()
	followed_id = id
	followed_point = point


func stop_following() -> void:
	followed_id = -1


func track_displayed(point: Vector3) -> void:
	# Translate the existing viewpoint with submitted geometry, not a model tick.
	# Its world-space angle and distance do not depend on the animal's heading.
	if followed_id < 0:
		return
	position += point - followed_point
	followed_point = point
	position.y = maxf(position.y, land.height_at(position.x, position.z) + .25)


func configure(landscape: ForestLandscape, obstacle: ForestBarrier) -> void:
	land = landscape
	barrier = obstacle
	far = 1800
	near = .3
	fov = 64
	current = true


func release_pointer() -> void:
	moving = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		window_focused = false
		release_pointer()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		window_focused = true


func controls_blocked() -> bool:
	if not window_focused or (input_blocked.is_valid() and input_blocked.call()):
		return true
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


func ground_at(point: Vector3) -> float:
	if surface_height.is_valid():
		var height: float = surface_height.call(point)
		if is_finite(height):
			return height
	return land.height_at(point.x, point.z)


func _shallow_enough(point: Vector3, ground: float) -> bool:
	if not water_surface.is_valid():
		return true
	var stage: Vector2 = water_surface.call(point)
	return stage.y <= .000001 or stage.x - ground <= MAX_WADE_DEPTH


func set_walking(enabled: bool, align_to_ground := true) -> bool:
	if enabled and align_to_ground:
		var ground := ground_at(position)
		if not _shallow_enough(position, ground):
			return false
		stop_following()
		position.y = ground + EYE_HEIGHT
	walking = enabled
	near = .1 if walking else .3
	walking_changed.emit(walking)
	return true


func move_input(axes: Vector3, fast: bool, dt: float) -> void:
	# Input is observer time, independent of pause, playback speed and model RNG.
	if axes.is_zero_approx() or dt <= 0:
		return
	stop_following()
	var direction: Vector3
	if walking:
		var forward := Vector3(-global_basis.z.x, 0, -global_basis.z.z).normalized()
		var right := Vector3(global_basis.x.x, 0, global_basis.x.z).normalized()
		direction = (right * axes.x + forward * -axes.z).limit_length()
		var distance := minf(dt, .1) * (FAST_WALK_SPEED if fast else WALK_SPEED)
		# Short samples cannot leap through a bank after a slow frame.
		var pieces := maxi(1, ceili(distance / .2))
		var step := direction * distance / pieces
		for piece in pieces:
			var candidate := _walk_candidate(position + step)
			if candidate == position:
				# Slide along a bank instead of sticking when moving diagonally.
				candidate = _walk_candidate(position + Vector3(step.x, 0, 0))
				position = candidate
				candidate = _walk_candidate(position + Vector3(0, 0, step.z))
			position = candidate
	else:
		direction = (
			(global_basis.x * axes.x + global_basis.z * axes.z + Vector3.UP * axes.y).limit_length()
		)
		position += direction * minf(dt, .1) * (65.0 if fast else 23.0)
		position.x = clampf(position.x, 4, land.settings.extent - 4)
		position.z = clampf(position.z, 4, land.settings.extent - 4)
		position.y = maxf(position.y, ground_at(position) + EYE_HEIGHT)


func _walk_candidate(point: Vector3) -> Vector3:
	point.x = clampf(point.x, 4, land.settings.extent - 4)
	point.z = clampf(point.z, 4, land.settings.extent - 4)
	var distance := Vector2(point.x - position.x, point.z - position.z).length()
	if distance <= .000001:
		return position
	var ground := ground_at(point)
	if absf(ground - ground_at(position)) > distance * MAX_WALK_SLOPE:
		return position
	if not _shallow_enough(point, ground):
		return position
	point.y = ground + EYE_HEIGHT
	return point


func _process(dt: float) -> void:
	if controls_blocked():
		release_pointer()
		return
	var axes := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		axes.z -= 1
	if Input.is_physical_key_pressed(KEY_S):
		axes.z += 1
	if Input.is_physical_key_pressed(KEY_A):
		axes.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		axes.x += 1
	if Input.is_physical_key_pressed(KEY_Q):
		axes.y -= 1
	if Input.is_physical_key_pressed(KEY_E):
		axes.y += 1
	move_input(axes, Input.is_physical_key_pressed(KEY_SHIFT), dt)


func _input(event: InputEvent) -> void:
	# A release over a menu/card must still release an earlier viewport capture.
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and not event.pressed
	):
		release_pointer()


func _unhandled_input(event: InputEvent) -> void:
	if controls_blocked():
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		stop_following()
		release_pointer()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			stop_following()
		moving = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if moving else Input.MOUSE_MODE_VISIBLE
		yaw = self.rotation.y
		pitch = self.rotation.x
	if event is InputEventMouseMotion and moving:
		yaw -= event.relative.x * .003
		pitch = clampf(pitch - event.relative.y * .003, -1.45, 1.45)
		self.rotation = Vector3(pitch, yaw, 0)


func view(n: int) -> void:
	set_walking(false)
	stop_following()
	var target: Vector3
	if n == 1:
		self.position = Vector3(.762, .303, .914) * land.settings.extent
		target = Vector3(.479, .043, .459) * land.settings.extent
	else:
		var center := (barrier.start + barrier.end) / 2
		var z := center.y + (53.0 if n == 2 else 42.0)
		var x := land.channel_x(z) + (20.0 if n == 2 else -38.0)
		self.position = Vector3(x, land.height_at(x, z) + (7.0 if n == 2 else 22.0), z)
		target = Vector3(land.channel_x(center.y - 17), barrier.crest - 1, center.y - 17)
	self.look_at(target)
	yaw = self.rotation.y
	pitch = self.rotation.x


func view_plot(center: Vector2) -> void:
	set_walking(false)
	stop_following()
	var target := Vector3(center.x, land.height_at(center.x, center.y) + .15, center.y)
	self.position = Vector3(
		center.x + 4.5, land.height_at(center.x + 4.5, center.y + 8.5) + 2.3, center.y + 8.5
	)
	self.look_at(target)
	yaw = self.rotation.y
	pitch = self.rotation.x


func view_spring() -> void:
	set_walking(false)
	stop_following()
	var head := land.spring_position()
	var z := head.y + 17.0
	var x := land.ravine_x(z) + 3.0
	position = Vector3(x, land.height_at(x, z) + 4.0, z)
	look_at(Vector3(head.x, land.height_at(head.x, head.y) + .2, head.y))
	yaw = rotation.y
	pitch = rotation.x
