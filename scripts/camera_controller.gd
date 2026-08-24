extends Node3D
class_name CameraController

## Third-person orbit camera + mouse modes, deliberately kept OUT of the
## character/player scripts so that reworking the character model, its rig or
## its animations can't break camera control (which has happened before).
##
## Attach to the yaw pivot node (a child of whatever the camera should orbit),
## with this node layout underneath it:
##     CameraYaw   <- this script
##       CameraPitch
##         Camera3D
## Yaw turns this node; pitch turns the child; the Camera3D just sits at a
## fixed local offset behind the pivot.
##
## Modes:
##   - default: mouse captured, motion orbits the camera.
##   - Shift held: cursor released so objects can be dragged with left-click
##     (see _try_start_drag); camera look is suspended meanwhile.
##   - Escape: releases the cursor; the next click re-captures it (and is
##     swallowed, so it doesn't also start a drag).

## Mouse-look sensitivity in radians per pixel of mouse motion.
const MOUSE_SENSITIVITY := 0.003
## Camera pitch clamp, in Godot's rotation.x convention for a -Z-forward
## node: negative looks down, positive looks up.
const PITCH_MIN := deg_to_rad(-40.0)
const PITCH_MAX := deg_to_rad(70.0)
const PITCH_DEFAULT := deg_to_rad(-15.0)

## Max raycast distance for Shift-drag object picking.
const DRAG_RAY_LENGTH := 100.0

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

@onready var camera_pitch: Node3D = $CameraPitch
@onready var camera: Camera3D = $CameraPitch/Camera3D

## The camera's resting local offset, captured at startup so a vehicle can
## push the view back and restore it exactly rather than guessing.
var _base_camera_z := 0.0
var _base_yaw_y := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera_pitch.rotation.x = PITCH_DEFAULT
	_base_camera_z = camera.position.z
	_base_yaw_y = position.y

## Pulls the camera back and up while riding a vehicle, and puts it back
## where it was when getting off. Vehicles call this rather than writing the
## camera's transform themselves.
func set_ride_view(riding: bool, distance: float, height: float) -> void:
	camera.position.z = distance if riding else _base_camera_z
	position.y = height if riding else _base_yaw_y

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
		apply_look_delta(event.relative)

## Pure rotation math for mouse-look, split out from _unhandled_input so it
## can be exercised directly (the mouse_mode gate above is untestable
## headless, since there's no real display server to capture).
func apply_look_delta(relative: Vector2) -> void:
	rotation.y -= relative.x * MOUSE_SENSITIVITY
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
	# Exclude the orbited body (the player) from the ray: the camera orbits
	# close to (and sometimes behind/through) it, so an unfiltered ray can hit
	# the player's capsule before it ever reaches the object being aimed at.
	var exclude: Array[RID] = []
	var owner_body := get_parent()
	if owner_body is CollisionObject3D:
		exclude.append((owner_body as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude)
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

func _physics_process(_delta: float) -> void:
	if dragged_body:
		_update_drag(_drag_mouse_pos)
