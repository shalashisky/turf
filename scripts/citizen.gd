class_name Citizen
extends CharacterBody3D
## Base for every person in the city: the player, NPCs, rivals. Handles walking,
## jumping, swimming, shoving and being shoved, melee weapons and knockback,
## health and death, hit and landing effects, and 8-direction sprite animation with squash and
## stretch. Subclasses decide where to go and where to look by
## overriding _choose_move_direction() and _choose_facing().
##
## Expects a DirectionalSprite child named "Sprite". A Decal named
## "BlobShadow" is optional.

signal died
signal knocked_out
signal got_up

const BLOOD_BURST := preload("res://scenes/effects/blood_burst.tscn")
const BLOCK_SPARK := preload("res://scenes/effects/block_spark.tscn")
const DUST_PUFF := preload("res://scenes/effects/dust_puff.tscn")
## Landing faster than this (m/s) kicks up dust.
const DUST_FALL_SPEED := 3.0
## Height above the feet where weapons are held.
const HAND_HEIGHT := 0.55
## Physics layer for the level geometry. Citizens live on layer 2.
const WORLD_LAYER := 1

@export_group("Movement")
@export var move_speed := 5.0
@export var acceleration := 30.0
@export var friction := 40.0

@export_group("Jumping")
## Apex height in meters. A bit over 1 so a full jump clears a 1-tile ledge.
@export var jump_height := 1.3
@export var jump_time_to_peak := 0.35
## Falling is faster than rising, which makes jumps feel less floaty.
@export var fall_gravity_multiplier := 1.6
## Letting go of jump while rising cuts the jump short by this factor.
@export var jump_release_damping := 0.5
## Grace period to still jump just after walking off a ledge.
@export var coyote_time := 0.1
## A jump requested this long before landing still fires on landing.
@export var jump_buffer_time := 0.12

@export_group("Swimming")
## Walking speed is multiplied by this in water.
@export var swim_speed_factor := 0.55
## How far below the surface the feet float. Leaves head and shoulders out.
@export var swim_depth := 0.95
## How quickly the body settles at its floating height.
@export var buoyancy := 3.0
## How hard the water brakes vertical motion, like a fall into it, in m/s².
@export var water_drag := 25.0
## Jumping while swimming hauls you this high above the surface, enough to
## climb onto the shore.
@export var water_exit_height := 0.8
@export var bob_height := 0.05
## Bobs per second.
@export var bob_frequency := 0.8

@export_group("Pushing")
## Fraction of walking speed kept while shoving another citizen.
@export var push_speed_factor := 0.7
## How fast a shove we received wears off, in m/s per second.
@export var push_friction := 12.0

@export_group("Combat")
## Swung when no weapon is equipped.
@export var fists: Weapon = preload("res://weapons/fists.tres")
## Whether touching a weapon pickup equips it.
@export var can_carry_weapons := false
## Equipped on spawn.
@export var starting_weapon: Weapon
## Leave the held weapon behind as a pickup when dying.
@export var drops_weapon_on_death := true

@export_group("Health")
@export var max_health := 100
## How long a body lies there before it starts to fade.
@export var corpse_linger_time := 3.0
@export var corpse_fade_time := 1.0
## Come back to life at the spawn point after fading, instead of despawning.
@export var respawns_after_death := false
## Essential citizens are never killed. At zero health they're knocked out
## instead, and get back up after knockout_time.
@export var essential := false
@export var knockout_time := 6.0
## Fraction of max health an essential citizen gets back up with.
@export_range(0.0, 1.0) var get_up_health := 0.5
## Debug readout of health above the head.
@export var show_health_label := true

@export_group("Blocking")
## Share of a blocked hit's damage that's stopped.
@export_range(0.0, 1.0) var block_damage_reduction := 0.8
## Knockback from a blocked hit, as a fraction of the full shove.
@export_range(0.0, 1.0) var block_knockback_factor := 0.35
## Only hits from within this arc in front get blocked.
@export var block_arc_degrees := 120.0
## Walking speed is multiplied by this while blocking.
@export var block_move_factor := 0.45

@export_group("Squash and Stretch")
## How fast the sprite springs back to its normal shape.
@export var squash_recovery := 12.0
## Squash on a hard landing. Scaled up by fall speed, up to this much.
@export var max_landing_squash := 0.3
## Stretch while flying through the air, at most this much.
@export var max_air_stretch := 0.12

