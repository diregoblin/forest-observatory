extends RefCounted


static func run(world) -> void:
	world.paused = false
	var initial: Dictionary = world._world_snapshot()
	for tick in 16:
		world._advance_world(world.settings.ecology_step_s)
	var expected: Dictionary = world._world_snapshot().models
	assert(world._restore_world(initial))
	world.use_model_worker = true
	for tick in 16:
		world._process(world.settings.ecology_step_s)
		assert(world.model_work_active, "Live scene dispatches a coupled worker tick")
		world._finish_model_work(true)
	assert(
		world._world_snapshot().models == expected,
		"Worker has identical physics, budgets and RNG to synchronous reference"
	)
	world._process(world.settings.ecology_step_s)
	world._toggle_pause()
	assert(
		world.paused and not world.model_work_active,
		"Pause joins and commits the whole in-flight tick"
	)
	world._check_clock_alignment()
	var frozen: Dictionary = world._world_snapshot().models
	world._process(1)
	assert(world._world_snapshot().models == frozen)
	world._toggle_pause()
	world._process(world.settings.ecology_step_s)
	var saved: Dictionary = world._world_snapshot()
	assert(
		not world.model_work_active,
		"Saving commits the whole in-flight tick, never a partial world"
	)
	world._check_clock_alignment()
	world._set_speed(8)
	world._process(world.settings.ecology_step_s / 8)
	assert(
		world._restore_world(saved), "Loading waits for old work before restoring all participants"
	)
	assert(world._world_snapshot().models == saved.models)
	world._process(world.settings.ecology_step_s / world.sim_speed)
	assert(world.model_work_active)
	world.hud.fungi_map_requested.emit()
	assert(not world.model_work_active and world.hud.fungi_map.visible)
	world._check_clock_alignment()
	world.hud.fungi_map_requested.emit()
	assert(not world.hud.fungi_map.visible)
	world.use_model_worker = false
	assert(world._restore_world(initial))
	(
		FileAccess
		. open("res://artifacts/worker-check.json", FileAccess.WRITE)
		. store_string(
			(
				JSON
				. stringify(
					{
						"passed": true,
						"same_16_ticks_as_sync_reference": true,
						"pause_commits_in_flight_tick": true,
						"save_load_join_worker": true,
						"fungi_map_joins_busy_worker": true,
						"boundary":
						"Single owned worker, no partial model reads by the scene; no concurrent model writers"
					},
					"  "
				)
			)
		)
	)
	print("WORKER_CHECK passed")
