extends SceneTree
## Benchmarks ChunkStreamer on the generated test city, then loads the whole
## city at once for comparison. Generate the city first with
## tools/generate_test_city.gd.
##
## Run with a window, so rendering is measured too:
##   godot --path . --script res://tools/benchmark_streaming.gd

## Driving speed across the city, in m/s. Roughly a car.
const SPEED := 25.0
const CITY_DIRECTORY := "res://world/test_city"


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var scene: Node = load("res://scenes/streaming_test.tscn").instantiate()
	root.add_child(scene)
	_run.call_deferred(scene)


func _run(scene: Node) -> void:
	# Night, so every street lamp is lit: the worst case for lighting.
	var clock: Node = root.get_node("GameClock")
	clock.minutes = 22.0 * 60.0
	clock.paused = true
	var player: Node3D = scene.get_node("Player")
	var streamer: ChunkStreamer = scene.get_node("World")
	player.set_physics_process(false)
	await _wait_frames(60)

	# --- Streaming: drive back and forth along a street through the middle.
	for pass_index in 2:
		var eastward := pass_index % 2 == 0
		player.global_position = Vector3(40.0 if eastward else 600.0, 0.0, 321.5)
		player.reset_physics_interpolation()
		await _wait_frames(90)
		var frame_times: Array[float] = []
		var most_placed := 0
		var last := Time.get_ticks_usec()
		while (player.global_position.x < 600.0) if eastward else (player.global_position.x > 40.0):
			await process_frame
			var now := Time.get_ticks_usec()
			var frame_ms := (now - last) / 1000.0
			last = now
			frame_times.append(frame_ms)
			player.global_position.x += (1.0 if eastward else -1.0) * SPEED * frame_ms / 1000.0
			most_placed = maxi(most_placed, streamer.placed_count())
		_report("STREAMING pass %d, drove 560 m at %d m/s (most chunks placed: %d)" % [
			pass_index + 1, SPEED, most_placed], frame_times)
	if OS.get_cmdline_user_args().has("--streaming-only"):
		quit()
		return

	# --- Everything at once, for comparison.
	streamer.target = null
	streamer.set_process(false)
	for child in streamer.get_children():
		child.free()
	await _wait_frames(10)
	var all := Node3D.new()
	all.name = "WholeCity"
	scene.add_child(all)
	var load_started := Time.get_ticks_msec()
	for path in DirAccess.get_files_at(CITY_DIRECTORY):
		if not path.ends_with(".scn"):
			continue
		var parts := path.trim_suffix(".scn").split("_")
		var chunk: Node3D = load(CITY_DIRECTORY + "/" + path).instantiate()
		chunk.position = Vector3(parts[1].to_int() * 32.0, 0.0, parts[2].to_int() * 32.0)
		all.add_child(chunk)
	print("\nWHOLE CITY: loaded all %d chunks in %.1f s" % [all.get_child_count(), (Time.get_ticks_msec() - load_started) / 1000.0])
	player.global_position = Vector3(321.5, 0.0, 321.5)
	player.reset_physics_interpolation()
	await _wait_frames(20)
	var frame_times: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in 150:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_times.append((now - last) / 1000.0)
		last = now
	_report("WHOLE CITY, standing in the middle", frame_times)
	quit()


func _report(title: String, frame_times: Array[float]) -> void:
	var sorted := frame_times.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	for ms in frame_times:
		total += ms
		if ms > 33.3:
			slow += 1
	var average := total / frame_times.size()
	print("\n%s" % title)
	print("  frames %d, average %.1f ms (%.0f fps), median %.1f ms, 99th percentile %.1f ms, worst %.1f ms, frames over 33 ms: %d" % [
		frame_times.size(), average, 1000.0 / average, sorted[sorted.size() / 2],
		sorted[int(sorted.size() * 0.99)], sorted[-1], slow])
	print("  nodes %d, objects %d, memory %.0f MB, video memory %.0f MB, draw calls %d" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _wait_frames(count: int) -> void:
	for i in count:
		await process_frame
