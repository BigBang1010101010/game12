extends CharacterBody3D
class_name Bicycle

## A rideable bicycle. Mount and dismount with the existing proximity
## interaction (E); while mounted, W/S pedal and A/D steer, and the player is
## carried along on the saddle.
##
## Steering is speed-proportional rather than tank-style: the bike only turns
## while it is actually rolling, so it traces a real turning arc and cannot
## spin on the spot.
##
## Collision uses an upright capsule rather than a box matching the frame.
## That is deliberate: a CharacterBody3D has no built-in step-up, and a
## capsule's rounded bottom is what lets it ride up the city's 0.12 kerbs the
## same way the player does. A boxy collider would be more faithful to the
## silhouette but would catch on every kerb.

## Model measurements (unscaled, measured from the imported FBX):
## wheelbase 3.928 along -Z (so the model already faces Godot-forward and
## needs no yaw correction), wheel bottoms at y=-0.950, saddle centre at
## (0, 1.774, 1.254).
const MODEL_SCALE := 0.32
## Distance from the model's own origin down to the bottom of its wheels:
## 0.950 * MODEL_SCALE.
const MODEL_WHEEL_DROP := 0.950 * MODEL_SCALE
## Where to place the rider's origin so they sit ON the saddle rather than
## sunk into it. Measured against the MODEL's origin, not this body's, so that
## moving the model (as the ground-contact fix does) carries the rider with it
## instead of leaving them hanging in the air.
## Derived by measurement, not by assuming the player's origin is its hips:
## with the origin placed exactly at the saddle centre the rider's Hips bone
## measured 0.191 lower and 0.067 further forward than the saddle, so the
## offset is corrected by that much.
const SEAT_OFFSET_FROM_MODEL := Vector3(0.0, 0.786, 0.47)

## Cruising speed, about 2x the player's 5.0 walk.
const SPEED := 10.0
## Sprint on the bike pedals harder. Kept below the on-foot sprint multiplier
## so bike+sprint lands at 14.0 rather than an absurd number: 1.75x the 8.0
## the player reaches sprinting on foot.
const SPRINT_MULTIPLIER := 1.4
const REVERSE_SPEED := 3.0
const ACCELERATION := 8.0
const BRAKING := 12.0
## Radians per second of yaw at full speed. Scaled by how fast the bike is
## actually going, which is what produces a turning radius.
const TURN_RATE := 2.0

## How far to the side the rider is placed when getting off, so they never
## end up standing inside the frame.
const DISMOUNT_SIDE_OFFSET := 1.1

## Camera pushed back and up while riding, since the bike covers ground faster.
const RIDE_CAMERA_DISTANCE := 11.5
const RIDE_CAMERA_HEIGHT := 2.6

## Wheel radius in world units: the model's wheels span y -0.950..0.950
## unscaled, so 0.950 * MODEL_SCALE. Used to turn linear speed into the
## correct angular speed (omega = v / r) rather than spinning at some
## arbitrary rate.
const WHEEL_RADIUS := 0.950 * MODEL_SCALE

## Crank turns per wheel turn. A real bike gears up, so the legs pedal a good
## deal slower than the wheels spin; without this the rider's legs would
## blur round at wheel speed.
const GEAR_RATIO := 0.35

## Maximum roll into a turn. Subtle on purpose - it is a lean, not a stunt.
const MAX_LEAN_DEGREES := 12.0
const LEAN_RESPONSE := 6.0

var is_mounted := false
var rider: CharacterBody3D = null

var _speed := 0.0
var _model: Node3D = null

## How close to an end of the handlebar a vertex has to be, in the mesh's own
## units, to count as part of that grip. The bar's own half-width is 0.136, so
## this band covers the grip without reaching the stem.
const GRIP_END_BAND := 0.02

## One Marker3D per handlebar end, measured from the mesh in _cache_grips().
var _grips: Array[Node3D] = []

## Wheel spin state.
var _wheel_nodes: Array[Node3D] = []
var _wheel_rest_bases: Array[Basis] = []
## The spin axis expressed in each wheel's OWN local space, so the wheels
## turn about the bike's left-right axis regardless of how the imported
## model's node basis happens to be oriented.
var _wheel_axes: Array[Vector3] = []
var _wheel_angle := 0.0

## Pedal crank angle, in radians, advanced from the real speed.
var _pedal_phase := 0.0
## Current visual roll, eased toward the target so it banks in and out
## smoothly instead of snapping.
var _lean := 0.0

@onready var interaction_area: Interactable = $Area3D

func _ready() -> void:
	add_to_group("bicycle")
	_spawn_model()
	if interaction_area:
		interaction_area.interacted.connect(_on_interacted)

