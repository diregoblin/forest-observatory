extends Node

## One shared World3D, one low-resolution render, full-resolution UI.
## The observer remains in its original viewport (terrain LOD, controls, saves).
## Only its presentation camera is mirrored here. No model state is accessed.
var observer: Camera3D
var source_viewport: Viewport
var viewport: SubViewport
var render_camera: Camera3D
var output: CanvasLayer
var image: TextureRect
var backdrop: ColorRect
var enabled := false
var pixel_scale := 1
var original_disable_3d := false


func configure(camera: Camera3D) -> void:
	observer = camera
	source_viewport = camera.get_viewport()
	original_disable_3d = source_viewport.disable_3d
	process_priority = 100  # After controller/follow updates, before rendering.
	viewport = SubViewport.new()
	render_camera = Camera3D.new()
	output = CanvasLayer.new()
	image = TextureRect.new()
	viewport.name = "PixelWorld"
	viewport.world_3d = source_viewport.world_3d
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Coverage antialiasing at the artistic pixel grid, never temporal history.
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	viewport.add_child(render_camera)
	render_camera.current = true
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	output.layer = -10
	output.visible = false
	add_child(output)
	backdrop = ColorRect.new()
	backdrop.color = Color(.015, .025, .03)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	output.add_child(backdrop)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.texture = viewport.get_texture()
	var grade := ShaderMaterial.new()
	grade.shader = preload("res://shaders/pixel_palette.gdshader")
	image.material = grade
	output.add_child(image)
	source_viewport.size_changed.connect(_resize)
	_resize()
	_sync_camera()
	set_process(false)


func set_enabled(value: bool) -> void:
	enabled = value
	set_process(enabled and source_viewport != null)
	if source_viewport == null:
		return
	if enabled:
		_resize()
		_sync_camera()
	source_viewport.disable_3d = true if enabled else original_disable_3d
	viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	)
	output.visible = enabled


func _resize() -> void:
	# Redot's root ViewportTexture.get_size() includes stretch a second time;
	# Window.size matches the actual render-target image (verified by readback).
	var full: Vector2i = source_viewport.get("size")
	backdrop.size = Vector2(full)
	# Cancel project canvas_items stretching for this layer only. Artistic pixels
	# stay square/integer in the physical window; the HUD keeps its normal scaling.
	output.transform = source_viewport.get_final_transform().affine_inverse()
	# 1440x900 -> 480x300; 1920x1080 -> 480x270. Whole screen pixels only.
	pixel_scale = maxi(1, int(full.y / 270))
	viewport.size = Vector2i(maxi(1, full.x / pixel_scale), maxi(1, full.y / pixel_scale))
	image.size = Vector2(viewport.size * pixel_scale)
	image.position = Vector2(Vector2i((Vector2(full) - image.size) * .5))


func _process(_dt: float) -> void:
	_sync_camera()


func _sync_camera() -> void:
	render_camera.global_transform = observer.global_transform
	render_camera.projection = observer.projection
	render_camera.keep_aspect = observer.keep_aspect
	render_camera.fov = observer.fov
	render_camera.size = observer.size
	render_camera.near = observer.near
	render_camera.far = observer.far
	render_camera.h_offset = observer.h_offset
	render_camera.v_offset = observer.v_offset
	render_camera.frustum_offset = observer.frustum_offset
	render_camera.cull_mask = observer.cull_mask
	render_camera.attributes = observer.attributes
	render_camera.environment = observer.environment


func contains_screen_point(point: Vector2) -> bool:
	var physical := source_viewport.get_final_transform() * point
	return not enabled or Rect2(image.position, image.size).has_point(physical)


func _pixel_point(point: Vector2) -> Vector2:
	# Select through the centre of the actual displayed pixel, including resize bars.
	var physical := source_viewport.get_final_transform() * point
	return ((physical - image.position) / pixel_scale).floor() + Vector2(.5, .5)


func ray_origin(point: Vector2) -> Vector3:
	return (
		render_camera.project_ray_origin(_pixel_point(point))
		if enabled
		else observer.project_ray_origin(point)
	)


func ray_normal(point: Vector2) -> Vector3:
	return (
		render_camera.project_ray_normal(_pixel_point(point))
		if enabled
		else observer.project_ray_normal(point)
	)


func screen_position(point: Vector3) -> Vector2:
	if enabled:
		var physical: Vector2 = (
			image.position + render_camera.unproject_position(point) * pixel_scale
		)
		return source_viewport.get_final_transform().affine_inverse() * physical
	return observer.unproject_position(point)


func frame_times() -> Dictionary:
	# The root only draws the composition/UI in pixel mode; measuring it alone
	# would silently omit the cost of the entire forest.
	var world_rid := viewport.get_viewport_rid() if enabled else source_viewport.get_viewport_rid()
	var composition_rid := source_viewport.get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(world_rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(world_rid)
	var composition_gpu := 0.0
	var composition_cpu := 0.0
	if enabled:
		composition_gpu = RenderingServer.viewport_get_measured_render_time_gpu(composition_rid)
		composition_cpu = RenderingServer.viewport_get_measured_render_time_cpu(composition_rid)
	return {
		"world_gpu_ms": gpu,
		"world_cpu_ms": cpu,
		"composition_gpu_ms": composition_gpu,
		"composition_cpu_ms": composition_cpu,
		"gpu_ms": gpu + composition_gpu,
		"cpu_ms": cpu + composition_cpu
	}


func _exit_tree() -> void:
	if is_instance_valid(source_viewport):
		source_viewport.disable_3d = original_disable_3d
