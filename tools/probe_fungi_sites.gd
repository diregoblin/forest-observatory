extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var s: ForestSettings = load("res://data/forest.tres").duplicate(true)
	var l := ForestLandscape.new(s)
	var w := ForestWatershed.new(l)
	var f := ForestFungi.new(w)
	for plot in f.plots:
		var sand := 0
		var fruit := 0
		var max_sand := 0.0
		var site_sum := Vector4.ZERO
		for k in plot.fields.fruit.size():
			var x: float = plot.origin.x + (k % s.fungi_resolution + .5) * s.fungi_cell_m
			var z: float = plot.origin.y + (k / s.fungi_resolution + .5) * s.fungi_cell_m
			var site := l.habitat_at(x,z)
			if plot.fields.fruit[k] > 1e-7:
				fruit += 1
				if site.w > .5:
					sand += 1
				max_sand = maxf(max_sand,site.w)
				site_sum += site
		print(plot.definition.display_name, " origin=",plot.origin," fruit=",fruit," sand=",sand," max=",max_sand," mean_site=",site_sum/maxi(1,fruit))
	quit()
