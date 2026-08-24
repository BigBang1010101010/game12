extends CanvasLayer

## Autoload handling the "sleep" action (Z): fades to black, jumps the
## day/night clock forward to the next morning, resets how long the player has
## been awake, and fades back in.
##
## Requires standing next to a bed: try_sleep() asks the "bed" group whether
## any bed has the player in range, so more beds can be added anywhere with no
## change here. Pressing Z out of range shows a short message instead of
## silently doing nothing.
##
## Restoring health is deliberately routed through PlayerStats rather than
## done here, so that whatever else ends up affecting health goes through the
## same place. If no health system is present this simply does nothing extra,
## which keeps sleeping working on its own.

## Time of day the player wakes up at, as a fraction of the cycle.
## DayNightCycle.SUNRISE is 0.25; this is a little after it, so waking lands in
## early daylight rather than exactly on the horizon.
const WAKE_TIME := 0.29

const FADE_OUT_SECONDS := 0.45
const FADE_HOLD_SECONDS := 0.25
const FADE_IN_SECONDS := 0.45

signal slept(hours_skipped: float)

var fade_rect: ColorRect
var is_sleeping := false

func _ready() -> void:
	layer = 30 # above the HUD and the inventory
	process_mode = Node.PROCESS_MODE_ALWAYS
	fade_rect = ColorRect.new()
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.visible = false
	add_child(fade_rect)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sleep"):
		try_sleep()
		get_viewport().set_input_as_handled()

## Sleeps if possible. Returns false when already sleeping, or when the
## player is not next to a bed.
func try_sleep() -> bool:
	if is_sleeping:
		return false
	if not is_near_bed():
		InteractionUI.show_message("Necesitas estar cerca de una cama para dormir")
		return false
	_do_sleep()
	return true

## True when any bed in the scene currently has the player within range.
func is_near_bed() -> bool:
	for bed in get_tree().get_nodes_in_group("bed"):
		if bed.has_method("is_player_near") and bed.is_player_near():
			return true
	return false

func _do_sleep() -> void:
	is_sleeping = true

	fade_rect.visible = true
	await _fade_to(1.0, FADE_OUT_SECONDS)

	# Skip the clock forward rather than waiting out the hours in real time.
	var hours_skipped: float = DayNightCycle.skip_to(WAKE_TIME)
	PlayerStats.reset_awake()
	# Health is restored through PlayerStats when that system exists, so every
	# health change goes through one place.
	if PlayerStats.has_method("restore_full_health"):
		PlayerStats.restore_full_health()

	await _wait(FADE_HOLD_SECONDS)
	await _fade_to(0.0, FADE_IN_SECONDS)
	fade_rect.visible = false

	is_sleeping = false
	slept.emit(hours_skipped)

func _fade_to(target_alpha: float, duration: float) -> void:
	var start_alpha: float = fade_rect.color.a
	var elapsed := 0.0
	while elapsed < duration:
		# Unscaled delta: this must still run if something has paused the tree.
		var delta: float = get_process_delta_time()
		elapsed += delta
		fade_rect.color.a = lerpf(start_alpha, target_alpha, clampf(elapsed / duration, 0.0, 1.0))
		await get_tree().process_frame
	fade_rect.color.a = target_alpha

func _wait(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame
