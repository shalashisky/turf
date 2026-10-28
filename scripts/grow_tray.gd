extends Node3D
## A hydroponic tray. Plant a seed, keep the nutrient reservoir topped up, and
## the plant grows over a couple of in-game days, even while you're away.
## The tray's state lives in WorldState under tray_id; this only shows it.

## Growth at which each frame of the plant sprite starts: seedling, young,
## leafy, flowering, ready.
const STAGE_STARTS := [0.0, 0.15, 0.4, 0.7, 1.0]
## A plant that's run out of nutrients yellows and stops growing.
const STARVING_TINT := Color(0.9, 0.82, 0.45)

## Must be unique across every scene, since it's how WorldState knows the tray.
@export var tray_id := "tray"

@onready var _plant: Sprite3D = $Plant
@onready var _plant_rest_scale := _plant.scale
@onready var _gauge: Node3D = $Reservoir/Gauge
@onready var _use: Interactable = $Use


func _ready() -> void:
	_use.interacted.connect(_on_used)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var state := WorldState.tray_state(tray_id)
	var growth := WorldState.tray_growth(tray_id)
	var nutrients := WorldState.tray_nutrients(tray_id)

	_plant.visible = state != WorldState.TrayState.EMPTY
	var stage := 0
	for i in STAGE_STARTS.size():
		if growth >= STAGE_STARTS[i]:
			stage = i
	_plant.frame = stage
	var starving := state == WorldState.TrayState.GROWING and nutrients <= 0.0
	_plant.modulate = STARVING_TINT if starving else Color.WHITE
	_gauge.scale.y = maxf(nutrients, 0.02)

	match state:
		WorldState.TrayState.EMPTY:
			_use.prompt = "Plant seed"
		WorldState.TrayState.READY:
			_use.prompt = "Harvest"
		WorldState.TrayState.GROWING:
			_use.prompt = "Top up nutrients  (%d%% grown%s)" % [
				floori(growth * 100.0), ", starving!" if starving else ""]


func _on_used(_by: Citizen) -> void:
	match WorldState.tray_state(tray_id):
		WorldState.TrayState.EMPTY:
			WorldState.plant_tray(tray_id)
		WorldState.TrayState.READY:
			WorldState.harvest_tray(tray_id)
		WorldState.TrayState.GROWING:
			WorldState.top_up_tray(tray_id)
	_refresh()
	# A little bounce, so you can see it took.
	_plant.scale = _plant_rest_scale * Vector3(1.2, 0.85, 1.0)
	create_tween().tween_property(_plant, "scale", _plant_rest_scale, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