var facing := Vector3.FORWARD
var is_swimming := false
var equipped_weapon: Weapon
var health := 0
## Holding a guard up: slower, can't attack, takes less from hits in front.
var is_blocking := false
var is_dead := false
var is_knocked_out := false
## Dead or knocked out: can't act, and nobody should be targeting them.
var is_down: bool:
	get:
		return is_dead or is_knocked_out

## Self-propelled horizontal velocity. Kept apart from shoves so that walking
## into a wall or a shove doesn't eat into it.
var _walk_velocity := Vector3.ZERO
var _push_velocity := Vector3.ZERO
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
## True while rising from a jump, so buoyancy doesn't cancel jumping out of water.
var _jump_rising := false
var _water: Water
var _swim_time := 0.0
var _spawn_position: Vector3
var _flash: Tween
var _sprite_scale := Vector2.ONE
## Set when a hit pops us into the air, so that landing doesn't kick up dust.
var _knocked_airborne := false
var _attack_cooldown_left := 0.0
var _swing_time_left := 0.0
## Weapon angle relative to facing, in radians, counterclockwise on screen.
var _weapon_angle := 0.0
var _weapon_pivot: Node3D
var _weapon_sprite: Sprite3D
var _health_label: Label3D
## 0 while standing, 1 once the body has toppled over onto its side.
var _death_tilt := 0.0
## Which way the body falls on screen: 1 to the right, -1 to the left.
var _death_side := 1.0
var _death_tween: Tween
## Saved on death so a respawn can restore them.
var _living_groups: Array[StringName] = []
var _living_collision_layer := 0
var _living_collision_mask := 0

@onready var _sprite: DirectionalSprite = $Sprite
@onready var _sprite_rest_height := _sprite.position.y
@onready var _sprite_billboard := _sprite.billboard
@onready var _blob_shadow: Decal = get_node_or_null("BlobShadow")


func _ready() -> void:
	add_to_group("citizens")
	_spawn_position = global_position
	health = max_health
	_build_weapon_sprite()
	_build_health_label()
	if starting_weapon:
		equip(starting_weapon)


func _physics_process(delta: float) -> void:
	var move_dir := Vector3.ZERO if is_down else _choose_move_direction(delta)
	_update_swimming()
	_update_walk_velocity(move_dir, delta)
	_update_vertical_velocity(delta)
	velocity.x = _walk_velocity.x + _push_velocity.x
	velocity.z = _walk_velocity.z + _push_velocity.z
	var was_on_floor := is_on_floor()
	var fall_speed := -velocity.y
	move_and_slide()
	if is_on_floor() and not was_on_floor and fall_speed > DUST_FALL_SPEED:
		_on_landed(fall_speed)
	_attack_cooldown_left -= delta
	_swing_time_left -= delta

	_push_bodies()
	_push_velocity = _push_velocity.move_toward(Vector3.ZERO, push_friction * delta)
	_respawn_if_fallen()
	if not is_down:
		_choose_facing(move_dir, delta)
	_update_visuals(delta)


## Where this citizen wants to go this frame, with a length of up to 1.
func _choose_move_direction(_delta: float) -> Vector3:
	return Vector3.ZERO


## Default: face the way you're moving.
func _choose_facing(move_dir: Vector3, _delta: float) -> void:
	if move_dir.length() > 0.1:
		facing = move_dir.normalized()


## Turn to look at `point` right away, even while the game is paused.
func face_toward(point: Vector3) -> void:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() > 0.01:
		facing = offset.normalized()
		_sprite.show_facing(facing, false, false, 0.0)


func request_jump() -> void:
	_jump_buffer_left = jump_buffer_time


func release_jump() -> void:
	if _jump_rising and velocity.y > 0.0:
		velocity.y *= jump_release_damping


func push(push_velocity: Vector3) -> void:
	push_velocity.y = 0.0
	if push_velocity.length() > _push_velocity.length():
		_push_velocity = push_velocity


func current_weapon() -> Weapon:
	return equipped_weapon if equipped_weapon else fists


## Whether touching a pickup of `weapon` should equip it. By default always,
## swapping out whatever's held.
func wants_weapon(_weapon: Weapon) -> bool:
	return true


## Holds `weapon`, dropping whatever was held before.
func equip(weapon: Weapon) -> void:
	drop_weapon()
	equipped_weapon = weapon
	_weapon_angle = _weapon_rest_angle()
	_squash(Vector2(1.15, 0.88))


