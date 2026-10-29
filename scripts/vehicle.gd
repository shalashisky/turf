class_name Vehicle
extends CharacterBody3D
## A car. Drives along its heading at its speed, faces where it's going, and
## runs over anyone it hits hard enough (Citizen.struck_by_vehicle), which
## counts as an attack by its driver, if it has one. Subclasses do their own
## driving (_ai_drive()): Car drops people off, TrafficCar drives around town,
## PlayerCar is the player's own.
##
## Anyone can take any car (hijack()): the player by walking up and pressing
## interact, NPCs with Npc.go_take(). Whoever was driving gets thrown out and
## takes it as an attack, and the new driver gets in a moment later. Cops and
## gangsters can also drag the player out of a car (pull_out()). The player then drives it (RT or W to drive, LT or S
## to brake and reverse, left and right to steer, interact to get out), and
## anyone else drives off around town with a StreetDriver.
##
## Cars take damage from crashes, bullets and beatings. They smoke when
## they're nearly done for, and at zero health they explode, hurting anyone
## nearby and setting off other cars, then the burnt-out wreck fades away.
## Lamp posts don't stop a car going fast enough: they get knocked over.
##
## Cars face -Z, and count as solid level geometry for everyone else.

signal wrecked

const SMOKE := preload("res://scenes/effects/car_smoke.tscn")
const EXPLOSION := preload("res://scenes/effects/explosion.tscn")
const CHARRED := Color(0.07, 0.06, 0.06)
## Crashing slower than this doesn't hurt.
const SAFE_CRASH_SPEED := 4.0
const CRASH_DAMAGE_PER_SPEED := 3.0
const LAMP_DAMAGE := 3.0
const LAMP_PUSH_TIME := 0.5
## The wreck stays this long before fading.
const WRECK_TIME := 8.0
## Interact presses this soon after getting in don't count, so the press that
## opened the door doesn't get you straight back out.
const DOOR_GRACE_MS := 300
## How loud engines idle, in dB.
const ENGINE_VOLUME := -16.0
## After throwing the driver out, the hijacker gets in this much later.
const HIJACK_DELAY := 0.45
## A hijacker who's wandered this far off by then doesn't get in after all.
const HIJACK_REACH := 4.0

## Below this speed, bumping into someone doesn't hurt them.
@export var harmful_speed := 3.5
## Anyone standing higher than this above the car's base is riding on top,
## not in its way.
const ROOF_HEIGHT := 1.0
@export var paint := Color.GRAY
@export var max_health := 100.0
## Smokes below this share of max_health.
@export_range(0.0, 1.0) var smoke_below := 0.35
@export var explosion_radius := 5.0
@export var explosion_damage := 70
## Debug: shows its health above it.
@export var show_health_label := true
## Lamp posts get knocked over at this speed or faster, or by pushing on
## them for LAMP_PUSH_TIME.
@export var knock_over_speed := 4.0

@export_group("Driving")
## How it handles when the player's at the wheel.
@export var max_speed := 16.0
@export var reverse_speed := 5.0
@export var acceleration := 9.0
@export var braking := 20.0
## How quickly it rolls to a stop with nobody on the pedals, in m/s per second.
@export var rolling_drag := 3.0
## Turning rate at full steering lock, in radians per second.
@export var steering := 2.0
## Steering only bites fully above this speed. Below it, turns are gentler.
@export var full_steering_speed := 6.0
## How much of the steering is left at top speed, so it doesn't twitch.
@export_range(0.0, 1.0) var top_speed_steering := 0.5
@export_group("")

## Which way it's pointed, flat.
var heading := Vector3.FORWARD
## Along the heading, in m/s. Negative is reversing.
var speed := 0.0
## Whoever's at the wheel. Their hits count as attacks.
var driver: Citizen
## Someone's at the wheel who isn't in the scene: the driver of a car going
## about its business. Taking the car makes them get out (_let_occupant_out()).
var occupied := false
## Drives it around town while no one else is: for traffic, and anyone who's
## taken it.
var street_driver: StreetDriver
var health := 0.0
var is_wrecked := false
## Whoever damaged it last. The explosion counts as their attack.
var last_attacker: Citizen

