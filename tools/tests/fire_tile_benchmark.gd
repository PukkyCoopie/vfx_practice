extends SceneTree
## Graphical benchmark; GPU timings are device-specific, not a phone FPS estimate.
## --baseline-dir=<absolute directory> optionally loads saved pre-change shaders.
var tiles: Array[Node] = []
func _initialize() -> void:
	call_deferred("run")
func stats(values: Array[float]) -> Dictionary:
	values.sort()
	var sum := 0.0
	for value in values: sum += value
	return {"median_ms": values[values.size() / 2], "p95_ms": values[int(values.size() * 0.95)], "mean_ms": sum / values.size()}
func run() -> void:
	root.size = Vector2i(750, 1000)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var baseline: Array[Shader] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-dir="):
			for name in ["fire_tile_flames.gdshader", "fire_tile_ribbons.gdshader"]:
				var shader := Shader.new()
				shader.code = FileAccess.get_file_as_string(arg.trim_prefix("--baseline-dir=").path_join(name))
				baseline.append(shader)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var results := {"gpu": RenderingServer.get_video_adapter_name(), "resolution": "750x1000", "runs": []}
	for scenario in [{"count": 1, "moving": 0}, {"count": 20, "moving": 0}, {"count": 20, "moving": 1}, {"count": 20, "moving": 20}]:
		for tile in tiles: tile.queue_free()
		tiles.clear()
		await process_frame
		for i in scenario.count:
			var tile = load("res://scenes/effects/fire_tile.tscn").instantiate()
			root.add_child(tile)
			if not baseline.is_empty():
				tile._mat.shader = baseline[0]
				tile._ribbon_mat.shader = baseline[1]
			tile._motion.set_process(false)
			tile._motion.set_process_input(false)
			tile._motion.set_process_unhandled_input(false)
			tile._motion.center = Vector2(140 + (i % 4) * 150, 140 + (i / 4) * 170)
			tile._motion._place()
			tile._time = i * 0.173
			for node in tile._holder.get_parent().get_children():
				if node is Label: node.hide()
			if i < scenario.moving: tile.set_motion_velocity(Vector2(900, -200))
			tiles.append(tile)
		for frame in 90: await process_frame
		var wall: Array[float] = []
		var gpu: Array[float] = []
		var last := Time.get_ticks_usec()
		# Cover six seconds of identical animation phases, independent of FPS.
		for frame in 360:
			for i in tiles.size(): tiles[i]._time = frame / 60.0 + i * 0.173
			await process_frame
			var now := Time.get_ticks_usec()
			wall.append((now - last) / 1000.0)
			last = now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		var row: Dictionary = scenario.duplicate()
		row["wall"] = stats(wall)
		row["gpu"] = stats(gpu)
		row["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		results.runs.append(row)
		print(JSON.stringify(row))
	var out := "user://fire_tile_perf.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  "))
	quit()