## Leaves the held weapon floating at our feet as a pickup, and goes back to fists.
func drop_weapon() -> void:
	if equipped_weapon == null:
		return
	var pickup: WeaponPickup = load("res://scenes/weapon_pickup.tscn").instantiate()
	pickup.weapon = equipped_weapon
	equipped_weapon = null
	# Float on the water rather than under it.
	var at := global_position
	at.y = maxf(at.y, water_surface_height())
	var parent := get_parent() as Node3D
	pickup.position = parent.to_local(at) if parent else at
	pickup.drop_from(self)
	# Deferred: this can run inside a physics callback, like touching another
	# pickup, where adding an Area3D isn't allowed.
	get_parent().add_child.call_deferred(pickup)


func set_blocking(on: bool) -> void:
	is_blocking = on and not is_down


func can_attack() -> bool:
	return not is_down and not is_blocking and _attack_cooldown_left <= 0.0


## Melee swing in the facing direction with the current weapon. Hits every
## other citizen in its arc. Returns false while still cooling down.
func attack() -> bool:
	if not can_attack():
		return false
	var weapon := current_weapon()
	_attack_cooldown_left = weapon.cooldown
	_swing_time_left = weapon.swing_time
	var half_arc := deg_to_rad(weapon.arc_degrees) * 0.5
	for other: Citizen in get_tree().get_nodes_in_group("citizens"):
		if other == self or _is_ally(other):
			continue
		var to_other := _flat_offset_to(other)
		if to_other.length() <= weapon.reach and facing.angle_to(to_other) <= half_arc:
			other.hit(self, weapon)
	return true


## Allies are never hit by our attacks. Nobody has allies by default.
func _is_ally(_other: Citizen) -> bool:
	return false


## Takes the weapon's damage and gets knocked back away from the attacker,
## harder for heavier weapons.
func hit(attacker: Citizen, weapon: Weapon) -> void:
	if is_down:
		return
	var away := _flat_offset_from(attacker)
	away = away.normalized() if away.length() > 0.01 else attacker.facing
	var blocked := is_blocking and facing.angle_to(-away) <= deg_to_rad(block_arc_degrees) * 0.5
	var damage := weapon.damage
	if blocked:
		# The guard takes most of it: a shove, a spark, and a little damage.
		push(away * weapon.knockback * block_knockback_factor)
		damage = roundi(weapon.damage * (1.0 - block_damage_reduction))
		_squash(Vector2(1.1, 0.92))
		_spawn_effect(BLOCK_SPARK, global_position + Vector3.UP * 0.8 - away * 0.35, -away + Vector3.UP * 0.5)
	else:
		push(away * weapon.knockback)
		if is_on_floor() or is_swimming:
			velocity.y = weapon.knockback_lift
			_knocked_airborne = true
		if _flash:
			_flash.kill()
		_sprite.modulate = Color(1.0, 0.2, 0.2)
		_flash = create_tween()
		_flash.tween_property(_sprite, "modulate", Color.WHITE, 0.3)
		_squash(Vector2(1.25, 0.8))
		_spawn_effect(BLOOD_BURST, global_position + Vector3.UP * 0.8, away + Vector3.UP * 0.8)

	health = maxi(health - damage, 0)
	if health == 0:
		if essential:
			knock_out(away)
		else:
			die(away)
	# Let neighbors nearby know there's a fight on.
	if attacker:
		get_tree().call_group("neighbors", "notice_fight", attacker, self)


## Topples over sideways, lies there for a bit, then fades out and despawns
## (or respawns, if respawns_after_death is set). `fall_direction` is the way
## the body was knocked; it decides which side it lands on.
func die(fall_direction := Vector3.ZERO) -> void:
	if is_down:
		return
	is_dead = true
	_fall_down(fall_direction)
	if drops_weapon_on_death:
		drop_weapon()
	died.emit()
	_death_tween.tween_interval(corpse_linger_time)
	# Blended transparency for the fade. Alpha cut would make it pop out instead.
	_death_tween.tween_callback(func() -> void: _sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED)
	_death_tween.tween_property(_sprite, "modulate:a", 0.0, corpse_fade_time)
	if _blob_shadow:
		_death_tween.parallel().tween_property(_blob_shadow, "modulate:a", 0.0, corpse_fade_time)
	_death_tween.tween_callback(_on_corpse_faded)


