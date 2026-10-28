class_name Pedestrian
extends Npc
## Someone out for a walk. Strolls along the sidewalks, turning at corners and
## now and then crossing the street, and runs from any fight that breaks out
## nearby, or from the player while a turf war is on. Once it's calm, they
## make their way back to the nearest sidewalk. They're nobody's neighbor, so
## safe doors won't take them in.
##
## Some will take a car: a stopped one nearby to get away when they're
## running, and now and then one left unattended as they walk past. (Not
## from under the player's nose, nor from the player's garage.)
##
## The player can offer them weed (interact, with weed in hand), once each.
## Folks on the street might buy, might not, and might shout for the police.
## Some don't wait to be asked: they come over to buy when they spot the
## player. Each kind is set up in its scene: ordinary passers-by never come
## over, a few of the homeless do (and pay with whatever they've got on
## them), and druggies always do, weed in hand or not, and pay over the odds.

const DIRECTIONS: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
## How far around to look for a sidewalk to get back to, in tiles.
const SIDEWALK_SEARCH_RADIUS := 8
## Walkers keep this far right of the middle of the sidewalk, so people going
## opposite ways pass each other.
const LANE_OFFSET := 0.26
## Stuck this long against someone or something, they turn around.
const STUCK_TIME := 0.8
## How far around them they'll look for a car to get away in.
const GETAWAY_SEARCH_RADIUS := 8.0
## Would-be car thieves look this far around them, this often.
const THIEF_SEARCH_RADIUS := 6.0
const THIEF_CHECK_INTERVAL := 1.5
## Nobody steals a car with the player this close to it.
const THIEF_PLAYER_DISTANCE := 12.0
## Buyers come this close to buy, and wait this long for the player to sell
## before giving up.
const BUY_DISTANCE := 1.5
const BUYER_PATIENCE := 12.0
## The deal prompt shows with the player this close.
const OFFER_RANGE := 2.2
## Shouting for the police gets the player wanted this much later.
const SNITCH_DELAY := 2.5
## What the homeless trade for weed, when they pay in kind. Weapons by path,
## loaded when they're handed over.
const TRADE_GOODS := [
	{"item": "weed_seed", "count": 2},
	{"item": "burger", "count": 1},
	{"item": "cocaine", "count": 1},
	{"weapon": "res://weapons/knife.tres"},
	{"weapon": "res://weapons/brass_knuckles.tres"},
	{"weapon": "res://weapons/baseball_bat.tres"},
	{"weapon": "res://weapons/pistol.tres", "ammo": 8},
	{"weapon": "res://weapons/molotov.tres", "ammo": 1},
]

## Strolling speed. move_speed is how fast they run.
@export var walk_speed := 1.4
## How close a fight has to be for them to notice it.
@export var notice_range := 14.0
## How long they keep running after the last thing that scared them.
@export var flee_time := 6.0
## Chance of crossing the street at the end of a stretch of sidewalk, instead of turning.
@export_range(0.0, 1.0) var cross_chance := 0.35
## Chance of stopping for a moment whenever they turn.
@export_range(0.0, 1.0) var pause_chance := 0.2
## Chance of taking a stopped car nearby to get away in, when they start running.
@export_range(0.0, 1.0) var getaway_chance := 0.35
## Chance of stealing each unattended car they walk past.
@export_range(0.0, 1.0) var car_thief_chance := 0.08
@export_group("Weed")
## Chance they come over to buy, when they spot the player with weed in hand.
@export_range(0.0, 1.0) var approach_chance := 0.0
## They come over whenever they spot the player, weed in hand or not.
@export var pesters := false
## They spot the player, to come over and buy, this far off.
@export var buyer_range := 9.0
## Chance they'll buy when the player offers, unasked.
@export_range(0.0, 1.0) var accept_chance := 0.5
## Chance that, turning the player down, they shout for the police.
@export_range(0.0, 1.0) var snitch_chance := 0.45
## What they pay, times the going rate.
@export var price_factor := 1.0
## They pay with something they've got on them (TRADE_GOODS), not cash.
@export var pays_in_kind := false
@export_group("")

