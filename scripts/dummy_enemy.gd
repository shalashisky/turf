class_name GangMember
extends Npc
## A member of a turf-holding gang: the dummy gang, the Black Panthers, the
## Yellows. Hangs around their home Territory, attacks rival gangs and the
## police on sight (the player only during a turf war over their turf), and joins in when a fellow member nearby is attacked
## (Npc.notice_fight). Every so often their turf sends a few of them raiding a
## rival's (raid()). While their turf is at war they hold it: they won't
## chase anyone past its edge. An unarmed member that spots a weapon lying
## around while fighting goes and grabs it first. Won't walk off ledges by itself, but can
## be shoved off them, water included. The player attacking one sets off a
## turf war over that gang's turf.
##
## The player's own crew are gang members too. Give one a bag of weed and
## they follow the player (up to MAX_FOLLOWERS at once), fighting whoever the
## player fights. They each carry one weapon, which the player can swap for
## the one in hand, give them, or take; and send them home again.

## Most of the player's crew following them at once.
const MAX_FOLLOWERS := 4
## Followers keep about this close to the player, and run to catch up.
const FOLLOW_DISTANCE := 2.5
const CATCH_UP_DISTANCE := 6.0
## The crew's prompt shows with the player this close.
const CREW_PROMPT_RANGE := 2.2

## How often to look around for weapons, in seconds. Saves raycasts.
const WEAPON_SCAN_INTERVAL := 0.25
const CASH_PICKUP := preload("res://scenes/cash_pickup.tscn")
@export_group("Wandering")
@export var wander_speed := 1.5
@export var idle_time_range := Vector2(1.0, 3.0)
@export var walk_time_range := Vector2(1.5, 4.0)

@export_group("Loot")
## Chance of dropping cash on death, and how much.
@export_range(0.0, 1.0) var cash_drop_chance := 0.6
@export var cash_range := Vector2i(5, 20)

@export_group("Weapons")
## Unarmed dummies notice weapon pickups within this distance, if nothing blocks the view.
@export var weapon_sight_range := 8.0
## Also go for weapons while calmly wandering, not just mid-fight.
@export var grab_weapons_while_calm := false

## The turf they hang around. Null to roam anywhere.
var home: Territory

var _wander_dir := Vector3.ZERO
var _state_time_left := 0.0
## Scripted walk, like stepping out of a spawn door, that overrides the AI.
var _walk_out_dir := Vector3.ZERO
var _walk_out_left := 0.0
## The weapon pickup we're heading for, if any.
var _wanted_pickup: WeaponPickup
var _weapon_scan_left := 0.0
## Somewhere on a rival's turf they've been sent to make trouble.
var _raid_point := Vector3.ZERO
var _raid_left := 0.0


## Routed: how long they run before fading away, and how long the fade takes.
const ROUT_TIME := Vector2(3.0, 5.0)
const ROUT_FADE_TIME := 1.0

## Their turf's been lost, and they're running for it (rout()).
var routed := false
## Who they're following, for the player's crew.
var following: Citizen
## Sent to take one of the player's turfs (TurfAttack): they go for the player
## and the crew on sight, and fighting them doesn't start a turf war.
var raider := false
var _crew_prompt: Interactable
var _rout_left := 0.0
var _fading := false


func _ready() -> void:
	super()
	_state_time_left = randf_range(idle_time_range.x, idle_time_range.y)
	died.connect(_on_died)


func _react_to_hit(attacker: Citizen) -> void:
	# On the run, they just keep running.
	if attacker == null or _is_ally(attacker) or routed:
		return
	# Always turn on whoever hit us. The rest of the gang joins in through
	# notice_fight, if they're free.
	if not is_down:
		start_fighting(attacker)
	# Only the player sets off a turf war, and the gang's doors with it. Not
	# by fighting off raiders, though: that's a fight they started.
	if attacker.is_in_group("player") and not raider:
		get_tree().call_group("turf_wars", "start", faction)


## In a turf war, the player gets dragged out of any car they're hiding in.
func _pulls_out_of_cars(who: Citizen) -> bool:
	return who.is_in_group("player") and (raider or (home != null and home.at_war)) and not routed


## Rival gangs and the police get jumped on sight. The player only does once
## there's a turf war on over this gang's turf; until then, the player has to
## start it.
func _attacks_on_sight(other: Citizen) -> bool:
	if routed:
		return false
	if raider and other.is_in_group("player"):
		return true
	if other.is_in_group("player"):
		return home != null and home.at_war
	return super(other)


## Head for `point` on rival turf, looking for a fight on the way.
func raid(point: Vector3, give_up_after := 45.0) -> void:
	_raid_point = point
	_raid_left = give_up_after
	_wander_dir = Vector3.ZERO


