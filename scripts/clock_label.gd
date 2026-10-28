extends Label
## Shows the in-game date and time from GameClock, and whether it's raining.


func _ready() -> void:
	GameClock.time_changed.connect(_refresh)
	GameClock.day_started.connect(func(_day: int) -> void: _refresh())
	Weather.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	text = "%s\n%s" % [GameClock.date_text(), GameClock.time_text()]
	if Weather.raining:
		text += "  ·  Rain"
