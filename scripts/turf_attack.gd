class_name TurfAttack
extends CanvasLayer
## Now and then, while there's no turf war on, a rival gang comes for one of
## the player's turfs: one next to theirs, though never the home turf the
## crew started out with. "Our turf is under attack!", with
## an arrow pointing the way and the turf flashing their color on the map
## (Territory.under_attack_by). Their raiders show up once the player's close
## enough to see them, and come straight for the player and the crew.
##
## Take down every raider in time and the turf holds. Let the clock run out
## and it's theirs, raiders and all.

## How often to roll for an attack, and the chance each time.
const CHECK_INTERVAL := 60.0
## Raiders arrive this far apart, once the player's close enough.
const ARRIVAL_INTERVAL := 1.5

@export_range(0.0, 1.0) var chance := 0.2
## No attack this soon after the last attack or turf war ended, in seconds.
@export var quiet_time := 180.0
## Seconds the player has to fight them off.
@export var defend_time := 120.0
@export var party_size := Vector2i(3, 5)
## Raiders show up once the player's this close to the turf.
@export var arrival_range := 45.0
## Raiders show up this far from the player.
@export var spawn_distance := Vector2(14.0, 30.0)

var active := false
var turf: Territory
var attacker := &""

var _check_left := CHECK_INTERVAL
var _quiet_left := 0.0
var _time_left := 0.0
var _arrival_left := 0.0
## Raiders still to come, and ones taken down.
var _to_arrive := 0
var _party := 0
var _taken_down := 0
var _banner: Label
var _arrow: ScreenArrow


func _ready() -> void:
	add_to_group("turf_attacks")
	_build_ui()


func _process(delta: float) -> void:
	if not active:
		_maybe_start(delta)
		return
	var player := get_tree().get_first_node_in_group("player") as Citizen
	if player == null:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_lose()
		return
	var near := player.global_position.distance_to(turf.nearest_point(player.global_position)) < arrival_range
	_arrival_left -= delta
	if near and _to_arrive > 0 and _arrival_left <= 0.0:
		_arrival_left = ARRIVAL_INTERVAL
		_send_raider(player)
	var inside := turf.contains(player.global_position)
	_arrow.target = Vector3.INF if inside else turf.nearest_point(player.global_position)
	_banner.text = "Our turf is under attack!  %d:%02d   %d of %d down" % [
		floori(_time_left / 60.0), floori(fmod(_time_left, 60.0)), _taken_down, _party]


func _maybe_start(delta: float) -> void:
	_quiet_left -= delta
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_INTERVAL
	for war in get_tree().get_nodes_in_group("turf_wars"):
		if war.active:
			_quiet_left = quiet_time
	if _quiet_left > 0.0 or randf() >= chance:
		return
	start()


## A rival gang comes for one of the player's turfs, one bordering theirs.
## Nothing happens if there isn't one.
func start() -> void:
	var targets: Array[Territory] = []
	var attackers: Array[StringName] = []
	for mine: Territory in get_tree().get_nodes_in_group("territories"):
		# Home turf's safe.
		if mine.owner_faction() != Factions.PLAYER or mine.starting_owner == Factions.PLAYER:
			continue
		for theirs: Territory in get_tree().get_nodes_in_group("territories"):
			var gang := theirs.owner_faction()
			if gang != Factions.PLAYER and Factions.is_gang(gang) and mine.area.grow(2.0).intersects(theirs.area):
				targets.append(mine)
				attackers.append(gang)
	if targets.is_empty():
		return
	var pick := randi() % targets.size()
	turf = targets[pick]
	attacker = attackers[pick]
	turf.under_attack_by = attacker
	active = true
	_party = randi_range(party_size.x, party_size.y)
	_to_arrive = _party
	_taken_down = 0
	_time_left = defend_time
	_arrival_left = 0.0
	_banner.visible = true
	Sound.play(&"war_start")
	Transition.show_message("Our turf is under attack!")


func _send_raider(player: Citizen) -> void:
	var path: String = Factions.MEMBER_SCENES.get(attacker, "")
	var spot := turf.random_spot_near(player.global_position, spawn_distance)
	if path.is_empty() or spot == Vector3.INF:
		return
	var raider: GangMember = load(path).instantiate()
	raider.raider = true
	raider.position = spot
	if not turf.weapon_pool.is_empty() and randf() < turf.armed_chance:
		raider.starting_weapon = turf.weapon_pool.pick_random()
	get_tree().current_scene.add_child(raider)
	raider.reset_physics_interpolation()
	raider.start_fighting(player)
	_to_arrive -= 1
	raider.died.connect(_on_raider_down)
	# Gone without going down (wandered off where the city isn't loaded):
	# someone else takes their place.
	raider.tree_exiting.connect(func() -> void:
		if active and not raider.is_dead:
			_to_arrive += 1)


func _on_raider_down() -> void:
	_taken_down += 1
	if _taken_down >= _party:
		_end()
		Sound.play(&"victory")
		Transition.show_message("We held our turf!")


## Out of time: the turf's theirs, and the raiders still standing stay on.
func _lose() -> void:
	var lost := turf
	var gang := attacker
	_end()
	WorldState.set_territory_owner(lost.id, gang)
	lost.handed_over()
	for raider in get_tree().get_nodes_in_group(gang):
		if raider is GangMember and raider.raider and not raider.is_down:
			raider.raider = false
			raider.home = lost
	Transition.show_message("%s took our turf." % Factions.short_name(gang))


func _end() -> void:
	active = false
	turf.under_attack_by = &""
	_banner.visible = false
	_arrow.target = Vector3.INF
	_quiet_left = quiet_time


func _build_ui() -> void:
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -320.0
	_banner.offset_right = 320.0
	_banner.offset_top = 84.0
	_banner.offset_bottom = 116.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.visible = false
	add_child(_banner)
	_arrow = ScreenArrow.new()
	_arrow.color = Color(1.0, 0.75, 0.3)
	_arrow.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_arrow.offset_left = -40.0
	_arrow.offset_right = 40.0
	_arrow.offset_top = 118.0
	_arrow.offset_bottom = 198.0
	add_child(_arrow)
