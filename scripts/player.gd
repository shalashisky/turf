extends Citizen
## The player. Moves and jumps from input, and aims with the right stick, the
## mouse, or auto-aim on attack when neither is in use.

enum AimMode { MOVE, STICK, MOUSE }

@export var camera_rig: CameraRig

@export_group("Aiming")
@export var stick_aim_deadzone := 0.3
## Seconds without mouse movement before mouse aim lets go. 0 means never.
@export var mouse_aim_timeout := 2.0
@export var auto_aim_range := 6.0
@export var auto_aim_cone_degrees := 120.0
## How long an auto-aim snap holds before movement can turn you again.
@export var auto_aim_hold := 0.3

## Nothing gets thrown closer than this.
const MIN_THROW_DISTANCE := 2.5
## A burger heals this much.
const BURGER_HEALING := 50
## A bump of cocaine makes you this much faster, for this long.
const RUSH_SPEED := 1.5
const RUSH_TIME := 30.0
## No eating or snorting faster than this.
const USE_COOLDOWN := 0.6

var aim_mode := AimMode.MOVE
## Seconds left on a cocaine rush.
var rush_left := 0.0
var _use_cooldown_left := 0.0

## Whether attack was already held last frame, so holding the trigger of an
## automatic only costs energy once per burst.
var _trigger_was_held := false
var _mouse_idle_time := 0.0
var _aim_hold_time := 0.0

@onready var _aim_pivot: Node3D = $AimPivot


func _ready() -> void:
	super()
	add_to_group("player")
	died.connect(Factions.clear_wanted)
	Inventory.selection_changed.connect(_hold_selected)
	Inventory.changed.connect(_hold_selected)
	_hold_selected()


func _unhandled_input(event: InputEvent) -> void:
	_pick_hotbar_slot(event)
	if event is InputEventMouseMotion:
		aim_mode = AimMode.MOUSE
		_mouse_idle_time = 0.0
	elif event is InputEventJoypadMotion and aim_mode == AimMode.MOUSE and absf(event.axis_value) > 0.5:
		# Picking up the gamepad hands aiming back to the sticks.
		aim_mode = AimMode.MOVE


func _pick_hotbar_slot(event: InputEvent) -> void:
	if Dialogue.blocks_input():
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		# 1 to 9, then 0 for the tenth.
		if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_9:
			Inventory.select(key.physical_keycode - KEY_1)
		elif key.physical_keycode == KEY_0:
			Inventory.select(9)
	if event.is_action_pressed("hotbar_next"):
		Inventory.select(Inventory.selected + 1)
	elif event.is_action_pressed("hotbar_prev"):
		Inventory.select(Inventory.selected - 1)


## Holds whatever's in the selected hotbar slot: a weapon, or fists for an
## empty slot or goods. Keeps the shots left in what was held.
func _hold_selected() -> void:
	var weapon := Inventory.weapon_in(Inventory.selected)
	var stack: Variant = Inventory.selected_slot()
	var shots: int = stack.ammo if weapon else 0
	if weapon != equipped_weapon or shots != ammo:
		hold(weapon, shots)


## Eats, snorts, or otherwise uses up one `item` from the hotbar.
func use_item(item: String) -> void:
	if _use_cooldown_left > 0.0 or is_down:
		return
	match item:
		"burger":
			if health >= max_health:
				call_out("Not hungry.")
				return
			var healed := mini(BURGER_HEALING, max_health - health)
			health += healed
			call_out("+%d" % healed, Color(0.55, 1.0, 0.45))
		"cocaine":
			rush_left = RUSH_TIME
			call_out("Whoa!", Color(0.85, 0.95, 1.0))
		_:
			return
	WorldState.add_item(item, -1)
	_use_cooldown_left = USE_COOLDOWN
	_squash(Vector2(0.9, 1.12))


func _speed_boost() -> float:
	return RUSH_SPEED if rush_left > 0.0 else 1.0


func _physics_process(delta: float) -> void:
	super(delta)
	rush_left = maxf(rush_left - delta, 0.0)
	_use_cooldown_left -= delta


## Whether the player has weed in hand, to sell.
func is_offering_weed() -> bool:
	return Inventory.item_in(Inventory.selected) == "weed" and not is_down and vehicle == null


## Weapons go in the hotbar: onto a stack of the same, or into a free slot.
## With no room, the one in hand is dropped and this takes its slot.
func equip(weapon: Weapon, with_ammo := -1) -> void:
	if Inventory.add_weapon(weapon, with_ammo) < 0:
		drop_weapon()
		var slot := Inventory.add_weapon(weapon, with_ammo)
		if slot >= 0:
			Inventory.select(slot)
	_hold_selected()
	_squash(Vector2(1.15, 0.88))


## Room in the hotbar for it: pick it up on touch.
func picks_up_on_touch(weapon: Weapon) -> bool:
	return Inventory.has_room_for(weapon)


## Takes anything there's room for, or that can swap for the weapon in hand.
func wants_weapon(weapon: Weapon) -> bool:
	return weapon == null or Inventory.has_room_for(weapon) \
		or (Inventory.weapon_in(Inventory.selected) != null and not Inventory.has_weapon(weapon))


## Drops the weapon in hand, emptying its hotbar slot.
func drop_weapon() -> void:
	if equipped_weapon and Inventory.weapon_in(Inventory.selected) == equipped_weapon:
		Inventory.slots[Inventory.selected] = null
	super()
	Inventory.changed.emit()


func aim_mode_name() -> String:
	return AimMode.keys()[aim_mode]


