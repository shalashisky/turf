extends Node
## The in-game clock and calendar, autoloaded as GameClock.
##
## A day runs from 6:00 AM until 2:00 AM the next morning, then the next day
## starts at 6:00 AM. Time moves continuously, but like most life sims it's
## shown in 10-minute steps.
##
## Debug: [ and ] jump an hour back or forward.

## Fired whenever the shown time ticks over to the next 10 minutes.
signal time_changed
signal day_started(day_index: int)

const DAY_START_MINUTE := 6 * 60
## 2:00 AM the next morning, counted on from the same day's midnight.
const DAY_END_MINUTE := 26 * 60
const MINUTES_PER_DAY := 24 * 60
const DAYS_PER_SEASON := 28
const SEASONS := ["Spring", "Summer", "Fall", "Winter"]
const WEEKDAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

## Real seconds per in-game minute. At 0.7 a whole day takes about 14 real minutes.
@export var seconds_per_minute := 0.7

var paused := false
## Minutes since the current day's midnight. Goes past 24:00 after midnight.
var minutes := float(DAY_START_MINUTE)
## Days since the game started, counting from 0.
var day_index := 0

var _shown_minute := -1


func _process(delta: float) -> void:
	if paused:
		return
	minutes += delta / seconds_per_minute
	if minutes >= DAY_END_MINUTE:
		_start_next_day()
	_notify_if_time_changed()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_BRACKETRIGHT:
		skip_hours(1.0)
	elif key.keycode == KEY_BRACKETLEFT:
		skip_hours(-1.0)


## Moves the clock within the current day. Use for sleeping, cutscenes, debugging.
func skip_hours(hours: float) -> void:
	minutes = clampf(minutes + hours * 60.0, DAY_START_MINUTE, DAY_END_MINUTE - 1.0)
	_notify_if_time_changed()


## Minutes since the game started, counting the skipped night hours too.
## Use this to timestamp things that change over time, like crops.
func absolute_minutes() -> float:
	return day_index * MINUTES_PER_DAY + minutes


## Hour of the day as a float on a 24-hour clock, 0 at midnight. 1:30 AM is 1.5.
func hour_of_day() -> float:
	return fmod(minutes, MINUTES_PER_DAY) / 60.0


## "6:40 AM", in 10-minute steps.
func time_text() -> String:
	var minute_of_day := (floori(minutes / 10.0) * 10) % MINUTES_PER_DAY
	var hour := floori(minute_of_day / 60.0)
	var hour_12 := hour % 12
	if hour_12 == 0:
		hour_12 = 12
	return "%d:%02d %s" % [hour_12, minute_of_day % 60, "AM" if hour < 12 else "PM"]


## "Mon, Spring 1", plus the year from year 2 on.
@warning_ignore("integer_division")
func date_text() -> String:
	var days_per_year := DAYS_PER_SEASON * SEASONS.size()
	var season: String = SEASONS[(day_index % days_per_year) / DAYS_PER_SEASON]
	var day_of_season := day_index % DAYS_PER_SEASON + 1
	var weekday: String = WEEKDAYS[day_index % WEEKDAYS.size()]
	var year := day_index / days_per_year + 1
	var text := "%s, %s %d" % [weekday, season, day_of_season]
	return text if year == 1 else "%s, Year %d" % [text, year]


func _start_next_day() -> void:
	day_index += 1
	minutes = DAY_START_MINUTE
	day_started.emit(day_index)


func _notify_if_time_changed() -> void:
	var shown := floori(minutes / 10.0)
	if shown != _shown_minute:
		_shown_minute = shown
		time_changed.emit()
