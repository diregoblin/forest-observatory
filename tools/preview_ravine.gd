extends SceneTree
var scene
var output := "res://artifacts/ravine-natural"
func _initialize():
	create_timer(80).timeout.connect(func():quit(1))
	_run.call_deferred()
func photo(label):
	for frame in 8: await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK)
func _run():
	DirAccess.make_dir_recursive_absolute(output)
	scene=load("res://scripts/forest.gd").new()
	scene.paused=true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.capture_dir=""
	scene.hud.visible=false
	Engine.max_fps=30
	var head: Vector2=scene.land.spring_position()
	var target=Vector3(211,scene.land.height_at(211,140),140)
	scene.camera.position=target+Vector3(-28,48,5)
	scene.camera.look_at(target)
	await photo("01-overview")
	scene.vegetation.visible=false
	scene.turf_cards.visible=false
	scene.habitat_view.visible=false
	await photo("02-bare-banks")
	scene.vegetation.visible=true
	scene.turf_cards.visible=true
	scene.habitat_view.visible=true
	scene.camera.position=Vector3(head.x+4,scene.land.height_at(head.x+4,head.y+4)+2.5,head.y+4)
	scene.camera.look_at(Vector3(scene.land.ravine_x(head.y+32),scene.land.height_at(scene.land.ravine_x(head.y+32),head.y+32)+1,head.y+32))
	await photo("03-from-spring")
	scene.free()
	quit()
