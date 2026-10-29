class_name CashPickup
extends Area3D
## Money lying on the ground, dropped by someone. The player collects it by
## walking over it. Left alone, it fades away after a while.

@export var amount := 10
@export var lifetime := 30.0
@export var hover_height := 0.35
@export var bob_height := 0.06

var _time := 0.0

@onready var _sprite: Sprite3D = $Sprite


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Pop in, sit there a while, then fade away.
	_sprite.scale = Vector3.ONE * 0.2
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(lifetime)
	tween.tween_callback(func() -> void: _sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED)
	tween.tween_property(_sprite, "modulate:a", 0.0, 1.0)
	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	_time += delta
	_sprite.position.y = hover_height + sin(_time * 4.0) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or is_queued_for_deletion():
		return
	WorldState.add_money(amount)
	Sound.play(&"cash", -4.0)
	_show_amount()
	queue_free()


## "+$12" rising from where the cash was.
func _show_amount() -> void:
	var label := Label3D.new()
	label.text = "+$%d" % amount
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 44
	label.outline_size = 12
	label.pixel_size = 0.005
	label.modulate = Color(0.55, 1.0, 0.5)
	get_parent().add_child(label)
	label.global_position = global_position + Vector3.UP * 1.0
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y + 0.8, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.tween_callback(label.queue_free)
