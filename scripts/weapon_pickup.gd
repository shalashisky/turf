class_name WeaponPickup
extends Area3D
## A weapon floating in mid-air under a green arrow. Someone who can carry
## weapons (and wants this one, see Citizen.wants_weapon()) grabs it just by
## touching it, if they've a free hand (Citizen.picks_up_on_touch()): for
## the player, room in the hotbar. Otherwise the player gets a
## "[E] Swap for ..." prompt instead. Citizens drop these when they swap
## weapons or die (see Citizen.drop_weapon()).

## Someone who just dropped a weapon has to step this far away before they
## can pick it back up. Otherwise a swap would grab it straight back.
const REPICKUP_DISTANCE := 1.0

@export var weapon: Weapon
## Shots left, for guns. Negative means a fresh, full gun.
@export var ammo := -1
@export var hover_height := 0.8
@export var bob_height := 0.12
## Bobs per second.
@export var bob_frequency := 0.6
## How far above the weapon the arrow floats.
@export var arrow_gap := 0.75
## Dropped weapons fade away after lying around this long. Ones placed in
## the level stay put. Tossed empty guns go much sooner.
@export var dropped_lifetime := 10.0
@export var empty_gun_lifetime := 2.0
@export var fade_time := 1.0

var _time := 0.0
## Grows from small to full size when dropped, so the weapon pops into view.
var _pop_scale := 1.0
var _ignored: Citizen
var _was_dropped := false

@onready var _sprite: Sprite3D = $Sprite
@onready var _arrow: Sprite3D = $Arrow
@onready var _swap: Interactable = $Swap


func _ready() -> void:
	add_to_group("weapon_pickups")
	_sprite.texture = weapon.texture
	body_entered.connect(_on_body_entered)
	_swap.interacted.connect(func(by: Citizen) -> void: try_give_to(by))
	if is_empty_gun():
		_clatter_then_expire()
	elif _was_dropped:
		_pop_in_then_expire()


## A tossed gun with no shots left: just litter.
func is_empty_gun() -> bool:
	return weapon.swing_style == Weapon.SwingStyle.SHOOT and ammo == 0


## Whether `citizen` may pick this up right now.
func is_available_to(citizen: Citizen) -> bool:
	return not is_empty_gun() and citizen != _ignored and citizen.can_carry_weapons and not citizen.is_down \
		and citizen.wants_weapon(weapon) and not is_queued_for_deletion()


## Hands the weapon to `citizen` if they may take it. Returns whether they did.
func try_give_to(citizen: Citizen) -> bool:
	if not is_available_to(citizen):
		return false
	citizen.equip(weapon, ammo)
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


## An empty gun drops to the ground, lies there a moment, and fades. No arrow:
## there's nothing to pick up.
func _clatter_then_expire() -> void:
	_arrow.hide()
	$BlobShadow.hide()
	set_process(false)
	_sprite.position.y = hover_height
	var camera := get_viewport().get_camera_3d()
	if camera:
		_sprite.global_basis = camera.global_basis * Basis(Vector3.BACK, randf() * TAU)
	var tween := create_tween()
	tween.tween_property(_sprite, "position:y", 0.1, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(empty_gun_lifetime)
	tween.tween_callback(_start_fading)
	tween.tween_property(_sprite, "modulate:a", 0.0, fade_time)
	tween.tween_callback(queue_free)


func _start_fading() -> void:
	# Blended transparency for the fade. Alpha cut would make them pop out instead.
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_arrow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED


func _process(delta: float) -> void:
	_update_swap_prompt()
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


## Only free hands grab a weapon on touch.
func _on_body_entered(body: Node3D) -> void:
	if body is Citizen and body.picks_up_on_touch(weapon):
		try_give_to(body)


func _update_swap_prompt() -> void:
	var player := get_tree().get_first_node_in_group("player") as Citizen
	var swapping := player != null and not player.picks_up_on_touch(weapon) and is_available_to(player)
	var prompt := "Swap for %s" % weapon.display_name if swapping else ""
	if _swap.prompt != prompt:
		_swap.prompt = prompt
