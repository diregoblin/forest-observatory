# Negative control: the old debt-driven playback, on the same coupled models.
extends "res://scripts/forest.gd"


func _advance_presentation(_dt := 0.0) -> void:
	if presentation_frames.is_empty():
		return
	if not paused:
		var requested := ecology_clock.elapsed_s + ecology_clock.pending_s
		presentation_s = maxf(
			presentation_s,
			minf(maxf(0, requested - 2 * settings.ecology_step_s), presentation_frames[-1].end_s)
		)
	_draw_presentation()
	atmosphere.set_season(_display_climate())
	terrain.set_surface_season(_display_climate())
