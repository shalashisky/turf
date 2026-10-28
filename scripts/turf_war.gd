extends CanvasLayer
## The fight for a turf. Starts when the player attacks the gang that runs it
## (the "enemies"). A bar at the top of the screen fills with each one taken
## down, and at kills_to_win the turf is the player's: the gang's spawn doors
## shut for good, anyone hiding comes back out, and WorldState remembers it.
## If the player goes down first, the war is lost and progress resets.

signal started
signal won

@export var turf_id := "downtown"
@export var kills_to_win := 25
@export var victory_message := "This turf is now ours!"
## How long the victory message stays up, in seconds.
@export var message_time := 3.0

var active := false
var kills := 0

@onready var _bar_panel: Control = %BarPanel
@onready var _bar: ProgressBar = %Bar
@onready var _bar_label: Label = %BarLabel
@onready var _message: Label = %Message


func _ready() -> void:
	add_to_group("turf_wars")
	_bar_panel.visible = false
	_message.visible = false
	if WorldState.owns_turf(turf_id):
		# Already ours, from an earlier visit.
		get_tree().call_group.call_deferred("spawn_doors", "shut_for_good")


## The player has started a fight with the gang.
func start() -> void:
	if active or WorldState.owns_turf(turf_id):
		return
	active = true
	kills = 0
	_refresh_bar()
	_bar_panel.visible = true
	_bar_panel.modulate.a = 0.0
	create_tween().tween_property(_bar_panel, "modulate:a", 1.0, 0.3)
	started.emit()


## One of the gang went down.
func count_kill() -> void:
	if not active:
		return
	kills += 1
	_refresh_bar()
	if kills >= kills_to_win:
		_win()


func _process(_delta: float) -> void:
	if not active:
		return
	var player := get_tree().get_first_node_in_group("player") as Citizen
	if player == null or player.is_down:
		_lose()


func _win() -> void:
	active = false
	WorldState.claim_turf(turf_id)
	get_tree().call_group("spawn_doors", "shut_for_good")
	get_tree().call_group("enemies", "stop_fighting")
	get_tree().call_group("safe_doors", "release")
	won.emit()
	create_tween().tween_property(_bar_panel, "modulate:a", 0.0, 0.5)
	_message.text = victory_message
	_message.visible = true
	_message.modulate.a = 0.0
	_message.scale = Vector2.ONE * 0.6
	var tween := create_tween()
	tween.tween_property(_message, "modulate:a", 1.0, 0.25)
	tween.parallel().tween_property(_message, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(message_time)
	tween.tween_property(_message, "modulate:a", 0.0, 0.6)
	tween.tween_callback(_message.hide)


func _lose() -> void:
	active = false
	kills = 0
	create_tween().tween_property(_bar_panel, "modulate:a", 0.0, 0.5)


func _refresh_bar() -> void:
	_bar.max_value = kills_to_win
	_bar.value = kills
	_bar_label.text = "TURF WAR   %d / %d" % [kills, kills_to_win]