## Topples over like die(), but gets back up after knockout_time. What
## happens to essential citizens instead of dying.
func knock_out(fall_direction := Vector3.ZERO) -> void:
	if is_down:
		return
	is_knocked_out = true
	_fall_down(fall_direction)
	knocked_out.emit()
	_death_tween.tween_interval(knockout_time)
	_death_tween.tween_property(self, "_death_tilt", 0.0, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	_death_tween.tween_callback(_get_up)


func _get_up() -> void:
	is_knocked_out = false
	health = maxi(roundi(max_health * get_up_health), 1)
	_stand_back_up()
	_squash(Vector2(0.85, 1.15))
	got_up.emit()


## Knocks the citizen flat: out of the fight, untargetable, lying on their side.
## Starts _death_tween with the topple, for the caller to add on to.
func _fall_down(fall_direction: Vector3) -> void:
	health = 0
	_walk_velocity = Vector3.ZERO
	_jump_buffer_left = 0.0

	# Nobody can target, hit, or bump into the body. It still rests on the ground.
	_living_groups.clear()
	for group in get_groups():
		if not String(group).begins_with("_"):
			_living_groups.append(group)
			remove_from_group(group)
	_living_collision_layer = collision_layer
	_living_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = WORLD_LAYER

	var camera := get_viewport().get_camera_3d()
	var screen_right := camera.global_basis.x if camera else Vector3.RIGHT
	var side := fall_direction.dot(screen_right)
	_death_side = signf(side) if absf(side) > 0.01 else (1.0 if randf() < 0.5 else -1.0)

	# The sprite gets posed by hand from here on, so it stops facing the camera.
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite_scale = Vector2.ONE
	_weapon_pivot.hide()
	_health_label.hide()
	if _flash:
		_flash.kill()
	_sprite.modulate = Color.WHITE

	if _death_tween:
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_property(self, "_death_tilt", 1.0, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_death_tween.tween_callback(_on_body_hit_ground)


func _on_body_hit_ground() -> void:
	if not is_swimming:
		_spawn_effect(DUST_PUFF, global_position + _corpse_offset() * 0.6 + Vector3.UP * 0.05)


func _on_corpse_faded() -> void:
	if respawns_after_death:
		_revive()
	else:
		queue_free()


func _revive() -> void:
	is_dead = false
	health = max_health
	_stand_back_up()
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_push_velocity = Vector3.ZERO
	reset_physics_interpolation()


## Undoes _fall_down: back in the groups, colliding, and facing the camera.
func _stand_back_up() -> void:
	_death_tilt = 0.0
	for group in _living_groups:
		add_to_group(group)
	collision_layer = _living_collision_layer
	collision_mask = _living_collision_mask
	_sprite.billboard = _sprite_billboard
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.modulate = Color.WHITE
	_sprite.basis = Basis.IDENTITY
	if _blob_shadow:
		_blob_shadow.modulate.a = 1.0
	_health_label.visible = show_health_label


func enter_water(water: Water) -> void:
	_water = water


func exit_water(water: Water) -> void:
	if _water == water:
		_water = null


## Height of the water surface we're in, or -INF when not in water.
func water_surface_height() -> float:
	return _water.surface_height() if _water else -INF


func _update_swimming() -> void:
	is_swimming = _water != null and global_position.y < _water.surface_height() - swim_depth * 0.5


func _update_walk_velocity(move_dir: Vector3, delta: float) -> void:
	var speed := move_speed * (swim_speed_factor if is_swimming else 1.0)
	if is_blocking:
		speed *= block_move_factor
	var target := Vector3(move_dir.x, 0.0, move_dir.z) * speed
	var rate := acceleration if move_dir != Vector3.ZERO else friction
	_walk_velocity = _walk_velocity.move_toward(target, rate * delta)


func _update_vertical_velocity(delta: float) -> void:
	if velocity.y <= 0.0:
		_jump_rising = false
	if is_on_floor() or is_swimming:
		_coyote_left = coyote_time
	else:
		_coyote_left -= delta

	# Gravity and launch speed are derived from the jump height and timing.
	var rise_gravity := 2.0 * jump_height / pow(jump_time_to_peak, 2.0)
	if is_swimming and not _jump_rising:
		var float_height := _water.surface_height() - swim_depth
		var settle_speed := (float_height - global_position.y) * buoyancy
		velocity.y = move_toward(velocity.y, settle_speed, water_drag * delta)
	elif not is_on_floor():
		var gravity := rise_gravity if velocity.y > 0.0 else rise_gravity * fall_gravity_multiplier
		velocity.y -= gravity * delta

	_jump_buffer_left -= delta
	if _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		var launch_height := jump_height
		if is_swimming:
			launch_height = _water.surface_height() + water_exit_height - global_position.y
		velocity.y = sqrt(2.0 * rise_gravity * launch_height)
		_knocked_airborne = false
		_squash(Vector2(0.8, 1.2))
		_jump_rising = true
		_jump_buffer_left = 0.0
		_coyote_left = 0.0


func _push_bodies() -> void:
	# Shove citizens we walk into, and slow to the same speed so both keep
	# contact instead of stuttering.
	var max_push_speed := move_speed * push_speed_factor
	var pushing := false
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other := collision.get_collider() as Citizen
		if other == null:
			continue
		var direction := -collision.get_normal()
		direction.y = 0.0
		if direction.is_zero_approx():
			continue  # standing on their head
		direction = direction.normalized()
		var speed := minf(_walk_velocity.dot(direction), max_push_speed)
		if speed <= 0.0:
			continue
		other.push(direction * speed)
		pushing = true
	if pushing:
		_walk_velocity = _walk_velocity.limit_length(max_push_speed)


func _respawn_if_fallen() -> void:
	if global_position.y < -10.0:
		global_position = _spawn_position
		velocity = Vector3.ZERO
		_walk_velocity = Vector3.ZERO
		_push_velocity = Vector3.ZERO
		reset_physics_interpolation()


func _on_landed(fall_speed: float) -> void:
	var amount := clampf(fall_speed * 0.025, 0.1, max_landing_squash)
	_squash(Vector2(1.0 + amount, 1.0 - amount))
	if not _knocked_airborne:
		_spawn_effect(DUST_PUFF, global_position + Vector3.UP * 0.05)
	_knocked_airborne = false


## Instantly deform the sprite. It springs back on its own.
func _squash(shape: Vector2) -> void:
	_sprite_scale = shape


## Spawns a one-shot particle effect at `at`, spraying toward `direction`.
func _spawn_effect(scene: PackedScene, at: Vector3, direction := Vector3.UP) -> void:
	# Place it before it enters the tree. Effects start emitting in _ready(),
	# so moving one afterwards would fire it from the world origin, and physics
	# interpolation would then drag it across from there.
	var effect: GPUParticles3D = scene.instantiate()
	var aim := Basis(Quaternion(Vector3.UP, direction.normalized()))
	var parent := get_parent() as Node3D
	var placed := Transform3D(aim, at)
	effect.transform = parent.global_transform.affine_inverse() * placed if parent else placed
	get_parent().add_child(effect)
	effect.reset_physics_interpolation()


func _update_visuals(delta: float) -> void:
	if is_down:
		_pose_corpse()
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.3
	var airborne := not is_on_floor() and not is_swimming
	_sprite.show_facing(facing, moving, airborne, delta)

	# Stretch along the motion while flying, then spring back toward that shape.
	var target_scale := Vector2.ONE
	if airborne:
		var stretch := minf(absf(velocity.y) * 0.015, max_air_stretch)
		target_scale = Vector2(1.0 - stretch * 0.5, 1.0 + stretch)
	_sprite_scale = _sprite_scale.lerp(target_scale, 1.0 - exp(-squash_recovery * delta))
	_sprite.scale = Vector3(_sprite_scale.x, _sprite_scale.y, 1.0)

	# Scale around the feet, not the middle of the sprite.
	var sprite_height := _sprite_rest_height * _sprite_scale.y
	if is_swimming:
		_swim_time += delta
		_sprite.position.y = sprite_height + sin(_swim_time * TAU * bob_frequency) * bob_height
	else:
		_swim_time = 0.0
		_sprite.position.y = sprite_height
	if _blob_shadow:
		_blob_shadow.visible = not is_swimming
	_update_weapon_sprite(delta)
	_update_health_label()


## Where the middle of the sprite rests once the body lies on its side,
## relative to the feet.
func _corpse_offset() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var screen_right := camera.global_basis.x if camera else Vector3.RIGHT
	screen_right.y = 0.0
	return screen_right.normalized() * _death_side * 0.55 + Vector3.UP * 0.28


func _pose_corpse() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Swing the sprite around in the camera's plane, from standing on its feet
	# to lying on its side, so it reads as a 90° topple on screen.
	var standing := Vector3.UP * _sprite_rest_height
	_sprite.position = standing.lerp(_corpse_offset(), clampf(_death_tilt, 0.0, 1.0))
	if is_swimming:
		_swim_time += get_physics_process_delta_time()
		_sprite.position.y += sin(_swim_time * TAU * bob_frequency) * bob_height
	_sprite.global_basis = camera.global_basis * Basis(Vector3.BACK, -_death_side * _death_tilt * PI * 0.5)


func _build_health_label() -> void:
	_health_label = Label3D.new()
	_health_label.name = "HealthLabel"
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_label.no_depth_test = true
	_health_label.render_priority = 10
	_health_label.outline_render_priority = 9
	_health_label.font_size = 36
	_health_label.outline_size = 10
	_health_label.pixel_size = 0.0055
	_health_label.layers = _sprite.layers
	_health_label.visible = show_health_label
	add_child(_health_label)


func _update_health_label() -> void:
	if not _health_label.visible:
		return
	var fraction := float(health) / max_health
	_health_label.text = "%d/%d" % [health, max_health]
	_health_label.modulate = Color.RED.lerp(Color.GREEN, fraction)
	_health_label.position.y = _sprite.position.y - _sprite_rest_height + 1.6


func _build_weapon_sprite() -> void:
	_weapon_pivot = Node3D.new()
	_weapon_pivot.name = "WeaponPivot"
	add_child(_weapon_pivot)
	_weapon_sprite = Sprite3D.new()
	_weapon_sprite.pixel_size = _sprite.pixel_size
	_weapon_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_weapon_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_weapon_sprite.layers = _sprite.layers
	_weapon_sprite.shaded = _sprite.shaded
	_weapon_pivot.add_child(_weapon_sprite)


## Arc weapons are held raised at the start of the arc, ready to come down.
## Jabs point straight ahead.
func _weapon_rest_angle() -> float:
	var weapon := current_weapon()
	if weapon.swing_style == Weapon.SwingStyle.JAB:
		return 0.0
	return deg_to_rad(weapon.arc_degrees) * 0.5


func _update_weapon_sprite(delta: float) -> void:
	var weapon := current_weapon()
	if _weapon_sprite.texture != weapon.texture:
		_weapon_sprite.texture = weapon.texture
		if weapon.texture:
			# Put the grip on the pivot so the weapon swings around the hand.
			_weapon_sprite.offset.x = weapon.texture.get_width() * 0.5 - weapon.grip_pixels
	var swinging := _swing_time_left > 0.0
	_weapon_pivot.visible = weapon.texture != null and (swinging or is_blocking or weapon.visible_when_idle)
	if not _weapon_pivot.visible:
		return

	var progress := 1.0 - _swing_time_left / weapon.swing_time if swinging else 1.0
	var thrust := 0.0
	match weapon.swing_style:
		Weapon.SwingStyle.ARC:
			# Sweep from one end of the arc to the other, fast at first, then
			# ease back to the raised rest pose once the swing is over.
			var half_arc := deg_to_rad(weapon.arc_degrees) * 0.5
			if swinging:
				_weapon_angle = lerpf(half_arc, -half_arc, 1.0 - pow(1.0 - progress, 3.0))
			else:
				_weapon_angle = lerpf(_weapon_angle, half_arc, 1.0 - exp(-15.0 * delta))
		Weapon.SwingStyle.JAB:
			# Shoot straight out and pull back.
			_weapon_angle = 0.0
			thrust = sin(progress * PI) * weapon.jab_distance
	if is_blocking and not swinging:
		# Guard up: held across the body, pointing up on screen.
		_weapon_angle = lerp_angle(_weapon_angle, PI * 0.5, 1.0 - exp(-25.0 * delta))
		thrust = 0.1

	# The sprite lies in the camera's plane, so this is a plain 2D rotation on
	# screen. Hold it a little ahead so it draws in front when facing the
	# camera and behind when facing away.
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen_facing := facing.rotated(Vector3.UP, -camera.global_rotation.y)
	var facing_angle := atan2(-screen_facing.z, screen_facing.x)
	_weapon_pivot.position = Vector3.UP * (_sprite.position.y - _sprite_rest_height + HAND_HEIGHT) + facing * (0.2 + thrust)
	_weapon_pivot.global_basis = camera.global_basis * Basis(Vector3.BACK, facing_angle + _weapon_angle)


func _flat_offset_to(node: Node3D) -> Vector3:
	var offset := node.global_position - global_position
	offset.y = 0.0
	return offset


func _flat_offset_from(node: Node3D) -> Vector3:
	return -_flat_offset_to(node)
