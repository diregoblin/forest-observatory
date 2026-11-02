extends RefCounted

## Port shim: compile the unchanged GLSL through the supported RenderingDevice
## API. This editor build crashes in its parallel GLSL resource importer.
## Cache bytecode by source content for the current process/device only.
static var bytecode := {}


static func load_file(path: String) -> RDShaderFile:
	var source := FileAccess.get_file_as_string(path).replace("#[compute]", "")
	var key := path + ":" + source.sha256_text()
	if bytecode.has(key):
		return bytecode[key]
	var device := RenderingServer.get_rendering_device()
	if device == null:
		push_error("GPU fluid requires a RenderingDevice")
		return null
	var input := RDShaderSource.new()
	input.source_compute = source
	var spirv := device.shader_compile_spirv_from_source(input)
	if not spirv.compile_error_compute.is_empty():
		push_error(spirv.compile_error_compute)
		return null
	var file := RDShaderFile.new()
	file.set_bytecode(spirv)
	bytecode[key] = file
	return file