func _on_died() -> void:
	get_tree().call_group("turf_wars", "count_kill", faction)
	if randf() < cash_drop_chance:
		var cash: CashPickup = CASH_PICKUP.instantiate()
		cash.amount = randi_range(cash_range.x, cash_range.y)
		var parent := get_parent() as Node3D
		cash.position = parent.to_local(global_position) if parent else global_position
		# Deferred: this can run inside a physics callback, where adding an Area3D isn't allowed.
		get_parent().add_child.call_deferred(cash)


func _run_off(delta: float) -> Vector3:
	_rout_left -= delta
	if _rout_left <= 0.0 and not _fading:
		_fading = true
		fade_away(ROUT_FADE_TIME)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	return _direction_away_from(player.global_position) if player else Vector3.ZERO


## Sticks with the player, fighting whoever they're up against.
func _follow(delta: float) -> Vector3:
	if _still_fighting() or _scan_for_hostiles(delta):
		return _fight(delta)
	var distance := global_position.distance_to(following.global_position)
	if distance <= FOLLOW_DISTANCE:
		return Vector3.ZERO
	var pace := 1.0 if distance > CATCH_UP_DISTANCE else minf(wander_speed * 1.6 / move_speed, 1.0)
	return _steer_toward(following.global_position) * pace


## What the player can do with them right now, by what they've got in hand:
## weed to recruit them, a weapon to swap or give, an empty hand to take
## theirs, or anything else to send a follower home.
func _crew_action() -> String:
	var held := Inventory.weapon_in(Inventory.selected)
	if Inventory.item_in(Inventory.selected) == "weed" and following == null:
		return "Give weed (roll with you)"
	if held:
		return "Swap for %s" % equipped_weapon.display_name if equipped_weapon else "Give %s" % held.display_name
	if Inventory.selected_slot() == null and equipped_weapon:
		return "Take %s" % equipped_weapon.display_name
	if following:
		return "Send home"
	return ""


func _update_crew_prompt() -> void:
	var player := get_tree().get_first_node_in_group("player") as Citizen
	var near := player != null and player.vehicle == null and not is_down \
		and global_position.distance_to(player.global_position) < CREW_PROMPT_RANGE + 2.0
	var prompt := _crew_action() if near else ""
	if _crew_prompt == null:
		if prompt == "":
			return
		_crew_prompt = Interactable.new()
		_crew_prompt.collision_layer = 0
		_crew_prompt.collision_mask = 2
		_crew_prompt.prompt_height = 2.0
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = CREW_PROMPT_RANGE
		shape.shape = sphere
		shape.position.y = 0.8
		_crew_prompt.add_child(shape)
		add_child(_crew_prompt)
		_crew_prompt.interacted.connect(_on_crew_prompt)
	if _crew_prompt.prompt != prompt:
		_crew_prompt.prompt = prompt


func _on_crew_prompt(player: Citizen) -> void:
	var action := _crew_action()
	var slot := Inventory.selected
	if action.begins_with("Give weed"):
		var followers := 0
		for member in get_tree().get_nodes_in_group(Factions.PLAYER):
			if member is GangMember and member.following:
				followers += 1
		if followers >= MAX_FOLLOWERS:
			call_out("You got enough backup already.")
			return
		if WorldState.add_item("weed", -1):
			following = player
			_raid_left = 0.0
			stop_fighting()
			call_out("I got you.", Color(0.55, 1.0, 0.45))
	elif action.begins_with("Swap") or action.begins_with("Give"):
		var stack: Dictionary = Inventory.selected_slot()
		var theirs := equipped_weapon
		var their_ammo := ammo
		hold(stack.weapon, stack.ammo)
		Inventory.set_slot(slot, {"weapon": theirs, "ammo": their_ammo} if theirs else null)
		call_out("Nice.")
	elif action.begins_with("Take"):
		if Inventory.add_weapon(equipped_weapon, ammo) >= 0:
			hold(null)
	elif action == "Send home":
		following = null
		call_out("Later.")


## Walk straight along `direction` for `duration` seconds before the AI takes over.
func walk_out(direction: Vector3, duration: float) -> void:
	_walk_out_dir = direction.normalized()
	_walk_out_left = duration


func push(push_velocity: Vector3) -> void:
	super(push_velocity)
	# Being shoved interrupts whatever it was doing.
	if _wander_dir != Vector3.ZERO:
		_stop_wandering()


## Only empty-handed dummies take weapons, and only when they're looking for one.
func wants_weapon(_weapon: Weapon) -> bool:
	return equipped_weapon == null and (target != null or grab_weapons_while_calm)


## The turf war's lost: they drop the fight, run from the player, and after
## a few seconds fade away for good.
func rout() -> void:
	if routed or is_down:
		return
	routed = true
	stop_fighting()
	_raid_left = 0.0
	_rout_left = randf_range(ROUT_TIME.x, ROUT_TIME.y)


