class_name WeaponPickup
extends Area3D
## A weapon floating in mid-air under a green arrow. The first citizen that can
## carry weapons and wants this one (Citizen.wants_weapon()) equips it on touch. Citizens drop these when they swap
## weapons or die (see Citizen.drop_weapon()).

## Someone who just dropped a weapon has to step this far away before they
## can pick it back up. Otherwise a swap would grab it straight back.
const REPICKUP_DISTANCE := 1.0

@export var weapon: Weapon
@export var hover_height := 0.8
@export var bob_height := 0.12
## Bobs per second.
@export var bob_frequency := 0.6
## How far above the weapon the arrow floats.
@export var arrow_gap := 0.75
## Dropped weapons fade away after lying around this long. Ones placed in
## the level stay put.
@export var dropped_lifetime := 10.0
@export var fade_time := 1.0

var _time := 0.0
## Grows from small to full size when dropped, so the weapon pops into view.
var _pop_scale := 1.0
var _ignored: Citizen
var _was_dropped := false

@onready var _sprite: Sprite3D = $Sprite
@onready var _arrow: Sprite3D = $Arrow


func _ready() -> void:
	add_to_group("weapon_pickups")
	_sprite.texture = weapon.texture
	body_entered.connect(_on_body_entered)
	if _was_dropped:
		_pop_in_then_expire()


## Whether `citizen` may pick this up right now.
func is_available_to(citizen: Citizen) -> bool:
	return citizen != _ignored and citizen.can_carry_weapons and not citizen.is_down \
		and citizen.wants_weapon(weapon) and not is_queued_for_deletion()


## Hands the weapon to `citizen` if they may take it. Returns whether they did.
func try_give_to(citizen: Citizen) -> bool:
	if not is_available_to(citizen):
		return false
	citizen.equip(weapon)
	queue_free()
	return true


## Called on a freshly dropped pickup, before it's added to the scene. The
## dropper can't grab it again until they've walked away from it, and it
## fades away if nobody takes it.
func drop_from(citizen: Citizen) -> void:
	_ignored = citizen
	_was_dropped = true


func _pop_in_then_expire() -> void:
	_pop_scale = 0.2
	var tween := create_tween()
	tween.tween_property(self, "_pop_scale", 1.0, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(dropped_lifetime)
	tween.tween_callback(_start_fading)
	tween.tween_property(_sprite, "modulate:a", 0.0, fade_time)
	tween.parallel().tween_property(_arrow, "modulate:a", 0.0, fade_time)
	tween.parallel().tween_property($BlobShadow, "modulate:a", 0.0, fade_time)
	tween.tween_callback(queue_free)


func _start_fading() -> void:
	# Blended transparency for the fade. Alpha cut would make them pop out instead.
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_arrow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED


func _process(delta: float) -> void:
	_time += delta
	var bob := sin(_time * TAU * bob_frequency) * bob_height
	_sprite.position.y = hover_height + bob
	_arrow.position.y = hover_height + arrow_gap + bob
	_arrow.scale = Vector3.ONE * _pop_scale
	# Face the camera, tilted diagonally.
	var camera := get_viewport().get_camera_3d()
	if camera:
		_sprite.global_basis = camera.global_basis * Basis(Vector3.BACK, deg_to_rad(45.0)) \
			* Basis.from_scale(Vector3.ONE * _pop_scale)


func _physics_process(_delta: float) -> void:
	if _ignored and (not is_instance_valid(_ignored) \
			or _ignored.global_position.distance_to(global_position) > REPICKUP_DISTANCE):
		_ignored = null


func _on_body_entered(body: Node3D) -> void:
	if body is Citizen:
		try_give_to(body)
