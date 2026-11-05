extends SceneTree


func _initialize() -> void:
	# Reproducible immutable numerical input shared by CPU forcing and GPU sky.
	# Only this offline tool creates the tile; runtime reads the same PNG bytes.
	var noise := FastNoiseLite.new()
	noise.seed = 78371
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = .026
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = .25
	noise.domain_warp_enabled = true
	noise.domain_warp_amplitude = 12
	noise.domain_warp_frequency = .012
	var image := noise.get_seamless_image(512, 512, false, false, .2)
	image.convert(Image.FORMAT_L8)
	assert(image.save_png("res://art/clouds/weather-density.png") == OK)
	print("CLOUD_DENSITY_BUILT ", FileAccess.get_sha256("res://art/clouds/weather-density.png"))
	quit()
