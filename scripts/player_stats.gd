extends Node

## Autoload holding the player's condition: how long they have been awake,
## and (once the health system is added) their health. Kept out of player.gd
## so it survives any future rework of the character, and so the HUD and the
## sleep action can read and change it without reaching into the scene.

signal awake_changed(hours: float)
signal health_changed(half_hearts: int)
signal stamina_changed(stamina: float)

## Health is counted in HALF hearts, so a half-heart loss is a whole unit of
## the underlying value and nothing has to deal in fractions.
const MAX_HALF_HEARTS := 4 # 2 full hearts

## In-game hours of being awake that cost half a heart. Deliberately equal to
## DayNightCycle.HOURS_PER_DAY: one half heart per FULL day/night cycle, i.e.
## per 30 real minutes awake, locked 1:1 to the cycle rather than to some
## independent unit. (It was 0.5 game hours, which measured out to a half
## heart every 37.5 real seconds - 1/48th of a cycle.)
## Sleeping is still the only thing that costs health, but the cost goes
## through change_health() like any other source would, so adding real damage
## later means calling that rather than editing this system.
const HOURS_AWAKE_PER_HALF_HEART := DayNightCycle.HOURS_PER_DAY

## Stamina, 0-100, spent by sprinting and regained by not sprinting. Unlike
## awake time (which is measured in game hours off the day/night clock), this
## is a physical gameplay resource, so it runs on real seconds and is ticked
## from the player's _physics_process - which means it correctly freezes when
## the inventory pauses the tree, instead of draining behind a menu.
const MAX_STAMINA := 100.0
const STAMINA_DRAIN_PER_SECOND := 20.0
const STAMINA_REGEN_PER_SECOND := 12.0
## After stamina bottoms out, sprint stays locked until this much has been
## regained. Without it, sprint would re-enable the instant a sliver of
## stamina appeared and flicker on and off every frame.
const STAMINA_SPRINT_RESUME := 20.0

var stamina: float = MAX_STAMINA
## Set when stamina hits 0, cleared once STAMINA_SPRINT_RESUME is back.
var _sprint_locked := false

## In-game hours since the player last woke up. DERIVED each frame from
## DayNightCycle.total_elapsed_seconds rather than accumulated here: both
## values then come from one single clock, so no amount of running can make
## the awake counter and the day/night cycle disagree.
var awake_hours: float = 0.0

## The reading of DayNightCycle.total_elapsed_seconds at the moment the
## player last woke up. awake_hours is just the distance from here to now.
var _awake_since_seconds: float = 0.0

var health_half_hearts: int = MAX_HALF_HEARTS

## Awake hours already paid for in health, so each threshold is only charged
## once.
var _hours_charged: float = 0.0

func _ready() -> void:
	# Matches DayNightCycle: the clock keeps moving while the inventory has
	# the tree paused, so the awake counter has to as well or the two would
	# disagree by however long menus were left open.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	_refresh_awake()

## Recomputes awake_hours from the shared clock.
func _refresh_awake() -> void:
	var elapsed: float = DayNightCycle.total_elapsed_seconds - _awake_since_seconds
	var hours: float = elapsed * DayNightCycle.game_hours_per_real_second()
	if is_equal_approx(hours, awake_hours):
		return
	awake_hours = hours
	awake_changed.emit(awake_hours)
	_apply_exhaustion()

## Shifts the wake-up anchor back so the player reads as having been awake
## `hours` longer. Used by tests to reach a state without waiting for it in
## real time; it moves the anchor rather than a second counter, so the single
## source of truth stays intact.
func add_awake_hours(hours: float) -> void:
	if hours == 0.0:
		return
	_awake_since_seconds -= hours / DayNightCycle.game_hours_per_real_second()
	_refresh_awake()

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
	# Waking up rested covers stamina too.
	restore_full_stamina()

func get_full_hearts() -> float:
	return health_half_hearts * 0.5

## Advances stamina for one frame. `sprinting` is whether the player is
## actually sprinting right now (holding the key AND moving AND allowed to),
## not merely whether the key is down.
func tick_stamina(delta: float, sprinting: bool) -> void:
	var before := stamina
	if sprinting:
		stamina = maxf(stamina - STAMINA_DRAIN_PER_SECOND * delta, 0.0)
		if stamina <= 0.0:
			_sprint_locked = true
	else:
		stamina = minf(stamina + STAMINA_REGEN_PER_SECOND * delta, MAX_STAMINA)
		if _sprint_locked and stamina >= STAMINA_SPRINT_RESUME:
			_sprint_locked = false
	if stamina != before:
		stamina_changed.emit(stamina)

## Whether sprinting is currently allowed at all.
func can_sprint() -> bool:
	return not _sprint_locked and stamina > 0.0

func is_sprint_locked() -> bool:
	return _sprint_locked

func get_stamina_ratio() -> float:
	return stamina / MAX_STAMINA

func restore_full_stamina() -> void:
	stamina = MAX_STAMINA
	_sprint_locked = false
	stamina_changed.emit(stamina)

## Called when the player sleeps.
func reset_awake() -> void:
	_awake_since_seconds = DayNightCycle.total_elapsed_seconds
	awake_hours = 0.0
	_hours_charged = 0.0
	awake_changed.emit(awake_hours)

## "Xh Ym" for display.
func get_awake_string() -> String:
	var h: int = int(awake_hours)
	var m: int = int((awake_hours - float(h)) * 60.0)
	return "%dh %02dm" % [h, m]
