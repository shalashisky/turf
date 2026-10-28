extends Label
## Shows the in-game date and time from GameClock.


func _ready() -> void:
	GameClock.time_changed.connect(_refresh)
	GameClock.day_started.connect(func(_day: int) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	text = "%s\n%s" % [GameClock.date_text(), GameClock.time_text()]
