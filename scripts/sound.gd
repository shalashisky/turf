extends Node
## Plays the game's sound, autoloaded as Sound. Sounds are WAVs in res://audio
## by name (placeholders from tools/make_placeholder_sounds.py, until real
## recordings replace them): sound effects out in the world (play_at()) or
## flat, like menu clicks (play()); loops that hang off something, like a
## car's engine (loop_on()); and the background: rain and city noise outdoors,
## and the car radio while the player's driving.
##
## Sound in the world is heard from the player, not the camera: the camera
## hangs high above the street, and from up there everything nearby would
## sound far off and muffled.
##
## Three buses under Master, so they can each be turned up or down: SFX,
## Ambience and Music.

const AUDIO_DIR := "res://audio/%s.wav"
## Sounds this far from the player can't be heard.
const MAX_DISTANCE := 50.0
## Sounds are at full volume this close to the player, and fade with distance.
const UNIT_SIZE := 6.0
## The player hears from about head height.
const EAR_HEIGHT := 1.5
## How long the background takes to fade in or out, in seconds.
const FADE_TIME := 1.5

const BUSES := {"SFX": 0.0, "Ambience": -6.0, "Music": -9.0}

var _streams := {}
var _rain: AudioStreamPlayer
var _city: AudioStreamPlayer
var _radio: AudioStreamPlayer
var _ears: AudioListener3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
			AudioServer.set_bus_volume_db(index, BUSES[bus])
	_rain = _background("rain_loop", "Ambience")
	_city = _background("city_loop", "Ambience")
	_radio = _background("radio_loop", "Music")


func _process(delta: float) -> void:
	_follow_player_with_ears()
	# Outdoors is wherever it can rain.
	var outdoors := get_tree().get_first_node_in_group("rain") != null and not get_tree().paused
	var player := get_tree().get_first_node_in_group("player") as Citizen
	var driving := player != null and player.vehicle != null and not get_tree().paused
	_fade(_rain, Weather.intensity if outdoors else 0.0, delta)
	_fade(_city, 0.7 if outdoors else 0.0, delta)
	_fade(_radio, 1.0 if driving else 0.0, delta)


## Keeps a listener on the player in whatever scene is up, so 3D sound is
## heard from where they stand.
func _follow_player_with_ears() -> void:
	var scene := get_tree().current_scene
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if scene == null or player == null:
		return
	if not is_instance_valid(_ears) or _ears.get_parent() != scene:
		_ears = AudioListener3D.new()
		scene.add_child(_ears)
		_ears.make_current()
	_ears.global_position = player.global_position + Vector3.UP * EAR_HEIGHT


## The sound called `name`, or null if there's no such file. A sound with
## variations (name_1.wav, name_2.wav, ...) gives a random one each time.
## Loops (names ending in _loop) come set to loop.
func stream(name: StringName) -> AudioStream:
	if name == &"":
		return null
	if not _streams.has(name):
		_streams[name] = _load_variations(name)
	var choices: Array = _streams[name]
	return choices.pick_random() if not choices.is_empty() else null


func _load_variations(name: StringName) -> Array:
	var paths: Array[String] = []
	if ResourceLoader.exists(AUDIO_DIR % name):
		paths.append(AUDIO_DIR % name)
	else:
		var i := 1
		while ResourceLoader.exists(AUDIO_DIR % ("%s_%d" % [name, i])):
			paths.append(AUDIO_DIR % ("%s_%d" % [name, i]))
			i += 1
	var loaded := []
	for path in paths:
		var sound: AudioStreamWAV = load(path)
		if String(name).ends_with("_loop"):
			sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
			sound.loop_begin = 0
			sound.loop_end = sound.data.size() / 2
		loaded.append(sound)
	return loaded


## Plays `name` once at `at` in the world, a little higher or lower each time
## so repeats don't sound canned.
func play_at(name: StringName, at: Vector3, volume_db := 0.0, pitch_spread := 0.08) -> void:
	var sound := stream(name)
	var scene := get_tree().current_scene
	if sound == null or scene == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = sound
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.pitch_scale = randf_range(1.0 - pitch_spread, 1.0 + pitch_spread)
	player.finished.connect(player.queue_free)
	scene.add_child(player)
	player.global_position = at
	player.play()


## Plays `name` once, not from anywhere in particular: menus, stings.
func play(name: StringName, volume_db := 0.0) -> void:
	var sound := stream(name)
	if sound == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = sound
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


## Starts looping `name` on `parent`, moving along with it. Returns the
## player, to change its volume or pitch, or stop it.
func loop_on(parent: Node3D, name: StringName, volume_db := 0.0) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream(name)
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.autoplay = true
	parent.add_child(player)
	return player


func _background(name: StringName, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream(name)
	player.bus = bus
	player.volume_db = -80.0
	add_child(player)
	return player


## Eases a background loop toward `level` (0 to 1), and stops it when silent.
func _fade(player: AudioStreamPlayer, level: float, delta: float) -> void:
	var current := db_to_linear(player.volume_db) if player.playing else 0.0
	current = move_toward(current, level, delta / FADE_TIME)
	if current <= 0.001:
		if player.playing:
			player.stop()
		return
	player.volume_db = linear_to_db(current)
	if not player.playing:
		player.play()
