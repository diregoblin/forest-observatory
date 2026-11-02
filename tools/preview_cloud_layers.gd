extends "res://tools/preview_cloud_edges.gd"


func _initialize() -> void:
	super._initialize()
	output = "res://artifacts/cloud-layers"


func reference_path() -> String:
	return "/run/media/pavel/Storage/tmp/forest-sky-timeline-20261102/shaders/painterly_sky.gdshader"


func extra_captures() -> void:
	scene.camera.position = Vector3(200, scene.land.height_at(200, 196) + 2.0, 196)
	scene.camera.look_at(scene.camera.position + Vector3(0, .22, -1))
	var material: ShaderMaterial = scene.painterly_style.sky_material
	var full := await capture("two-layers")
	material.set_shader_parameter("upper_cloud_opacity", 0.0)
	var low := await capture("low-only-control")
	assert(difference(full, low) > .0001, "Upper tier must have a visible contribution")
	material.set_shader_parameter("upper_cloud_opacity", .32)
	material.set_shader_parameter("lower_cloud_opacity", 0.0)
	var high := await capture("high-only-control")
	assert(difference(full, high) > .0001, "Lower tier must have a visible contribution")
	material.set_shader_parameter("lower_cloud_opacity", 1.0)
	var climate: Dictionary = scene.atmosphere.displayed_weather.duplicate()
	climate.weather_time_s = 25.0
	scene.atmosphere.set_season(climate)
	var shifted := await capture("two-layers-wind")
	assert(difference(full, shifted) > .0001)