var _grid: CityGrid
var _dir := Vector3.ZERO
var _crossing := false
var _pause_left := 0.0
var _flee_from := Vector3.ZERO
var _flee_left := 0.0
## A sidewalk tile to head back to after running off it.
var _way_back := Vector3.INF
var _stuck_time := 0.0
## Unattended cars they've already walked past, and decided about.
var _cars_passed := {}
var _thief_check_left := 0.0
var _will_approach := false
## They've already been offered weed, or bought some: once is enough.
var _dealt := false
## On their way over to buy, or waiting to.
var _buying := false
var _buy_patience := 0.0
var _sell_prompt: Interactable


func _ready() -> void:
	super()
	_grid = get_tree().get_first_node_in_group("city_grid")
	_will_approach = randf() < approach_chance
	_pause_left = randf_range(0.0, 2.0)


## Pedestrians don't fight: whoever's fighting near them, they run.
func notice_fight(attacker: Citizen, victim: Citizen) -> void:
	if is_down or self in [attacker, victim]:
		return
	if global_position.distance_to(victim.global_position) <= notice_range:
		_flee(victim.global_position)


func _react_to_hit(attacker: Citizen) -> void:
	if attacker and not is_down:
		_flee(attacker.global_position)


func _flee(from: Vector3) -> void:
	if _flee_left <= 0.0 and car_to_take == null and randf() < getaway_chance:
		var getaway := _stopped_car_near(GETAWAY_SEARCH_RADIUS)
		if getaway:
			go_take(getaway)
	_flee_from = from
	_flee_left = flee_time
	_crossing = false
	_way_back = Vector3.INF


func _choose_move_direction(delta: float) -> Vector3:
	if car_to_take:
		return _approach_car_to_take()
	_keep_away_from_turf_wars()
	if _flee_left > 0.0:
		_flee_left -= delta
		_buying = false
		if _sell_prompt:
			_sell_prompt.prompt = ""
		return _direction_away_from(_flee_from)
	_update_deal_prompt()
	if _will_approach and not _dealt and _update_buying(delta):
		return _toward_seller()
	_look_for_a_car_to_steal(delta)
	return _stroll(delta) * minf(walk_speed / move_speed, 1.0)


## Whether they're going over to buy from the player right now: they've
## spotted them (with weed in hand, unless they pester), and haven't run out
## of patience.
func _update_buying(delta: float) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Citizen
	var wanted := player != null and (pesters or _is_holding_weed(player)) and player.vehicle == null
	var distance := global_position.distance_to(player.global_position) if player else INF
	if not _buying:
		if not wanted or distance > buyer_range or not _can_see(player.global_position):
			return false
		_buying = true
		_buy_patience = BUYER_PATIENCE
		call_out("Hey... hey man, you holding?" if pesters else "Psst... got any?")
	_buy_patience -= delta
	if not wanted or distance > buyer_range + 4.0 or _buy_patience <= 0.0:
		_buying = false
		return false
	return true


func _toward_seller() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if global_position.distance_to(player.global_position) <= BUY_DISTANCE:
		face_toward(player.global_position)
		return Vector3.ZERO
	return _steer_toward(player.global_position) * minf(maxf(walk_speed * 1.5, 1.6) / move_speed, 1.0)


func _is_holding_weed(player: Citizen) -> bool:
	return player.has_method("is_offering_weed") and player.is_offering_weed()


## "[E] Offer weed" when the player's close with weed in hand, or "Sell weed"
## to someone who's asked for it.
func _update_deal_prompt() -> void:
	var player := get_tree().get_first_node_in_group("player") as Citizen
	var dealing := player != null and not _dealt and _is_holding_weed(player) \
		and global_position.distance_to(player.global_position) < OFFER_RANGE + 2.0
	if not dealing:
		if _sell_prompt:
			_sell_prompt.prompt = ""
		return
	if _sell_prompt == null:
		_sell_prompt = Interactable.new()
		_sell_prompt.collision_layer = 0
		_sell_prompt.collision_mask = 2
		_sell_prompt.prompt_height = 2.0
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = OFFER_RANGE
		shape.shape = sphere
		shape.position.y = 0.8
		_sell_prompt.add_child(shape)
		add_child(_sell_prompt)
		_sell_prompt.interacted.connect(_offered_weed)
	var prompt := "Offer weed"
	if _buying:
		prompt = "Trade weed" if pays_in_kind else "Sell weed ($%d)" % _price()
	if _sell_prompt.prompt != prompt:
		_sell_prompt.prompt = prompt