func _spawn_model() -> void:
	var packed: PackedScene = load("res://assets/environment/bicycle.fbx")
	if not packed:
		push_warning("Bicycle: could not load model")
		return
	_model = packed.instantiate()
	_model.name = "BikeModel"
	_model.scale = Vector3.ONE * MODEL_SCALE
	# Drop the model so the WHEELS meet the ground, rather than leaving its
	# origin on this body's origin. The collision capsule is centred on that
	# origin, so when the bike rests on the floor the origin floats half a
	# capsule above it: measured, the wheels sat exactly 0.5500 above the floor
	# with the old fixed +0.304. Wheel bottom = origin + offset - wheel drop,
	# and it needs to equal the capsule's bottom, so offset = wheel drop minus
	# half the capsule. Read from the shape so it stays right if it is resized.
	_model.position.y = MODEL_WHEEL_DROP - _capsule_half_height()
	add_child(_model)
	call_deferred("_cache_wheels")
	call_deferred("_cache_grips")

## Half the height of this body's collision capsule, i.e. how far its lowest
## point sits below the origin.
func _capsule_half_height() -> float:
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision and collision.shape is CapsuleShape3D:
		return (collision.shape as CapsuleShape3D).height * 0.5
	return 0.55

## Finds the wheel nodes and works out which axis, in each wheel's own local
## space, corresponds to the bike's left-right axis - that is the axle they
## must spin about.
func _cache_wheels() -> void:
	for wheel_name in ["FrontWheel", "BackWheel"]:
		var node: Node3D = _model.find_child(wheel_name, true, false)
		if not node:
			continue
		_wheel_nodes.append(node)
		_wheel_rest_bases.append(node.transform.basis)
		var axis: Vector3 = (node.global_transform.basis.inverse() * global_transform.basis.x).normalized()
		_wheel_axes.append(axis)

