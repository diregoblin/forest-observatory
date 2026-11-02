extends "res://tools/check_fauna_geometry.gd"


func _run() -> void:
	var s := specimen("thrush")
	var view: ForestAnimalsView = s.view
	var frozen: Dictionary = s.model.snapshot()
	var hinge: Vector3 = view.wing_hinges[0]
	var height: float = view.displayed_heights[0]
	var folded := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
	var spread := folded.duplicate()
	spread[7] = 1
	var folded_bounds := AABB()
	var spread_bounds := AABB()
	for i in view.mesh_faces[0].size():
		var p: Vector3 = view.mesh_faces[0][i]
		var tag: Color = view.face_tags[0][i]
		var f := ForestAnimalMotion.deform(p, tag, view.head_pivots[0], folded, height, hinge)
		var u := ForestAnimalMotion.deform(p, tag, view.head_pivots[0], spread, height, hinge)
		folded_bounds = AABB(f, Vector3.ZERO) if i == 0 else folded_bounds.expand(f)
		spread_bounds = AABB(u, Vector3.ZERO) if i == 0 else spread_bounds.expand(u)
	assert(spread_bounds.size.x > .42 and spread_bounds.size.x > folded_bounds.size.x * 2)
	# Both sides keep the wrist attached to the same parent wing at every phase.
	for side in [-1.0, 1.0]:
		var wrist := Vector3(side * .155, .213, -.020)
		for i in 49:
			var pose := ForestAnimalMotion.sample("fly", .24 * i / 48)
			var a := ForestAnimalMotion.deform(
				wrist, Color(wrist.x, wrist.y, wrist.z, 6), Vector3.ZERO, pose, height, hinge
			)
			var b := ForestAnimalMotion.deform(
				wrist, Color(wrist.x, wrist.y, wrist.z, 7), Vector3.ZERO, pose, height, hinge
			)
			assert(a.distance_to(b) < .00001)
	# Flat wings really travel above and below the shoulder, not a small shrug.
	var tip := Vector3(.265, .213, -.04)
	var pivot := Color(.155, .213, -.020, 7)
	var up := ForestAnimalMotion.deform(
		tip, pivot, Vector3.ZERO, ForestAnimalMotion.sample("fly", 0), height, hinge
	)
	var down := ForestAnimalMotion.deform(
		tip, pivot, Vector3.ZERO, ForestAnimalMotion.sample("fly", .12), height, hinge
	)
	assert(up.y - down.y > .20)
	# Transitions begin at the previous visible pose and finish on authored curves.
	view.animation_transitions.clear()
	view._animate(0, "idle", 10.0)
	var before: PackedFloat32Array = view.animation_poses[0].duplicate()
	view._animate(0, "fly", 10.0)
	assert(view.animation_poses[0] == before, "Takeoff must not pop to an unfolded wing")
	var previous := view.selection_shape(0).faces as PackedVector3Array
	var largest_step := 0.0
	for i in range(1, 81):
		view._animate(0, "fly", 10 + i * .005)
		var now: PackedVector3Array = view.selection_shape(0).faces
		for j in range(0, now.size(), 13):
			largest_step = maxf(largest_step, now[j].distance_to(previous[j]))
		previous = now
	assert(largest_step < .045)
	assert(view.animation_poses[0] == ForestAnimalMotion.sample("fly", 10.4))
	before = view.animation_poses[0].duplicate()
	view._animate(0, "idle", 10.4)
	assert(view.animation_poses[0] == before, "Landing must start at the visible flight pose")
	view._animate(0, "idle", 10.7)
	assert(view.animation_poses[0][7] == 0)
	assert(s.model.snapshot() == frozen)
	# Rewinding a display buffer cannot leave a transition with a future timestamp.
	view._animate(0, "fly", 2)
	assert(view.animation_transitions.is_empty())
	assert(view.animation_poses[0] == ForestAnimalMotion.sample("fly", 2))
	var report := {
		"passed": true,
		"folded_span_m": folded_bounds.size.x,
		"spread_span_m": spread_bounds.size.x,
		"tip_vertical_travel_m": up.y - down.y,
		"largest_5ms_transition_step_m": largest_step,
		"two_sided_wrist_contact_cases": 98,
		"unchanged_model": true
	}
	FileAccess.open("res://artifacts/bird-flight-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("BIRD_FLIGHT PASS ", JSON.stringify(report))
	view.free()
	quit()
