extends SceneTree

var scene
var output := "res://artifacts/site-surface-render"


func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	_run.call_deferred()


func photo(label: String) -> void:
	scene.painterly_style._process(0)
	for frame in 4:
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.hud.visible = false
	Engine.max_fps = 30
	scene.terrain.advance_ecology_display(1)
	var best := [-INF, -INF, -INF, -INF]
	var points := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var colors := [
		Color(.07, .24, .12), Color(.49, .63, .24), Color(.15, .46, .32), Color(.76, .67, .47)
	]
	for z in 256:
		for x in 256:
			var px := (x + .5) * 2.0
			var pz := (z + .5) * 2.0
			var site: Vector4 = scene.land.habitat_at(px, pz)
			var color := Color(0, 0, 0)
			for k in 4:
				color += colors[k] * site[k]
				var preference: float = site[k] - Vector2(px - 240, pz - 270).length() * .00015
				if (
					scene.water.depth[scene.water.index_at(px, pz)] < .001
					and preference > best[k]
					and px > 25
					and px < 487
					and pz > 25
					and pz < 487
				):
					best[k] = preference
					points[k] = Vector3(px, scene.land.height_at(px, pz), pz)
			image.set_pixel(x, z, color)
	image.save_png(output.path_join("00-site-map.png"))
	scene.camera.position = Vector3(256, 420, 600)
	scene.camera.look_at(Vector3(256, 35, 245))
	await photo("01-overview")
	var labels := ["forest", "clearing", "wet-meadow", "sand"]
	for k in 4:
		var p: Vector3 = points[k]
		scene.camera.position = p + Vector3(14, 15, 20)
		scene.camera.look_at(p)
		await photo("02-" + labels[k])
		scene.vegetation.visible = false
		scene.camera.position = p + Vector3(0, 3, 4)
		scene.camera.look_at(p)
		await photo("03-surface-" + labels[k])
		scene.vegetation.visible = true
	var p: Vector3 = points[1]
	for i in 20:
		var pos := p + Vector3((i - 10) * .7, 0, 0)
		pos.y = scene.land.height_at(pos.x, pos.z)
		scene.habitat.tracks.append(
			{
				"position": pos,
				"yaw": PI / 2,
				"animal": 0,
				"size": .48,
				"born_s": 0.0,
				"life_s": 45.0 * ForestClimate.DAY_S
			}
		)
	scene.habitat_view.refresh(scene._display_climate())
	scene.vegetation.visible = false
	scene.camera.position = p + Vector3(0, 1.2, 1.8)
	scene.camera.look_at(p)
	scene.habitat_view.advance_display()
	print(
		"TRACK_RENDER ",
		scene.habitat_view.footprints.multimesh.visible_instance_count,
		" ",
		scene.habitat_view.footprints.multimesh.get_instance_transform(20),
		" camera ",
		scene.camera.position
	)
	await photo("04-tracks-fresh")
	scene.habitat.elapsed_s = 30.0 * ForestClimate.DAY_S
	scene.habitat_view.refresh(scene._display_climate())
	await photo("05-tracks-aged")
	# The same layered material in all three shipped presentation styles.
	scene.vegetation.visible = true
	for mode in 3:
		scene.painterly_style.set_mode(mode)
		var target: Vector3 = points[0]
		scene.camera.position = target + Vector3(8, 5, 10)
		scene.camera.look_at(target)
		await photo("06-style-%d" % mode)
	# The user's visual reference is the ordinary valley camera, not the aerial map.
	scene.camera.view(1)
	scene.terrain.set_surface_season(scene._display_climate())
	await photo("07-reference-spring")
	scene.season_preview = 4
	var autumn: Dictionary = scene._display_climate()
	scene.vegetation.refresh_trees(autumn)
	scene.atmosphere.set_season(autumn)
	scene.terrain.set_surface_season(autumn)
	await photo("08-reference-autumn")
	var result := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"points": points,
		"boundary":
		"Read-only site presentation. Track ages/positions are an isolated visual fixture."
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(result, "  ")
	)
	print("SITE_SURFACE_RENDER ", JSON.stringify(result))
	quit()
