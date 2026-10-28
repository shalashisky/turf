extends Label
## Debug readout of performance numbers, for judging world streaming.

@export var streamer: ChunkStreamer


func _process(_delta: float) -> void:
	text = "FPS %d  (%.1f ms process)\nChunks placed %d\nNodes %d   objects %d\nMemory %.0f MB   video %.0f MB\nDraw calls %d" % [
		Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		streamer.placed_count() if streamer else 0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	]