## Marks where the rider's hands go, by MEASURING the ends of the handlebar
## mesh instead of assuming a width. Both grips are found the same way and
## deliberately not labelled left/right here - which hand takes which is
## decided by the rider, from its own shoulders (see player.gd), so this keeps
## working whatever way the bike or the rig happens to face.
func _cache_grips() -> void:
	_grips.clear()
	if not _model:
		return
	var handle := _model.find_child("Handle", true, false) as MeshInstance3D
	if not handle or not handle.mesh:
		return
	# The bike's own left-right axis, brought into the handlebar's local space,
	# so the extremes are measured along the bar rather than along whatever
	# axis the mesh happens to be authored on.
	var lateral: Vector3 = (handle.global_transform.basis.inverse() * global_transform.basis.x).normalized()
	var vertices := PackedVector3Array()
	for surface in range(handle.mesh.get_surface_count()):
		vertices.append_array(handle.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	if vertices.is_empty():
		return
	var menor: float = INF
	var mayor: float = -INF
	for v in vertices:
		var d: float = v.dot(lateral)
		menor = minf(menor, d)
		mayor = maxf(mayor, d)
	# One marker per end, placed at the centroid of the vertices within
	# GRIP_END_BAND of that end: the centroid lands in the middle of the grip
	# rather than on the outermost point of the bar cap, and it carries the
	# grip's real height and sweep, not just its width.
	for extremo in [menor, mayor]:
		var suma := Vector3.ZERO
		var contados: int = 0
		for v in vertices:
			if absf(v.dot(lateral) - extremo) < GRIP_END_BAND:
				suma += v
				contados += 1
		if contados == 0:
			continue
		var marcador := Marker3D.new()
		marcador.name = "Grip%d" % _grips.size()
		handle.add_child(marcador)
		marcador.position = suma / float(contados)
		_grips.append(marcador)

## World positions of the two handlebar grips, for whoever is riding.
func get_grip_nodes() -> Array[Node3D]:
	return _grips

func _on_interacted() -> void:
	# The same E press both mounts and dismounts.
	if is_mounted:
		dismount()
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	mount(players[0])

func mount(player: CharacterBody3D) -> void:
	if is_mounted:
		return
	rider = player
	is_mounted = true
	_speed = 0.0
	# Face the bike the way the rider was facing, so mounting doesn't snap the
	# view around.
	rotation.y = player.global_rotation.y
	# The rider sits inside this body's own capsule. Without an explicit
	# exception, move_and_slide() depenetrates that overlap every frame and
	# shoves the bike forward, which compounds into a runaway speed (measured
	# at 32.8 u/s against a 10.0 top speed) instead of the intended cruise.
	add_collision_exception_with(player)
	player.add_collision_exception_with(self)
	if player.has_method("set_handlebar_targets") and _model:
		var objetivos: Array[Node3D] = get_grip_nodes()
		if objetivos.is_empty():
			# Measuring failed (no mesh, or a model without a Handle): fall
			# back to the bar's own origin so the arms still reach forward.
			var handle := _model.find_child("Handle", true, false) as Node3D
			if handle:
				objetivos = [handle]
		player.set_handlebar_targets(objetivos)
	if player.has_method("set_mounted"):
		player.set_mounted(self)
	_set_camera_ride_view(true)
	if interaction_area:
		interaction_area.prompt_text = "Presiona E para bajarte"

func dismount() -> void:
	if not is_mounted:
		return
	var player := rider
	is_mounted = false
	rider = null
	_speed = 0.0
	velocity = Vector3.ZERO

	if player:
		remove_collision_exception_with(player)
		player.remove_collision_exception_with(self)
		# Step off to the left of the frame, then let the body settle onto
		# whatever ground is there rather than leaving it floating.
		var side: Vector3 = -global_transform.basis.x.normalized()
		player.global_position = global_position + side * DISMOUNT_SIDE_OFFSET + Vector3(0, 0.9, 0)
		player.velocity = Vector3.ZERO
		if player.has_method("set_mounted"):
			player.set_mounted(null)
	_set_camera_ride_view(false)
	if interaction_area:
		interaction_area.prompt_text = "Presiona E para montar"

func _set_camera_ride_view(riding: bool) -> void:
	if not rider and not riding:
		# On dismount the rider reference is already cleared, so find it again.
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		var rig = (players[0] as Node).get_node_or_null("CameraYaw")
		if rig and rig.has_method("set_ride_view"):
			rig.set_ride_view(false, 0.0, 0.0)
		return
	if not rider:
		return
	var rig = rider.get_node_or_null("CameraYaw")
	if rig and rig.has_method("set_ride_view"):
		rig.set_ride_view(riding, RIDE_CAMERA_DISTANCE, RIDE_CAMERA_HEIGHT)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	if is_mounted:
		_drive(delta)
	else:
		_speed = move_toward(_speed, 0.0, BRAKING * delta)

	var forward: Vector3 = -global_transform.basis.z
	velocity.x = forward.x * _speed
	velocity.z = forward.z * _speed
	move_and_slide()

	_update_wheels(delta)
	_update_lean(delta)

	if is_mounted and rider:
		_carry_rider()

## Spins both wheels at omega = v / r, so the rotation is tied to how fast the
## bike is actually travelling rather than to a fixed rate.
func _update_wheels(delta: float) -> void:
	if _wheel_nodes.is_empty():
		return
	_wheel_angle += (_speed / WHEEL_RADIUS) * delta
	_pedal_phase += (_speed / WHEEL_RADIUS) * GEAR_RATIO * delta
	for i in range(_wheel_nodes.size()):
		_wheel_nodes[i].transform.basis = _wheel_rest_bases[i] * Basis(_wheel_axes[i], _wheel_angle)

## Banks the whole bike (and with it the rider, who is parented by position
## and heading) into a turn, proportionally to how hard it is turning and how
## fast it is going.
func _update_lean(delta: float) -> void:
	var steer: float = 0.0
	if is_mounted:
		steer = Input.get_axis("move_right", "move_left")
	var speed_ratio: float = clampf(_speed / SPEED, -1.0, 1.0)
	var target: float = deg_to_rad(MAX_LEAN_DEGREES) * -steer * speed_ratio
	_lean = lerpf(_lean, target, clampf(delta * LEAN_RESPONSE, 0.0, 1.0))
	if _model:
		_model.rotation.z = _lean

func get_lean() -> float:
	return _lean

func _drive(delta: float) -> void:
	var throttle: float = Input.get_axis("move_back", "move_forward")
	var steer: float = Input.get_axis("move_right", "move_left")

	# Sprinting on the bike costs stamina exactly like sprinting on foot, and
	# only counts while actually pedalling forward.
	var sprinting: bool = (
		Input.is_action_pressed("sprint")
		and throttle > 0.0
		and PlayerStats.can_sprint()
	)
	PlayerStats.tick_stamina(delta, sprinting)

	var top_speed: float = SPEED * (SPRINT_MULTIPLIER if sprinting else 1.0)
	if throttle > 0.0:
		_speed = move_toward(_speed, top_speed, ACCELERATION * delta)
	elif throttle < 0.0:
		_speed = move_toward(_speed, -REVERSE_SPEED, BRAKING * delta)
	else:
		_speed = move_toward(_speed, 0.0, BRAKING * delta)

	# Turning scales with how fast the bike is rolling, so it carves an arc
	# instead of pivoting in place, and reverses when backing up.
	if absf(_speed) > 0.05:
		var speed_ratio: float = clampf(_speed / SPEED, -1.0, 1.0)
		rotation.y += steer * TURN_RATE * speed_ratio * delta

## Keeps the rider glued to the saddle, matching the bike's heading.
func _carry_rider() -> void:
	rider.global_position = get_seat_position()
	rider.velocity = Vector3.ZERO
	if rider.has_method("face_direction"):
		rider.face_direction(-global_transform.basis.z)
	# The rider leans with the frame and pedals at the crank's rate.
	if rider.has_method("apply_riding_pose"):
		rider.apply_riding_pose(_pedal_phase)
	if rider.character_model:
		rider.character_model.rotation.z = _lean

## World position the rider's origin is placed at, anchored to the model so it
## tracks the bike's visuals rather than its collision origin.
func get_seat_position() -> Vector3:
	var base: Vector3 = _model.global_position if _model else global_position
	return base + global_transform.basis * SEAT_OFFSET_FROM_MODEL

func get_speed() -> float:
	return _speed
