class_name ForestObserverCamera
extends Camera3D

var land: ForestLandscape
var barrier: ForestBarrier
var moving := false
var yaw := 0.0
var pitch := 0.0
var followed_id := -1
var followed_point := Vector3.ZERO


func follow(id: int, point: Vector3) -> void:
	moving = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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


func _process(dt: float) -> void:
	if not moving:
		return
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		direction -= self.global_basis.z
	if Input.is_physical_key_pressed(KEY_S):
		direction += self.global_basis.z
	if Input.is_physical_key_pressed(KEY_A):
		direction -= self.global_basis.x
	if Input.is_physical_key_pressed(KEY_D):
		direction += self.global_basis.x
	if Input.is_physical_key_pressed(KEY_Q):
		direction -= Vector3.UP
	if Input.is_physical_key_pressed(KEY_E):
		direction += Vector3.UP
	self.position += direction * dt * (65.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 23.0)
	self.position.x = clampf(self.position.x, 4, land.settings.extent - 4)
	self.position.z = clampf(self.position.z, 4, land.settings.extent - 4)
	self.position.y = maxf(self.position.y, land.height_at(self.position.x, self.position.z) + 1.8)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		stop_following()
		moving = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	stop_following()
	var target := Vector3(center.x, land.height_at(center.x, center.y) + .15, center.y)
	self.position = Vector3(
		center.x + 4.5, land.height_at(center.x + 4.5, center.y + 8.5) + 2.3, center.y + 8.5
	)
	self.look_at(target)
	yaw = self.rotation.y
	pitch = self.rotation.x


func view_spring() -> void:
	stop_following()
	var head := land.spring_position()
	var z := head.y + 17.0
	var x := land.ravine_x(z) + 3.0
	position = Vector3(x, land.height_at(x, z) + 4.0, z)
	look_at(Vector3(head.x, land.height_at(head.x, head.y) + .2, head.y))
	yaw = rotation.y
	pitch = rotation.x
