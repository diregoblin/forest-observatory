extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var camera := Camera3D.new()
	host.add_child(camera)
	var terrain := Terrain3D.new()
	terrain.region_size = 64
	terrain.collision_mode = 0
	host.add_child(terrain)
	terrain.set_camera(camera)
	assert(terrain.version.begins_with("1.1.0"))
	var asset := Terrain3DTextureAsset.new()
	asset.set_asset_name("API migration fixture")
	var albedo := Image.create(8, 8, true, Image.FORMAT_RGBA8)
	albedo.fill(Color(.3, .4, .2, .5))
	asset.albedo_texture = ImageTexture.create_from_image(albedo)
	var normal := Image.create(8, 8, true, Image.FORMAT_RGBA8)
	normal.fill(Color(.5, .5, 1, .9))
	asset.normal_texture = ImageTexture.create_from_image(normal)
	terrain.assets.set_texture_asset(0, asset)
	var image := Image.create(64, 64, false, Image.FORMAT_RF)
	for z in 64:
		for x in 64:
			image.set_pixel(x, z, Color(2.0 * x + 3.0 * z, 0, 0))
	terrain.data.import_images([image, null, null], Vector3.ZERO, 0, 1)
	terrain.material.world_background = 0
	var heights := []
	var raw_differs := false
	# Analytical sloping plane: interpolation must preserve every fractional point.
	# A raw nearest-vertex lookup is a known wrong substitute for ground anchoring.
	for p in [Vector3(20.25, 0, 22.75), Vector3(31.6, 0, 37.4), Vector3(41.75, 0, 15.3)]:
		var expected: float = 2.0 * p.x + 3.0 * p.z
		var actual: float = terrain.data.get_surface_height(p)
		assert(absf(actual - expected) < .0001)
		raw_differs = raw_differs or absf(terrain.data.get_height(p) - expected) > .1
		heights.append(actual)
	assert(raw_differs)
	assert(terrain.assets.get_texture_asset(0).get_asset_name() == "API migration fixture")
	terrain.material.max_regions = 64
	assert(terrain.data.get_region_count() == 1)
	assert(absf(terrain.data.get_surface_height(Vector3(20.25, 0, 22.75)) - heights[0]) < .0001)
	var report := {
		"passed": true,
		"version": terrain.version,
		"analytical_plane_samples": heights,
		"raw_height_rejected_for_surface_placement": raw_differs,
		"texture_asset_api": true,
		"region_limit_preserves_surface": true
	}
	FileAccess.open("res://artifacts/terrain-upgrade-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("TERRAIN_UPGRADE_CHECK ", JSON.stringify(report))
	host.free()
	quit()
