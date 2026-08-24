extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 4.5

## How fast the visual model turns to face its movement direction (radians/sec-ish, via lerp_angle factor).
const MODEL_ROTATION_SPEED := 10.0

## Mouse-look sensitivity in radians per pixel of mouse motion. Tune this to taste.
const MOUSE_SENSITIVITY := 0.003
## Camera pitch clamp. Positive = looking up, negative = looking down (Godot's
## rotation.x convention for a node whose forward is -Z). Down range is wider
## than up range, matching the common third-person "see more ground" clamp.
const PITCH_MIN := deg_to_rad(-70.0) # how far down the camera can look
const PITCH_MAX := deg_to_rad(40.0) # how far up the camera can look
const PITCH_DEFAULT := deg_to_rad(-15.0) # initial look-slightly-down angle

const CHARACTER_MODEL := "res://assets/characters/character_model.glb"
## Feet-to-origin offset: the capsule collision (radius 0.4, height 1.8) is
## centered on the Player's origin, so its bottom sits 0.9 below it. The
## character model's root is at its feet, so it's offset down to match.
const MODEL_FEET_OFFSET := -0.9
## The source model's own front faces local +Z, the opposite of Godot's -Z
## forward convention (confirmed via its skeleton rest pose: "LeftArm" sits
## on +X, which only matches a +Z-facing rig). This constant rotation gets
## added on top of the model's movement-facing yaw to correct for it.
const MODEL_FRONT_CORRECTION := PI

## Max raycast distance for Shift-drag object picking.
const DRAG_RAY_LENGTH := 100.0

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var character_model: Node3D

## True while Shift is held (mouse released, left-click drags objects
## instead of driving camera look).
var shift_held := false
## True after Escape releases the mouse outside of Shift mode; the next
## click just re-captures it rather than starting a drag.
var escaped := false
var dragged_body: RigidBody3D = null
var drag_plane_y := 0.0
## Latest mouse position while dragging. Only _physics_process actually
## writes dragged_body's position (see _update_drag) - _unhandled_input just
## records where the mouse is, so the RigidBody3D's transform is only ever
## touched from the same loop the physics engine itself steps on. Setting it
## straight from input events (which fire asynchronously, not on the physics
## tick) fights the physics server's own per-step handling of the frozen
## body and is what caused the drag to stutter.
var _drag_mouse_pos := Vector2.ZERO

@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var camera: Camera3D = $CameraYaw/CameraPitch/Camera3D

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera_pitch.rotation.x = PITCH_DEFAULT
	call_deferred("_spawn_character_model")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not shift_held:
		escaped = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventKey and not event.echo and event.keycode == KEY_SHIFT:
		_set_shift_held(event.pressed)
		return

	if escaped:
		if event is InputEventMouseButton and event.pressed:
			escaped = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if shift_held:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_start_drag(event.position)
			else:
				_stop_drag()
		elif event is InputEventMouseMotion and dragged_body:
			_drag_mouse_pos = event.position
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look_delta(event.relative)

## Pure rotation math for mouse-look, split out from _unhandled_input so it
## can be exercised directly (the mouse_mode gate above is untestable
## headless, since there's no real display server to capture).
func _apply_look_delta(relative: Vector2) -> void:
	camera_yaw.rotation.y -= relative.x * MOUSE_SENSITIVITY
	camera_pitch.rotation.x = clamp(
		camera_pitch.rotation.x - relative.y * MOUSE_SENSITIVITY,
		PITCH_MIN,
		PITCH_MAX
	)

func _set_shift_held(pressed: bool) -> void:
	if pressed == shift_held:
		return
	shift_held = pressed
	if escaped:
		return
	if shift_held:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_stop_drag()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Raycasts from the camera through the given viewport position and, if it
## hits a RigidBody3D in the "draggable" group, grabs it: freezes its
## physics and remembers the horizontal plane (at the object's current
## height) it will be dragged along.
func _try_start_drag(mouse_pos: Vector2) -> void:
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * DRAG_RAY_LENGTH
	# Exclude the player's own collision body: the camera orbits close to (and
	# sometimes behind/through) it, so an unfiltered ray can hit the player's
	# capsule before it ever reaches the object being aimed at.
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid()])
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider = result["collider"]
	if not (collider is RigidBody3D) or not collider.is_in_group("draggable"):
		return
	dragged_body = collider
	drag_plane_y = dragged_body.global_position.y
	dragged_body.freeze = true
	_drag_mouse_pos = mouse_pos

## Moves the currently dragged body to wherever the camera ray now crosses
## the drag plane, so it tracks the mouse cursor.
func _update_drag(mouse_pos: Vector2) -> void:
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.0001:
		return
	var t := (drag_plane_y - from.y) / dir.y
	if t < 0.0:
		return
	var target := from + dir * t
	target.y = drag_plane_y
	dragged_body.global_position = target

func _stop_drag() -> void:
	if dragged_body:
		dragged_body.freeze = false
		dragged_body = null

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Movement is relative to where the camera is looking horizontally (yaw
	# only - pitch is ignored so moving forward never sends the player into
	# the ground or the sky).
	var direction := (camera_yaw.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	_update_model_facing(direction, delta)
	_update_animation()

	if dragged_body:
		_update_drag(_drag_mouse_pos)

func _update_model_facing(direction: Vector3, delta: float) -> void:
	if not character_model or direction == Vector3.ZERO:
		return
	var target_yaw := atan2(-direction.x, -direction.z) + MODEL_FRONT_CORRECTION
	character_model.rotation.y = lerp_angle(character_model.rotation.y, target_yaw, delta * MODEL_ROTATION_SPEED)

func _spawn_character_model() -> void:
	var packed: PackedScene = load(CHARACTER_MODEL)
	var instance := packed.instantiate()
	instance.name = "CharacterModel"
	instance.transform.origin.y = MODEL_FEET_OFFSET
	instance.rotation.y = MODEL_FRONT_CORRECTION
	add_child(instance)
	character_model = instance

	skeleton = CharacterRig.find_skeleton(instance)
	if not skeleton:
		push_warning("Player: no Skeleton3D found in character model")
		return

	_apply_skin(skeleton)

	animation_player = CharacterRig.build_animation_player(skeleton)
	# AnimationPlayer must be a sibling of the Skeleton3D (not its child): its
	# default root_node is its own parent, and bone tracks are written as
	# "Skeleton3D:BoneName" paths relative to that root.
	skeleton.get_parent().add_child(animation_player)
	animation_player.play("idle")

func _apply_skin(skel: Skeleton3D) -> void:
	var mesh_instance := _find_mesh_instance(skel)
	if not mesh_instance:
		push_warning("Player: no MeshInstance3D found in character model")
		return
	var skin_texture: Texture2D = load(GameState.selected_character)
	if not skin_texture:
		push_warning("Player: could not load skin texture %s" % GameState.selected_character)
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = skin_texture
	mesh_instance.material_override = material

func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh_instance(c)
		if r:
			return r
	return null

func _update_animation() -> void:
	if not animation_player:
		return
	var next_animation: String
	if not is_on_floor():
		next_animation = "jump"
	elif Vector2(velocity.x, velocity.z).length() > 0.1:
		next_animation = "run"
	else:
		next_animation = "idle"
	if animation_player.current_animation != next_animation:
		animation_player.play(next_animation, 0.1)
