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
## Lifts the model so the wheels sit on the ground: 0.950 * MODEL_SCALE.
const MODEL_GROUND_OFFSET := 0.304
## Where to place the rider's origin so they sit ON the saddle rather than
## sunk into it. Derived by measurement, not by assuming the player's origin
## is its hips: with the origin placed exactly at the saddle centre
## (0, 0.872, 0.401) the rider's Hips bone measured 0.191 lower and 0.067
## further forward than the saddle, so the offset is corrected by that much.
## The feet then hover around pedal height instead of dragging on the road.
const SEAT_OFFSET := Vector3(0.0, 1.09, 0.47)

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
const RIDE_CAMERA_DISTANCE := 9.5
const RIDE_CAMERA_HEIGHT := 2.0

var is_mounted := false
var rider: CharacterBody3D = null

var _speed := 0.0
var _model: Node3D = null

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
	_model.position.y = MODEL_GROUND_OFFSET
	add_child(_model)

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

	if is_mounted and rider:
		_carry_rider()

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
	rider.global_position = global_position + global_transform.basis * SEAT_OFFSET
	rider.velocity = Vector3.ZERO
	if rider.has_method("face_direction"):
		rider.face_direction(-global_transform.basis.z)

func get_speed() -> float:
	return _speed
