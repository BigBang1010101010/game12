extends Node

## Autoload holding the player's condition: how long they have been awake,
## and (once the health system is added) their health. Kept out of player.gd
## so it survives any future rework of the character, and so the HUD and the
## sleep action can read and change it without reaching into the scene.

signal awake_changed(hours: float)

## In-game hours since the player last woke up. Advances off the day/night
## cycle's own rate rather than an independent one, so "awake time" and the
## clock on the wall can never drift apart.
var awake_hours: float = 0.0

func _ready() -> void:
	# Matches DayNightCycle: the clock keeps moving while the inventory has
	# the tree paused, so the awake counter has to as well or the two would
	# disagree by however long menus were left open.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	add_awake_hours(delta * DayNightCycle.game_hours_per_real_second())

## Adds in-game hours to the awake counter. Separate from _process so sleeping
## and tests can drive it directly instead of waiting in real time.
func add_awake_hours(hours: float) -> void:
	if hours == 0.0:
		return
	awake_hours += hours
	awake_changed.emit(awake_hours)

## Called when the player sleeps.
func reset_awake() -> void:
	awake_hours = 0.0
	awake_changed.emit(awake_hours)

## "Xh Ym" for display.
func get_awake_string() -> String:
	var h: int = int(awake_hours)
	var m: int = int((awake_hours - float(h)) * 60.0)
	return "%dh %02dm" % [h, m]