## Allied neighbors fight on our side, so our swings don't hit them.
func _is_ally(other: Citizen) -> bool:
	return (other is Neighbor and other.is_allied()) or super(other)


func attack() -> bool:
	if not can_attack():
		return false
	if aim_mode == AimMode.MOVE:
		var target := _find_auto_aim_target()
		if target:
			facing = _flat_offset_to(target).normalized()
			_aim_hold_time = auto_aim_hold
	var held := equipped_weapon
	if not super():
		return false
	# Shots and throws come off the stack in the hotbar; used up, it's gone.
	if held and Inventory.weapon_in(Inventory.selected) == held:
		var stack: Dictionary = Inventory.selected_slot()
		if equipped_weapon == null:
			Inventory.set_slot(Inventory.selected, null)
		elif stack.ammo != ammo:
			stack.ammo = ammo
			Inventory.changed.emit()
	# Holding down the trigger of an automatic tires you out once per burst.
	if not current_weapon().automatic or not _trigger_was_held:
		WorldState.use_energy(WorldState.ATTACK_ENERGY)
	return true


## Throws land at the cursor when aiming with the mouse, as far as they'll go.
func _throw_distance(weapon: Weapon) -> float:
	if aim_mode == AimMode.MOUSE:
		var to_cursor := _mouse_ground_point() - global_position
		to_cursor.y = 0.0
		return clampf(to_cursor.length(), MIN_THROW_DISTANCE, weapon.reach)
	return weapon.reach


func _choose_move_direction(_delta: float) -> Vector3:
	set_blocking(Input.is_action_pressed("block") and not Dialogue.blocks_input())
	if Dialogue.blocks_input():
		return Vector3.ZERO
	if Input.is_action_just_pressed("jump"):
		request_jump()
	elif Input.is_action_just_released("jump"):
		release_jump()
	return _camera_relative(Input.get_vector("move_left", "move_right", "move_up", "move_down"))


func _choose_facing(move_dir: Vector3, delta: float) -> void:
	_update_aim(move_dir, delta)
	if Dialogue.blocks_input():
		return
	var trigger := Input.is_action_pressed("attack")
	var in_hand := Inventory.item_in(Inventory.selected)
	if in_hand in WorldState.CONSUMABLES:
		if Input.is_action_just_pressed("attack"):
			use_item(in_hand)
	elif Input.is_action_just_pressed("attack") or (current_weapon().automatic and trigger):
		attack()
	_trigger_was_held = trigger
	if Input.is_action_just_pressed("interact"):
		_interact_with_nearest()


func _interact_with_nearest() -> void:
	var nearest: Interactable = null
	var nearest_distance := INF
	for thing: Interactable in get_tree().get_nodes_in_group("interactables"):
		var distance := global_position.distance_to(thing.global_position)
		if thing.can_interact(self) and distance < nearest_distance:
			nearest = thing
			nearest_distance = distance
	if nearest:
		nearest.interact(self)


func _camera_relative(input: Vector2) -> Vector3:
	var yaw := camera_rig.global_rotation.y if camera_rig else 0.0
	return Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)


func _update_aim(move_dir: Vector3, delta: float) -> void:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", stick_aim_deadzone)
	if stick != Vector2.ZERO:
		aim_mode = AimMode.STICK
		facing = _camera_relative(stick).normalized()
		return
	if aim_mode == AimMode.STICK:
		aim_mode = AimMode.MOVE

	if aim_mode == AimMode.MOUSE:
		_mouse_idle_time += delta
		if mouse_aim_timeout > 0.0 and _mouse_idle_time > mouse_aim_timeout:
			aim_mode = AimMode.MOVE
		else:
			var to_cursor := _mouse_ground_point() - global_position
			to_cursor.y = 0.0
			if to_cursor.length() > 0.1:
				facing = to_cursor.normalized()
			return

	_aim_hold_time = maxf(_aim_hold_time - delta, 0.0)
	if _aim_hold_time == 0.0:
		super._choose_facing(move_dir, delta)


func _mouse_ground_point() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var mouse := get_viewport().get_mouse_position()
	var ground := Plane(Vector3.UP, global_position)
	var hit: Variant = ground.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	return hit if hit != null else global_position


func _find_auto_aim_target() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var half_cone := deg_to_rad(auto_aim_cone_degrees) * 0.5
	# Guns reach further than the usual auto-aim range.
	var aim_range := maxf(auto_aim_range, attack_reach())
	for enemy: Citizen in get_tree().get_nodes_in_group("citizens"):
		# Rival gangs, and anyone else who's actually fighting us.
		var fighting_us := enemy is Npc and (enemy as Npc).target == self
		if enemy == self or enemy.is_down or _is_ally(enemy) \
				or not (is_hostile_to(enemy) or fighting_us):
			continue
		var to_enemy := _flat_offset_to(enemy)
		var distance := to_enemy.length()
		var angle := facing.angle_to(to_enemy)
		if distance > aim_range or angle > half_cone:
			continue
		# Prefer close targets, then ones already in front of you.
		var score := distance / aim_range + angle / half_cone
		if score < best_score:
			best = enemy
			best_score = score
	return best


func _update_visuals(delta: float) -> void:
	super(delta)
	_aim_pivot.visible = not is_down
	if is_down:
		return
	_aim_pivot.rotation.y = atan2(-facing.x, -facing.z)
	# Keep the aim arrow on top of the water while swimming.
	var surface := maxf(global_position.y, water_surface_height())
	_aim_pivot.position.y = surface - global_position.y + 0.03
