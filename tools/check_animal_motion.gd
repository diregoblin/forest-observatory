extends SceneTree


func _initialize() -> void:
	var library: AnimationLibrary = load("res://data/animation/animal_motion.tres")
	var channels: Array = ForestAnimalMotion.curves.channels
	assert(library.get_animation_list().size() == 8)
	for clip in library.get_animation_list():
		var animation := library.get_animation(clip)
		assert(animation.get_track_count() == channels.size())
		for i in 97:
			var t := animation.length * i / 97.0
			var pose := ForestAnimalMotion.sample(clip, t)
			for c in channels.size():
				assert(
					(
						str(animation.track_get_path(c))
						== ".:instance_shader_parameters/pose_" + channels[c]
					)
				)
				assert(
					absf(animation.value_track_interpolate(c, t) - pose[c]) < 1e-6,
					"CPU picking and AnimationPlayer must use identical authored curves"
				)
	# Definition-derived right-handed rotations. A reversed Z rotation fails this.
	var pose := PackedFloat32Array([0, 0, 0, 0, 0, 0, PI / 2])
	var wing := ForestAnimalMotion.deform(
		Vector3(2, 0, 0), Color(1, 0, 0, 5), Vector3.ZERO, pose, 1
	)
	assert(wing.distance_to(Vector3(1, 1, 0)) < 1e-6)
	pose = PackedFloat32Array([0, 0, PI / 2, 0, 0, 0, 0])
	var ear := ForestAnimalMotion.deform(Vector3(2, 0, 0), Color(1, 0, 0, 2), Vector3.ZERO, pose, 1)
	assert(ear.distance_to(Vector3(1, 1, 0)) < 1e-6)
	pose = PackedFloat32Array([PI / 2, 0, 0, 0, 0, 0, 0])
	var leg := ForestAnimalMotion.deform(
		Vector3(-1, 1, 0), Color(-1, 0, 0, 3), Vector3.ZERO, pose, 1
	)
	assert(leg.distance_to(Vector3(-1, 0, 1)) < 1e-6)
	var report := {
		"passed": true,
		"clips": 8,
		"sample_times_per_clip": 97,
		"channels": channels.size(),
		"native_animation_and_cpu_curves_equal": true,
		"right_handed_ears_wings_legs": true
	}
	FileAccess.open("res://artifacts/animal-motion-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("ANIMAL_MOTION_CHECK ", JSON.stringify(report))
	quit()
