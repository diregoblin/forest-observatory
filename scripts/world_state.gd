class_name ForestWorldState
extends RefCounted

## Versioned whole-world snapshots. Model registries share one transactional path.
const VERSION := 1
const MAX_FILE_BYTES := 128 * 1024 * 1024


static func capture(models: Dictionary, configuration: Dictionary, scene: Dictionary) -> Dictionary:
	var snapshots := {}
	for key in models:
		snapshots[key] = models[key].snapshot()
	return {"version": VERSION, "configuration": configuration.duplicate(true),
		"models": snapshots, "scene": scene.duplicate(true)}


static func restore(models: Dictionary, configuration: Dictionary, state: Dictionary) -> bool:
	if state.get("version") != VERSION or state.get("configuration") != configuration:
		return false
	if not state.get("models") is Dictionary or not state.get("scene") is Dictionary:
		return false
	if state.models.size() != models.size():
		return false
	for key in models:
		if not state.models.get(key) is Dictionary:
			return false
	var previous := {}
	for key in models:
		previous[key] = models[key].snapshot()
	for key in models:
		if not models[key].restore(state.models[key]):
			# Some earlier models may have accepted. Restore every participant,
			# in the original dependency order, before reporting a failed load.
			for restore_key in models:
				var restored: bool = models[restore_key].restore(previous[restore_key])
				assert(restored, "Internal rollback of a valid snapshot must succeed")
			return false
	return true


static func write(path: String, state: Dictionary) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var staged := absolute + ".tmp"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(state, false)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	# Same-filesystem rename leaves the old file intact if writing failed.
	return DirAccess.rename_absolute(staged, absolute)


static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return {}
	var state: Variant = file.get_var(false)  # Never instantiate objects from a save.
	return state if state is Dictionary else {}