var _heading_given := false
## Recently hit citizens, so one bump doesn't count every frame.
var _hit_cooldowns := {}
## Recently crashed-into cars, so a crash only counts once for both of them.
var _crash_cooldowns := {}
## How long we've been pushing on each lamp post we're up against.
var _lamp_pushes := {}
var _smoke: GPUParticles3D
var _health_label: Label3D
var _paint_material: StandardMaterial3D
var _door: Interactable
var _engine: AudioStreamPlayer3D
var _grid: CityGrid
var _got_in_at := 0
## Someone's throwing the driver out, about to get in.
var _hijacker: Citizen

@onready var _body_mesh: MeshInstance3D = $Body


func _ready() -> void:
	add_to_group("vehicles")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if health <= 0.0:
		health = max_health
	if not _heading_given:
		heading = -global_basis.z
		heading.y = 0.0
		heading = heading.normalized()
	_paint_material = StandardMaterial3D.new()
	_paint_material.albedo_color = paint
	_paint_material.roughness = 0.35
	_body_mesh.material_override = _paint_material
	_face(heading)
	_build_health_label()
	_update_smoke()
	_grid = get_tree().get_first_node_in_group("city_grid")
	_door = get_node_or_null("Door") as Interactable
	if _door == null:
		_door = _build_door()
	_door.interacted.connect(hijack)
	_refresh_door()
	_engine = Sound.loop_on(self, &"engine_loop", ENGINE_VOLUME)
	reset_physics_interpolation()


func _exit_tree() -> void:
	# Whoever's inside goes with the car, unless it's the player.
	if is_instance_valid(driver) and not driver.is_in_group("player") and not driver.is_queued_for_deletion():
		driver.queue_free()


func _physics_process(delta: float) -> void:
	if is_wrecked:
		return
	if driver and driver.is_in_group("player"):
		_player_drive(delta)
	elif street_driver:
		street_driver.tick(delta)
		_drive_step(delta)
	else:
		_ai_drive(delta)
	if driver:
		driver.global_position = global_position
	_update_engine()


## The engine runs while someone's at the wheel, revving with speed. The
## player's own is louder.
func _update_engine() -> void:
	var running := (driver != null or occupied or street_driver != null) and not is_wrecked and visible
	if running != _engine.playing:
		if running:
			_engine.play()
		else:
			_engine.stop()
	if running:
		_engine.pitch_scale = 0.7 + absf(speed) / 16.0 * 1.3
		var players_car := driver != null and driver.is_in_group("player")
		_engine.volume_db = ENGINE_VOLUME + (6.0 if players_car else 0.0)


## `who` takes the wheel. Whoever was driving is thrown out first, and takes
## it as an attack, and `who` gets in a moment later.
func hijack(who: Citizen) -> void:
	if is_wrecked or who == driver or who.is_down or _hijacker:
		return
	speed = 0.0
	var thrown_out: Citizen = null
	if driver:
		thrown_out = driver
		_let_driver_out()
	elif occupied:
		occupied = false
		street_driver = null
		thrown_out = _let_occupant_out(door_point(), who)
	if thrown_out:
		thrown_out.thrown_from_car(_out_the_door())
		thrown_out._react_to_hit(who)
		get_tree().call_group("npcs", "notice_fight", who, thrown_out)
		_hijacker = who
		_refresh_door()
		await get_tree().create_timer(HIJACK_DELAY, false).timeout
		_hijacker = null
		if is_wrecked or driver or not is_instance_valid(who) or who.is_down or who.vehicle \
				or who.global_position.distance_to(global_position) > HIJACK_REACH:
			_refresh_door()
			return
	_take_wheel(who)


