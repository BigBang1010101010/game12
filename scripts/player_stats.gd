extends Node

## Autoload holding the player's condition: how long they have been awake,
## and (once the health system is added) their health. Kept out of player.gd
## so it survives any future rework of the character, and so the HUD and the
## sleep action can read and change it without reaching into the scene.

signal awake_changed(hours: float)
signal health_changed(half_hearts: int)

## Health is counted in HALF hearts, so a half-heart loss is a whole unit of
## the underlying value and nothing has to deal in fractions.
const MAX_HALF_HEARTS := 4 # 2 full hearts

## In-game hours of being awake that cost half a heart. Sleeping is the only
## thing that costs health for now, but the cost itself goes through
## change_health() like any other source would, so adding real damage later
## means calling that rather than editing this system.
const HOURS_AWAKE_PER_HALF_HEART := 0.5

## In-game hours since the player last woke up. Advances off the day/night
## cycle's own rate rather than an independent one, so "awake time" and the
## clock on the wall can never drift apart.
var awake_hours: float = 0.0

var health_half_hearts: int = MAX_HALF_HEARTS

## Awake hours already paid for in health, so each threshold is only charged
## once.
var _hours_charged: float = 0.0

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
	_apply_exhaustion()

## Charges half a heart for every whole HOURS_AWAKE_PER_HALF_HEART the player
## has been awake, at most once per threshold.
func _apply_exhaustion() -> void:
	while awake_hours - _hours_charged >= HOURS_AWAKE_PER_HALF_HEART:
		_hours_charged += HOURS_AWAKE_PER_HALF_HEART
		change_health(-1)

## Single entry point for every health change, damage or healing. Clamped to
## [0, MAX_HALF_HEARTS]; reaching 0 just leaves it at 0 for now, with no death
## or game-over behaviour yet.
func change_health(delta_half_hearts: int) -> void:
	var new_value: int = clampi(health_half_hearts + delta_half_hearts, 0, MAX_HALF_HEARTS)
	if new_value == health_half_hearts:
		return
	health_half_hearts = new_value
	health_changed.emit(health_half_hearts)

func restore_full_health() -> void:
	change_health(MAX_HALF_HEARTS - health_half_hearts)

func get_full_hearts() -> float:
	return health_half_hearts * 0.5

## Called when the player sleeps.
func reset_awake() -> void:
	awake_hours = 0.0
	_hours_charged = 0.0
	awake_changed.emit(awake_hours)

## "Xh Ym" for display.
func get_awake_string() -> String:
	var h: int = int(awake_hours)
	var m: int = int((awake_hours - float(h)) * 60.0)
	return "%dh %02dm" % [h, m]
