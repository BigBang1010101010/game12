extends Node

## Autoload driving a full day/night cycle and exposing the in-game clock that
## other systems (energy, sleeping) read and write.
##
## The cycle is expressed as a single normalised value, `time_of_day`, in
## [0, 1): 0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset. One full
## turn takes CYCLE_DURATION_SECONDS of real time, which is deliberately
## expressed as a named constant rather than a bare number so the "30 real
## minutes" requirement is checkable in one place.
##
## It attaches to whatever scene is running: it looks up the current scene's
## DirectionalLight3D and WorldEnvironment each time the scene changes, and
## does nothing (rather than erroring) in scenes that have neither.

## One complete day + night, in real seconds. 30 minutes: 15 of daylight and
## 15 of darkness, with the sunrise/sunset transitions blended across the
## boundaries rather than switching abruptly.
const CYCLE_DURATION_SECONDS := 30.0 * 60.0

## In-game hours per full cycle. Used to convert `time_of_day` into a clock
## other systems can talk about in hours.
const HOURS_PER_DAY := 24.0

## Key points of the cycle, as fractions of it.
const SUNRISE := 0.25
const NOON := 0.5
const SUNSET := 0.75

## Light colour/energy at each phase. Interpolated between, so dawn and dusk
## are gradients rather than cuts.
const DAY_COLOR := Color(1.0, 0.97, 0.88)
const DAY_ENERGY := 1.0
const DUSK_COLOR := Color(1.0, 0.55, 0.25)
const DUSK_ENERGY := 0.55
const NIGHT_COLOR := Color(0.45, 0.55, 0.9)
const NIGHT_ENERGY := 0.20

const DAY_FOG := Color(0.62, 0.70, 0.80)
const DUSK_FOG := Color(0.72, 0.48, 0.34)
const NIGHT_FOG := Color(0.07, 0.09, 0.16)

const DAY_SKY_TOP := Color(0.38, 0.52, 0.74)
const DAY_SKY_HORIZON := Color(0.65, 0.72, 0.82)
const DUSK_SKY_HORIZON := Color(0.85, 0.48, 0.28)
const NIGHT_SKY_TOP := Color(0.03, 0.04, 0.09)
const NIGHT_SKY_HORIZON := Color(0.08, 0.10, 0.18)

const DAY_AMBIENT := Color(0.75, 0.8, 0.9)
## Tuned against measured screen luminance rather than by eye: at 0.30 the
## sunlit sidewalks blew out (3.66% of ground pixels clipped to white once
## ambient started actually applying); 0.20 keeps the day bright with no
## clipping. The night value is low enough to read as night without going
## black - the scene stays visible at roughly half the sunset brightness.
const DAY_AMBIENT_ENERGY := 0.20
const NIGHT_AMBIENT := Color(0.30, 0.38, 0.62)
const NIGHT_AMBIENT_ENERGY := 0.30

## Normalised position in the cycle, [0, 1). Starts at mid-morning so a fresh
## game begins in daylight rather than in the dark.
var time_of_day: float = 0.35

## Emitted once per crossing of midnight, for anything that counts days.
signal day_passed

## Monotonic count of real seconds this world has been running, including
## time skipped by sleeping. This is THE clock: anything that measures
## elapsed time (the awake counter, and through it health loss) reads it
## instead of accumulating its own delta, so the two can never drift apart.
var total_elapsed_seconds: float = 0.0

var _light: DirectionalLight3D = null
var _environment: Environment = null
var _days_elapsed: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps running while the game is paused
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_rebind")

func _process(delta: float) -> void:
	advance_seconds(delta)

## Advances the clock by `seconds` of real time and re-applies the lighting.
## Split out from _process so tests (and the sleep action) can drive the cycle
## directly instead of waiting in real time.
func advance_seconds(seconds: float) -> void:
	var before := time_of_day
	total_elapsed_seconds += seconds
	time_of_day = fposmod(time_of_day + seconds / CYCLE_DURATION_SECONDS, 1.0)
	if time_of_day < before:
		_days_elapsed += 1
		day_passed.emit()
	_apply()

## Jumps the clock forward to a specific point in the cycle, returning how many
## in-game hours were skipped. Used by sleeping.
func skip_to(target_time_of_day: float) -> float:
	var delta_fraction: float = fposmod(target_time_of_day - time_of_day, 1.0)
	# Skipped hours are still elapsed world time, so the monotonic clock has
	# to move with them or sleeping would rewind everything derived from it.
	total_elapsed_seconds += delta_fraction * CYCLE_DURATION_SECONDS
	time_of_day = fposmod(target_time_of_day, 1.0)
	_days_elapsed += 1
	day_passed.emit()
	_apply()
	return delta_fraction * HOURS_PER_DAY

## Current in-game hour, 0-24, for UI and for systems that think in hours.
func get_hour() -> float:
	return time_of_day * HOURS_PER_DAY