## `by` drags the driver out and throws them down. The car's left where it is.
func pull_out(by: Citizen) -> void:
	if driver == null or _hijacker:
		return
	var who := driver
	_let_driver_out()
	who.thrown_from_car(_out_the_door())
	who._react_to_hit(by)


func _take_wheel(who: Citizen) -> void:
	driver = who
	who.enter_vehicle(self)
	remove_from_group("traffic")
	if who.is_in_group("player"):
		street_driver = null
		_got_in_at = Time.get_ticks_msec()
	else:
		street_driver = StreetDriver.new(self)
		street_driver.fleeing = true
	_on_taken(who)
	_refresh_door()


## Which way someone thrown out of the driver's door goes flying.
func _out_the_door() -> Vector3:
	return (door_point() - global_position).normalized()


## Where people get in and out: beside the driver's door, on the car's left.
func door_point() -> Vector3:
	return global_position + Vector3(heading.z, 0.0, -heading.x) * 1.6


## Nobody but the player at the wheel, nobody inside: free for the taking.
func is_unattended() -> bool:
	return driver == null and not occupied and not is_wrecked


## Points the car along `direction`. Use before adding it to the scene.
func aim(direction: Vector3) -> void:
	heading = Vector3(direction.x, 0.0, direction.z).normalized()
	_heading_given = true


## Takes `amount` damage, from `attacker` if anyone. Explodes at zero.
func damage(amount: float, attacker: Citizen = null) -> void:
	if is_wrecked or amount <= 0.0:
		return
	if attacker:
		last_attacker = attacker
	health = maxf(health - amount, 0.0)
	_on_damaged(attacker)
	_update_smoke()
	_update_health_label()
	if health <= 0.0:
		explode()


## Blows up: hurts everyone nearby, damages other cars (which may go up too),
## and leaves a burnt-out wreck that fades away.
func explode() -> void:
	if is_wrecked:
		return
	is_wrecked = true
	health = 0.0
	speed = 0.0
	velocity = Vector3.ZERO
	if driver:
		_let_driver_out()
	occupied = false
	street_driver = null
	_refresh_door()
	_on_wrecked()
	wrecked.emit()

	var blast: Node3D = EXPLOSION.instantiate()
	blast.position = global_position + Vector3.UP * 0.8
	get_parent().add_child(blast)
	var center := global_position
	var blamed := last_attacker if is_instance_valid(last_attacker) else null
	for citizen: Citizen in get_tree().get_nodes_in_group("citizens"):
		var away := citizen.global_position.distance_to(center)
		if away < explosion_radius:
			citizen.caught_in_explosion(center, blamed, roundi(explosion_damage * (1.0 - away / explosion_radius * 0.6)))
	# Other cars go up a moment later, so chains of them ripple.
	for car: Vehicle in get_tree().get_nodes_in_group("vehicles"):
		var away := car.global_position.distance_to(center)
		if away < explosion_radius:
			var amount := explosion_damage * (1.0 - away / explosion_radius * 0.6)
			get_tree().create_timer(0.15 + away * 0.05).timeout.connect(_damage_later.bind(car, amount, blamed))

	for part in _meshes():
		part.material_override = _charred_material()
	_update_smoke()
	_smoke.amount_ratio = 1.0
	var tween := create_tween()
	tween.tween_interval(WRECK_TIME)
	for part in _meshes():
		tween.parallel().tween_property(part, "transparency", 1.0, 1.5).set_delay(WRECK_TIME)
	tween.tween_callback(_on_wreck_faded)


## How fast it can turn right now, in radians per second, at full lock
## `steering`: a car only turns while it's moving, more the faster it goes,
## up to full_steering_speed. No spinning on the spot.
func turn_rate(steering_rate: float) -> float:
	return steering_rate * clampf(absf(speed) / full_steering_speed, 0.0, 1.0)