func notice_fight(attacker: Citizen, victim: Citizen) -> void:
	if routed:
		return
	# Whoever the player goes after, their followers go after too.
	if following and attacker == following and not victim.is_down and not _is_ally(victim) \
			and global_position.distance_to(victim.global_position) <= defend_range:
		if not _still_fighting():
			start_fighting(victim)
		return
	super(attacker, victim)


func _choose_move_direction(delta: float) -> Vector3:
	if routed:
		return _run_off(delta)
	if faction == Factions.PLAYER:
		_update_crew_prompt()
	if following and not is_instance_valid(following):
		following = null
	if following:
		return _follow(delta)
	if _walk_out_left > 0.0:
		_walk_out_left -= delta
		return _walk_out_dir * minf(wander_speed / move_speed, 1.0)
	var fighting := _still_fighting() or _scan_for_hostiles(delta)
	if fighting:
		_wander_dir = Vector3.ZERO
	if _windup_left < 0.0 and _update_wanted_pickup(delta):
		return _fetch_weapon()
	if fighting:
		return _hold_turf(_fight(delta))
	if _raid_left > 0.0:
		return _go_raiding(delta)
	return _wander(delta)


## While home turf is at war, keeps `direction` from carrying us off it, and
## brings us back if we're already out.
func _hold_turf(direction: Vector3) -> Vector3:
	if home == null or not home.at_war:
		return direction
	if not home.contains(global_position):
		return _steer_toward(home.center())
	if not home.contains(global_position + direction * 0.8):
		return Vector3.ZERO
	return direction


func _go_raiding(delta: float) -> Vector3:
	_raid_left -= delta
	var to_point := _raid_point - global_position
	to_point.y = 0.0
	if to_point.length() < 1.5:
		_raid_left = 0.0
		return Vector3.ZERO
	# A purposeful walk, quicker than a stroll.
	return _steer_toward(_raid_point) * minf(wander_speed * 1.6 / move_speed, 1.0)


## Keeps _wanted_pickup pointing at a weapon we can see and still want.
## Returns whether there is one.
func _update_wanted_pickup(delta: float) -> bool:
	if _wanted_pickup and (not is_instance_valid(_wanted_pickup) or not _wanted_pickup.is_available_to(self)):
		_wanted_pickup = null
	if not wants_weapon(null):
		_wanted_pickup = null
		return false
	# Look around again every so often, so a closer weapon wins.
	_weapon_scan_left -= delta
	if _weapon_scan_left <= 0.0:
		_weapon_scan_left = WEAPON_SCAN_INTERVAL
		_wanted_pickup = _find_visible_pickup()
	return _wanted_pickup != null


func _find_visible_pickup() -> WeaponPickup:
	var best: WeaponPickup = null
	var best_distance := weapon_sight_range
	for pickup: WeaponPickup in get_tree().get_nodes_in_group("weapon_pickups"):
		var distance := global_position.distance_to(pickup.global_position)
		if distance < best_distance and pickup.is_available_to(self) \
				and _can_see(pickup.global_position) and _has_ground_below(pickup.global_position):
			best = pickup
			best_distance = distance
	return best


func _fetch_weapon() -> Vector3:
	# Grab it once close, even if we were already standing on it.
	if _flat_offset_to(_wanted_pickup).length() < 0.6 and _wanted_pickup.try_give_to(self):
		_wanted_pickup = null
		return Vector3.ZERO
	return _steer_toward(_wanted_pickup.global_position)


func _wander(delta: float) -> Vector3:
	_state_time_left -= delta
	if _state_time_left <= 0.0:
		if _wander_dir == Vector3.ZERO:
			var angle := randf() * TAU
			_wander_dir = Vector3(sin(angle), 0.0, cos(angle))
			# Off home turf (after a raid, say): head back toward the middle of it.
			if home and not home.contains(global_position):
				_wander_dir = home.center() - global_position
				_wander_dir.y = 0.0
				_wander_dir = _wander_dir.normalized()
			_state_time_left = randf_range(walk_time_range.x, walk_time_range.y)
		else:
			_stop_wandering()

	if _wander_dir != Vector3.ZERO:
		if is_swimming:
			if is_on_wall():
				request_jump()  # try to climb out
		elif is_on_wall() or _clip_at_ledges(_wander_dir, max_safe_drop) != _wander_dir:
			_stop_wandering()
		elif home and home.contains(global_position) and not home.contains(global_position + _wander_dir * 0.8):
			_stop_wandering()  # the edge of home turf
	# Wandering is a stroll, slower than the chase speed in move_speed.
	return _wander_dir * minf(wander_speed / move_speed, 1.0)


func _stop_wandering() -> void:
	_wander_dir = Vector3.ZERO
	_state_time_left = randf_range(idle_time_range.x, idle_time_range.y)