## How many in-game hours one real second advances the clock. Systems that
## accumulate game time (the awake timer) use this so they stay locked to the
## same cycle instead of keeping their own independent rate.
func game_hours_per_real_second() -> float:
	return HOURS_PER_DAY / CYCLE_DURATION_SECONDS

func is_night() -> bool:
	return time_of_day < SUNRISE or time_of_day >= SUNSET

func get_days_elapsed() -> int:
	return _days_elapsed

## "HH:MM" for display.
func get_clock_string() -> String:
	var hours: float = get_hour()
	var h: int = int(hours)
	var m: int = int((hours - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]

func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D or node is WorldEnvironment:
		call_deferred("_rebind")

## Finds the light and environment in whatever scene is currently loaded.
func _rebind() -> void:
	var scene := get_tree().current_scene
	if not scene:
		return
	_light = _find_node_of_type(scene, "DirectionalLight3D")
	var world_env := _find_node_of_type(scene, "WorldEnvironment")
	_environment = (world_env as WorldEnvironment).environment if world_env else null
	_apply()

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for c in node.get_children():
		var found := _find_node_of_type(c, type_name)
		if found:
			return found
	return null

## Pushes the current time of day onto the light and the environment.
func _apply() -> void:
	if is_instance_valid(_light):
		# The sun sweeps a full rotation per cycle around the world X axis,
		# so it rises around SUNRISE, peaks at NOON and sets around SUNSET.
		# Offset so that time_of_day = SUNRISE puts it on the horizon.
		var sun_angle: float = (time_of_day - SUNRISE) * TAU
		_light.rotation = Vector3(-sun_angle, deg_to_rad(-30.0), 0.0)
		_light.light_color = _phase_color()
		_light.light_energy = _phase_energy()

	if _environment:
		var night_blend: float = _night_blend()
		var dusk_blend: float = _dusk_blend()
		_environment.ambient_light_color = DAY_AMBIENT.lerp(NIGHT_AMBIENT, night_blend)
		_environment.ambient_light_energy = lerpf(DAY_AMBIENT_ENERGY, NIGHT_AMBIENT_ENERGY, night_blend)

		# Distance fog hides the hard edge of the world. Tinting it with the
		# same blends keeps the horizon consistent with the lighting instead
		# of leaving a daylight-blue haze hanging over a night scene.
		var fog: Color = DAY_FOG.lerp(NIGHT_FOG, night_blend).lerp(DUSK_FOG, dusk_blend)
		_environment.fog_light_color = fog

		# The procedural sky is otherwise a fixed noon blue, which reads
		# badly at midnight. Darkening its colours by the same blend keeps
		# the backdrop in step with the light.
		var sky_material: ProceduralSkyMaterial = null
		if _environment.sky:
			sky_material = _environment.sky.sky_material as ProceduralSkyMaterial
		if sky_material:
			sky_material.sky_top_color = DAY_SKY_TOP.lerp(NIGHT_SKY_TOP, night_blend)
			sky_material.sky_horizon_color = (
				DAY_SKY_HORIZON.lerp(NIGHT_SKY_HORIZON, night_blend).lerp(DUSK_SKY_HORIZON, dusk_blend))
			sky_material.ground_horizon_color = sky_material.sky_horizon_color
			sky_material.ground_bottom_color = DAY_SKY_TOP.lerp(NIGHT_SKY_TOP, night_blend)

## 0.0 in full daylight, 1.0 in full night, ramping across dawn and dusk so
## the change is gradual rather than a switch.
func _night_blend() -> float:
	# Distance from noon, as a fraction of half a cycle: 0 at noon, 1 at
	# midnight. Smoothstep over the dawn/dusk quarters turns that into a soft
	# ramp that is flat during the middle of day and night.
	var from_noon: float = absf(_signed_distance(time_of_day, NOON)) * 2.0
	return smoothstep(0.45, 0.85, from_noon)

## How strongly the warm sunrise/sunset tint applies: peaks exactly at the
## horizon crossings and falls off either side.
func _dusk_blend() -> float:
	var to_sunrise: float = absf(_signed_distance(time_of_day, SUNRISE))
	var to_sunset: float = absf(_signed_distance(time_of_day, SUNSET))
	var nearest: float = minf(to_sunrise, to_sunset)
	return 1.0 - smoothstep(0.0, 0.09, nearest)

func _phase_color() -> Color:
	var base: Color = DAY_COLOR.lerp(NIGHT_COLOR, _night_blend())
	return base.lerp(DUSK_COLOR, _dusk_blend())

func _phase_energy() -> float:
	var base: float = lerpf(DAY_ENERGY, NIGHT_ENERGY, _night_blend())
	return lerpf(base, DUSK_ENERGY, _dusk_blend() * 0.6)

## Shortest signed distance between two points on the [0,1) circle.
func _signed_distance(a: float, b: float) -> float:
	var d: float = fposmod(a - b, 1.0)
	return d - 1.0 if d > 0.5 else d