## Driving, when it's the player at the wheel.
func _player_drive(delta: float) -> void:
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	if not Dialogue.blocks_input():
		if Input.is_action_just_pressed("interact") and Time.get_ticks_msec() - _got_in_at > DOOR_GRACE_MS:
			_let_driver_out()
			return
		throttle = Input.get_action_strength("accelerate")
		brake = Input.get_action_strength("brake")
		steer = Input.get_axis("move_left", "move_right")

	if throttle > 0.0:
		# Stop backing up first, then drive forward.
		if speed < -0.5:
			speed = move_toward(speed, 0.0, braking * throttle * delta)
		else:
			speed = move_toward(speed, max_speed * throttle, acceleration * delta)
	elif brake > 0.0:
		# Brake to a stop, then back up.
		if speed > 0.5:
			speed = move_toward(speed, 0.0, braking * brake * delta)
		else:
			speed = move_toward(speed, -reverse_speed * brake, acceleration * delta)
	else:
		speed = move_toward(speed, 0.0, rolling_drag * delta)

	# Steering needs some speed to bite, and calms down again near top speed.
	var grip := clampf(absf(speed) / full_steering_speed, 0.0, 1.0)
	grip *= lerpf(1.0, top_speed_steering, clampf((absf(speed) - full_steering_speed) / (max_speed - full_steering_speed), 0.0, 1.0))
	heading = heading.rotated(Vector3.UP, -steer * steering * grip * signf(speed) * delta)

	# Stop at the edge of the map rather than driving into the water.
	if _grid and absf(speed) > 0.0:
		var bumper := global_position + heading * signf(speed) * 2.3
		if _grid.tile_at(bumper) == CityGrid.INVALID_TILE:
			speed = 0.0
	_drive_step(delta)


## Driving when neither the player nor a StreetDriver has the wheel.
## Subclasses drive themselves here; left alone, a car rolls to a stop.
func _ai_drive(delta: float) -> void:
	speed = move_toward(speed, 0.0, rolling_drag * delta)
	_drive_step(delta)


## The driver gets out by the driver's door, leaving the car parked.
func _let_driver_out() -> void:
	var who := driver
	driver = null
	street_driver = null
	speed = 0.0
	who.exit_vehicle(door_point())
	_refresh_door()


## Hook for a hijacking: the unseen driver (see `occupied`) gets out at `at`.
## Returns them, so they can react to `by`, or null.
func _let_occupant_out(_at: Vector3, _by: Citizen) -> Citizen:
	return null


## Hook for when someone's taken the wheel.
func _on_taken(_who: Citizen) -> void:
	pass


func _refresh_door() -> void:
	if _door == null:
		return
	if is_wrecked or _hijacker or (driver and driver.is_in_group("player")):
		_door.prompt = ""
	elif driver or occupied:
		_door.prompt = "Hijack"
	else:
		_door.prompt = "Drive"


func _build_door() -> Interactable:
	var door := Interactable.new()
	door.name = "Door"
	door.collision_layer = 0
	door.collision_mask = 2
	door.prompt_height = 2.2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.6, 2.0, 5.4)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.0)
	door.add_child(shape)
	add_child(door)
	return door


## Moves one physics step along the heading. Runs over anyone in the way,
## crashes into walls and other cars, and knocks over lamp posts.
func _drive_step(delta: float) -> void:
	if is_wrecked:
		return
	var speed_before := speed
	velocity = heading * speed
	move_and_slide()
	global_position.y = 0.0
	_face(heading)
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other := collision.get_collider()
		if collision.get_normal().y > 0.7 or other is Citizen or other == null:
			continue
		var lamp := (other as Node).get_parent()
		if lamp and lamp.has_method("knock_over"):
			if absf(speed_before) >= knock_over_speed:
				Sound.play_at(&"clang", lamp.global_position + Vector3.UP, -2.0)
				lamp.knock_over(heading * speed_before)
				speed = speed_before * 0.8
				damage(LAMP_DAMAGE)
				continue
			if speed_before != 0.0:
				_lamp_pushes[lamp] = _lamp_pushes.get(lamp, 0.0) + delta
				if _lamp_pushes[lamp] >= LAMP_PUSH_TIME:
					_lamp_pushes.erase(lamp)
					lamp.knock_over(heading * signf(speed_before) * knock_over_speed)
					continue
		# A wall, a car or a post too slow to knock down stops us short.
		var moved := get_real_velocity().dot(heading)
		if absf(moved) < absf(speed):
			speed = moved
		var closing := (heading * speed_before - collision.get_collider_velocity()).dot(-collision.get_normal())
		_crash(other, closing)
	_hit_whoever_we_bumped()
	_tick_cooldowns(_hit_cooldowns, delta)
	_tick_cooldowns(_crash_cooldowns, delta)