func _price() -> int:
	return roundi(WorldState.weed_price_at(global_position) * price_factor)


## The player holds out a bag. Whoever asked for it takes it. Anyone else
## might, or might turn them down, and might shout for the police.
func _offered_weed(seller: Citizen) -> void:
	if _dealt or not _is_holding_weed(seller):
		return
	var asked := _buying
	var goods: Dictionary = TRADE_GOODS.pick_random() if pays_in_kind else {}
	if pays_in_kind and not _room_for(goods):
		call_out("Your pockets are full, man.")
		return
	_dealt = true
	_buying = false
	if _sell_prompt:
		_sell_prompt.prompt = ""
	if not asked and randf() >= accept_chance:
		if randf() < snitch_chance:
			call_out("Officer! Help!", Color(1.0, 0.4, 0.35))
			_flee(seller.global_position)
			get_tree().create_timer(SNITCH_DELAY).timeout.connect(Factions.report_player_crime)
		else:
			call_out("Nah, I'm good.")
		return
	if not WorldState.add_item("weed", -1):
		return
	if pays_in_kind:
		_hand_over(goods, seller)
	else:
		var price := _price()
		WorldState.add_money(price)
		call_out("+$%d" % price, Color(0.55, 1.0, 0.45))
	Factions.witness_deal(seller, global_position)


func _room_for(goods: Dictionary) -> bool:
	if goods.has("weapon"):
		return Inventory.has_room_for(load(goods.weapon))
	return WorldState.item_count(goods.item) > 0 or Inventory.slots.has(null)


func _hand_over(goods: Dictionary, player: Citizen) -> void:
	if goods.has("weapon"):
		var weapon: Weapon = load(goods.weapon)
		player.equip(weapon, goods.get("ammo", -1))
		call_out("Here, take this %s." % weapon.display_name, Color(1.0, 0.9, 0.5))
	else:
		WorldState.add_item(goods.item, goods.count)
		var name := WorldState.item_name(goods.item).to_lower()
		var line := "Here, take this %s." % name if goods.count == 1 else "Here, %d %ss." % [goods.count, name]
		call_out(line, Color(1.0, 0.9, 0.5))


func _look_for_a_car_to_steal(delta: float) -> void:
	_thief_check_left -= delta
	if _thief_check_left > 0.0 or car_thief_chance <= 0.0:
		return
	_thief_check_left = THIEF_CHECK_INTERVAL
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for car: Vehicle in get_tree().get_nodes_in_group("vehicles"):
		if _cars_passed.has(car) or not car.is_unattended() or absf(car.speed) > 0.5 \
				or global_position.distance_to(car.global_position) > THIEF_SEARCH_RADIUS:
			continue
		if player and car.global_position.distance_to(player.global_position) < THIEF_PLAYER_DISTANCE:
			continue
		var garaged := false
		for garage: Garage in get_tree().get_nodes_in_group("garages"):
			garaged = garaged or garage.holds(car)
		if garaged:
			continue
		# Each car they could steal, they make their mind up about once.
		_cars_passed[car] = true
		if randf() < car_thief_chance:
			go_take(car)
			return


## The nearest car within `radius` that's stopped or nearly, and not the
## player's to drive right now.
func _stopped_car_near(radius: float) -> Vehicle:
	var best: Vehicle = null
	var best_distance := radius
	for car: Vehicle in get_tree().get_nodes_in_group("vehicles"):
		if car.is_wrecked or absf(car.speed) > 1.5 or (car.driver and car.driver.is_in_group("player")):
			continue
		var distance := global_position.distance_to(car.global_position)
		if distance < best_distance:
			best = car
			best_distance = distance
	return best


