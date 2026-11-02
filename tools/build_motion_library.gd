extends SceneTree


func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/animation/animal_motion.json")
	)
	var library := AnimationLibrary.new()
	for clip in source.clips:
		var data: Dictionary = source.clips[clip]
		var animation := Animation.new()
		animation.length = data.duration
		animation.loop_mode = Animation.LOOP_LINEAR
		for c in source.channels.size():
			var track := animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(
				track, NodePath(".:instance_shader_parameters/pose_" + source.channels[c])
			)
			animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
			for i in data.samples.size():
				animation.track_insert_key(
					track, data.duration * i / (data.samples.size() - 1), data.samples[i][c]
				)
		library.add_animation(clip, animation)
	assert(ResourceSaver.save(library, "res://data/animation/animal_motion.tres") == OK)
	print("MOTION_LIBRARY ", library.get_animation_list())
	quit()