func _crash(other: Object, closing_speed: float) -> void:
	var amount := (closing_speed - SAFE_CRASH_SPEED) * CRASH_DAMAGE_PER_SPEED
	if amount <= 0.0:
		return
	var car := other as Vehicle
	if not (car and _crash_cooldowns.has(car)):
		Sound.play_at(&"crash", global_position + Vector3.UP, minf(amount / 10.0 - 4.0, 4.0))
	if car:
		if _crash_cooldowns.has(car):
			return
		_crash_cooldowns[car] = 0.5
		car._crash_cooldowns[self] = 0.5
		car.damage(amount, driver)
	damage(amount, car.driver if car else null)


func _hit_whoever_we_bumped() -> void:
	if absf(speed) < harmful_speed:
		return
	for i in get_slide_collision_count():
		var who := get_slide_collision(i).get_collider() as Citizen
		if who and who != driver and not who.is_down and not _hit_cooldowns.has(who) and not is_riding(who):
			_hit_cooldowns[who] = 1.0
			who.struck_by_vehicle(heading * speed, driver)
			speed *= 0.6


## Whether `who` is up on the roof, along for the ride.
func is_riding(who: Node3D) -> bool:
	return who.global_position.y > global_position.y + ROOF_HEIGHT


func _tick_cooldowns(cooldowns: Dictionary, delta: float) -> void:
	for key in cooldowns.keys():
		cooldowns[key] -= delta
		if cooldowns[key] <= 0.0 or not is_instance_valid(key):
			cooldowns.erase(key)


## Hook for whenever it takes damage.
func _on_damaged(_attacker: Citizen) -> void:
	pass


## Hook for the moment it blows up, before the blast: let the driver out.
func _on_wrecked() -> void:
	pass


## Hook for when the wreck has faded away. Gone for good, unless overridden.
func _on_wreck_faded() -> void:
	queue_free()


## Puts it back like new: no damage, no smoke, fresh paint.
func repair() -> void:
	is_wrecked = false
	health = max_health
	last_attacker = null
	_update_health_label()
	for part in _meshes():
		part.material_override = null
		part.transparency = 0.0
	_body_mesh.material_override = _paint_material
	_update_smoke()


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
	_health_label.position.y = 2.7
	_health_label.visible = show_health_label
	add_child(_health_label)
	_update_health_label()


func _update_health_label() -> void:
	if _health_label == null:
		return
	_health_label.text = "%d/%d" % [ceili(health), roundi(max_health)]
	_health_label.modulate = Color.RED.lerp(Color.GREEN, health / max_health)


func _update_smoke() -> void:
	var smoking := is_wrecked or health < max_health * smoke_below
	if smoking and _smoke == null:
		_smoke = SMOKE.instantiate()
		_smoke.position = Vector3(0.0, 0.9, -1.2)
		add_child(_smoke)
	if _smoke:
		_smoke.emitting = smoking


func _meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for child in get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	return meshes


func _charred_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = CHARRED
	material.roughness = 1.0
	return material


func _damage_later(car: Vehicle, amount: float, attacker: Citizen) -> void:
	if is_instance_valid(car):
		car.damage(amount, attacker if is_instance_valid(attacker) else null)


func _face(direction: Vector3) -> void:
	if direction.length() > 0.01:
		rotation.y = atan2(-direction.x, -direction.z)