func _keep_away_from_turf_wars() -> void:
	for war in get_tree().get_nodes_in_group("turf_wars"):
		if war.active:
			var player := get_tree().get_first_node_in_group("player") as Node3D
			if player and global_position.distance_to(player.global_position) < notice_range:
				_flee(player.global_position)
			return


func _stroll(delta: float) -> Vector3:
	if _grid == null:
		return Vector3.ZERO
	if _pause_left > 0.0:
		_pause_left -= delta
		return Vector3.ZERO
	var here := _grid.tile_at(global_position)
	if here != CityGrid.SIDEWALK and not _crossing:
		return _head_back_to_sidewalk()
	_way_back = Vector3.INF

	if _dir == Vector3.ZERO:
		_dir = _pick_direction()
		if _dir == Vector3.ZERO:
			return Vector3.ZERO
	# Wedged against someone coming the other way, or a lamp post: turn back.
	if Vector2(velocity.x, velocity.z).length() < 0.3:
		_stuck_time += delta
		if _stuck_time > STUCK_TIME:
			_stuck_time = 0.0
			_crossing = false
			_dir = -_dir
	else:
		_stuck_time = 0.0
	var ahead := _grid.tile_at(global_position + _dir * 0.8)
	if _crossing:
		if here == CityGrid.SIDEWALK and ahead != CityGrid.ROAD:
			_crossing = false  # made it across
		elif ahead != CityGrid.ROAD and ahead != CityGrid.SIDEWALK:
			_crossing = false
			_dir = _pick_direction()
	elif ahead != CityGrid.SIDEWALK:
		# End of this stretch: cross the street, or turn the corner.
		if ahead == CityGrid.ROAD and randf() < cross_chance and _street_ends_in_sidewalk():
			_crossing = true
		else:
			_dir = _pick_direction()
			if randf() < pause_chance:
				_pause_left = randf_range(1.0, 3.0)
			return Vector3.ZERO
	return (_dir + _stay_in_lane()).normalized()


## A sidewalk to turn onto from here: anything but straight back, unless
## that's the only way.
func _pick_direction() -> Vector3:
	var options: Array[Vector3] = []
	for direction in DIRECTIONS:
		if direction != -_dir and _grid.tile_at(global_position + direction) == CityGrid.SIDEWALK:
			options.append(direction)
	if options.is_empty() and _grid.tile_at(global_position - _dir) == CityGrid.SIDEWALK:
		options.append(-_dir)
	return options.pick_random() if not options.is_empty() else Vector3.ZERO


## Whether walking straight across the road ahead lands on another sidewalk.
func _street_ends_in_sidewalk() -> bool:
	for distance in range(2, 6):
		var tile := _grid.tile_at(global_position + _dir * distance)
		if tile != CityGrid.ROAD:
			return tile == CityGrid.SIDEWALK
	return false


## A nudge toward the right-hand side of the sidewalk, sideways to the walk.
func _stay_in_lane() -> Vector3:
	var right := Vector3(-_dir.z, 0.0, _dir.x)
	var lane := _grid.tile_center(global_position) + right * LANE_OFFSET
	var offset := lane - global_position
	return offset * right.abs() * 2.0


func _head_back_to_sidewalk() -> Vector3:
	if _way_back == Vector3.INF:
		_way_back = _nearest_sidewalk()
		if _way_back == Vector3.INF:
			return Vector3.ZERO
	_dir = Vector3.ZERO
	return _steer_toward(_way_back)


func _nearest_sidewalk() -> Vector3:
	for radius in range(1, SIDEWALK_SEARCH_RADIUS + 1):
		var best := Vector3.INF
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var spot := global_position + Vector3(dx, 0.0, dz)
				if _grid.tile_at(spot) == CityGrid.SIDEWALK:
					var center := _grid.tile_center(spot)
					if best == Vector3.INF or global_position.distance_to(center) < global_position.distance_to(best):
						best = center
		if best != Vector3.INF:
			return best
	return Vector3.INF
