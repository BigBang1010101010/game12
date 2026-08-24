extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 4.5

## Sprint multiplier on SPEED while the sprint key is held, the player is
## moving, and stamina allows it. Sprint is bound to Left Ctrl (and Q as a
## browser-safe alternative) rather than Shift, which the camera rig already
## uses for object dragging.
const SPRINT_MULTIPLIER := 1.6
## The model has no dedicated sprint clip, so sprinting reuses "run" played
## faster. Applied through AnimationPlayer.speed_scale rather than by
## re-calling play(), because play() restarts the clip from frame 0 and would
## make the legs stutter every time sprint is tapped.
const SPRINT_ANIM_SPEED := 1.35

## True while the player is actually sprinting (not merely holding the key).
var is_sprinting := false

## Set to the vehicle being ridden (see scripts/bicycle.gd) while mounted.
## While non-null the player stops driving itself: the vehicle positions it
## and the normal movement/animation path is skipped.
var mounted_vehicle: Node3D = null

## How fast the visual model turns to face its movement direction (radians/sec-ish, via lerp_angle factor).
const MODEL_ROTATION_SPEED := 10.0

## Quaternius "Male_Casual" (CC0, see assets/characters/CREDITS.txt) - ships
## with its own Skeleton3D and a native AnimationPlayer whose animations were
## authored for that same skeleton, so there is no cross-rig retargeting
## anywhere in this pipeline (the source of every earlier T-pose/broken-pose
## bug in this project).
const CHARACTER_MODEL := "res://assets/characters/character.fbx"
## Measured directly: the imported model's
## world-space bounding box, before any scale of ours, is 4.841251 units
## tall feet-to-hair-top (its FBX ancestor bakes in a 100x cm->m unit scale,
## same quirk as the previous model). Scaled down to a 1.8-unit-tall human,
## matching the existing collision capsule (radius 0.4, height 1.8) and
## camera rig, both otherwise untouched.
const MODEL_SCALE := 1.8 / 4.841251
## Feet-to-origin offset: the capsule collision (radius 0.4, height 1.8) is
## centered on the Player's origin, so its bottom sits 0.9 below it. The
## character model's own feet sit at ~0 in its local space (measured), so
## it's offset down by the same amount to match.
const MODEL_FEET_OFFSET := -0.9
## This model is authored facing +Z, the opposite of Godot's -Z forward
## convention, so the CharacterModel container node is rotated by PI to turn
## it around. Confirmed by two independent anatomical measurements on its own
## skeleton rest pose (see the toe/arm checks that produced these numbers):
##   - toe direction (Foot.L_end minus Foot.L) = (0.000, -0.032, +0.999):
##     the feet point toward +Z.
##   - UpperArm.L sits at x=+0.467 and UpperArm.R at x=-0.453. For a body
##     facing -Z with +Y up, left = up x forward = -X, so a LEFT arm on the
##     +X side only makes sense for a body facing +Z.
## Without this, the character runs backwards with its face toward the camera.
const MODEL_FRONT_CORRECTION := PI

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var character_model: Node3D

## The camera rig owns its own input handling (scripts/camera_controller.gd);
## the player only reads its yaw to make movement camera-relative.
@onready var camera_yaw: Node3D = $CameraYaw

func _ready() -> void:
	add_to_group("player")
	call_deferred("_spawn_character_model")

## Forward lean of the whole model while riding, on top of the bone pose.
## Riders lean well forward: measured, the handlebar sits 0.89 units ahead of
## the saddle while the arm spans only ~0.55, so an upright torso physically
## cannot reach the bars. Leaning the torso carries the shoulders forward and
## down, which is what closes most of that gap (and is what a real cyclist
## does for the same reason).
const RIDING_LEAN_DEGREES := 24.0

## Riding pose, in degrees of local rotation about each bone's own X axis -
## measured to be the flexion axis for both the leg and the arm chains
## (rotating UpperLeg.L about X swings its knee 0.836 units forward/back in
## the model's frame, while Y and Z mostly splay it sideways).
##
## An earlier attempt concluded this rig could not be posed at all, because
## rotating a bone moved its child by 0.000. That was wrong: the cause was
## the AnimationPlayer still writing bone poses every frame - pause() and
## stop() both leave it doing that (child moved 0.019 and 0.025), and only
## `active = false` actually releases the skeleton (child moved 0.360).
## LowerLeg.L is a real child of UpperLeg.L and Palm.L of LowerArm.L, so both
## chains are ordinary FK. Only Foot.L is a separate IK target, which is why
## the feet do not follow the shins.
const RIDE_HIP_BASE := -52.0      # thigh swung forward toward the pedals
const RIDE_HIP_SWING := 20.0      # pedal cycle amplitude
const RIDE_KNEE_BASE := 58.0      # knee bent
const RIDE_KNEE_SWING := 26.0
const RIDE_SHOULDER := -80.0      # arms swung down-forward toward the bars
const RIDE_ELBOW := 24.0          # elbows bent, not locked straight

const RIDE_BONES := ["UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R",
	"UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]

## Bone the held item hangs off. Read from the model's own skeleton, where
## the right hand is "Palm.R" (index 23, parented to LowerArm.R).
const HAND_BONE := "Palm.R"

## Where the item sits relative to that bone, in real world units. The
## skeleton's global basis carries a 37.18x scale (the FBX 100x times
## MODEL_SCALE), which a BoneAttachment3D inherits, so the held model is
## divided by that at runtime - reading the live scale rather than hardcoding
## it, so it survives any change to MODEL_SCALE.
const HELD_ITEM_OFFSET := Vector3(0.0, -0.03, -0.06)
const HELD_ITEM_ROTATION := Vector3(0.0, 0.0, 0.0)

## Spot light shone by the flashlight.
const FLASHLIGHT_RANGE := 22.0
const FLASHLIGHT_ANGLE := 26.0
const FLASHLIGHT_ENERGY := 6.0

var hand_attachment: BoneAttachment3D = null
var held_item_node: Node3D = null
var held_item_id := ""
var flashlight: SpotLight3D = null

## The node the rider's hands reach for while mounted, supplied by the
## vehicle (the bike passes its handlebar).
var _handlebar_target: Node3D = null

func set_handlebar_target(node: Node3D) -> void:
	_handlebar_target = node

## Called by a vehicle when the player gets on or off it.
func set_mounted(vehicle: Node3D) -> void:
	mounted_vehicle = vehicle
	if animation_player:
		if vehicle:
			# Fully release the skeleton so the riding pose below survives;
			# pause()/stop() are not enough (see the note above).
			animation_player.active = false
		else:
			animation_player.active = true
			animation_player.play(ANIM_IDLE)
	if not vehicle:
		_handlebar_target = null
	if not vehicle and skeleton:
		for bone_name in RIDE_BONES:
			var idx := skeleton.find_bone(bone_name)
			if idx >= 0:
				skeleton.reset_bone_pose(idx)
	if character_model:
		character_model.rotation.x = deg_to_rad(RIDING_LEAN_DEGREES) if vehicle else 0.0

## Poses the rider on a bike. `pedal_phase` is in radians and advances with
## the vehicle's speed, so the legs pedal faster the faster it goes; the two
## legs are driven half a cycle apart.
func apply_riding_pose(pedal_phase: float) -> void:
	if not skeleton:
		return
	var swing_l: float = sin(pedal_phase)
	var swing_r: float = sin(pedal_phase + PI)
	_set_bone_x("UpperLeg.L", RIDE_HIP_BASE + RIDE_HIP_SWING * swing_l)
	_set_bone_x("UpperLeg.R", RIDE_HIP_BASE + RIDE_HIP_SWING * swing_r)
	# Knees bend most when the thigh is up, so they run a quarter cycle out.
	_set_bone_x("LowerLeg.L", RIDE_KNEE_BASE + RIDE_KNEE_SWING * sin(pedal_phase - PI * 0.5))
	_set_bone_x("LowerLeg.R", RIDE_KNEE_BASE + RIDE_KNEE_SWING * sin(pedal_phase + PI * 0.5))
	# Arms are AIMED at the handlebar rather than set to a fixed angle.
	# Rotating the shoulder about a single axis cannot reach it: measured, X
	# only raises the hand (at -80 degrees it still sat at z=+0.59 while the
	# bar is at z=-0.42), because the arm's swing plane under that axis is not
	# the sagittal one. Aiming solves it directly and keeps working if the
	# seat or the bike changes.
	if _handlebar_target:
		_aim_bone_at("UpperArm.L", "LowerArm.L", _handlebar_target.global_position)
		_aim_bone_at("UpperArm.R", "LowerArm.R", _handlebar_target.global_position)
		_aim_bone_at("LowerArm.L", "Palm.L", _handlebar_target.global_position)
		_aim_bone_at("LowerArm.R", "Palm.R", _handlebar_target.global_position)
	else:
		_set_bone_x("UpperArm.L", RIDE_SHOULDER)
		_set_bone_x("UpperArm.R", RIDE_SHOULDER)
		_set_bone_x("LowerArm.L", RIDE_ELBOW)
		_set_bone_x("LowerArm.R", RIDE_ELBOW)

## Rotates `bone` so the segment running to `child` points at a world-space
## target. Same shortest-arc aiming used elsewhere in this project: it works
## on real 3D directions instead of guessing an axis, so it does not care how
## the rig's bone bases happen to be oriented.
##
## Everything is read from the bone's CURRENT posed transform, not its rest
## pose, and the skeleton is force-updated first. That matters for a chain:
## aiming the forearm off rest positions ignores where the upper arm just put
## the elbow, and the errors compound (measured: hand ended up further from
## the bar, 1.45, than with a fixed angle).
func _aim_bone_at(bone_name: String, child_name: String, target_world: Vector3) -> void:
	var b := skeleton.find_bone(bone_name)
	var c := skeleton.find_bone(child_name)
	if b < 0 or c < 0:
		return
	skeleton.force_update_all_bone_transforms()
	var b_pose: Transform3D = skeleton.get_bone_global_pose(b)
	var c_pose: Transform3D = skeleton.get_bone_global_pose(c)
	var from_dir: Vector3 = (c_pose.origin - b_pose.origin).normalized()
	# Bone poses are in the skeleton's own space, so the target comes into
	# that space before any directions are compared.
	var target_local: Vector3 = skeleton.global_transform.affine_inverse() * target_world
	var to_dir: Vector3 = (target_local - b_pose.origin).normalized()
	if from_dir.is_zero_approx() or to_dir.is_zero_approx():
		return
	var new_global: Quaternion = Quaternion(from_dir, to_dir) * b_pose.basis.get_rotation_quaternion()
	var parent := skeleton.get_bone_parent(b)
	var parent_rot := Quaternion.IDENTITY
	if parent >= 0:
		parent_rot = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(b, parent_rot.inverse() * new_global)

func _set_bone_x(bone_name: String, degrees: float) -> void:
	var idx := skeleton.find_bone(bone_name)
	if idx < 0:
		return
	var rest: Quaternion = skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(idx, rest * Quaternion(Vector3(1, 0, 0), deg_to_rad(degrees)))

## Lets a vehicle point the rider the way it is heading.
func face_direction(direction: Vector3) -> void:
	if not character_model or direction == Vector3.ZERO:
		return
	character_model.rotation.y = atan2(-direction.x, -direction.z) + MODEL_FRONT_CORRECTION

func _physics_process(delta: float) -> void:
	# While riding, the vehicle owns movement and posture entirely.
	if mounted_vehicle:
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Movement is relative to where the camera is looking horizontally (yaw
	# only - pitch is ignored so moving forward never sends the player into
	# the ground or the sky).
	var direction := (camera_yaw.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Sprinting needs all three: the key held, actual movement input, and
	# enough stamina. Holding the key while standing still neither speeds
	# anything up nor drains anything.
	is_sprinting = Input.is_action_pressed("sprint") and direction != Vector3.ZERO and PlayerStats.can_sprint()
	PlayerStats.tick_stamina(delta, is_sprinting)

	var speed: float = SPEED * (SPRINT_MULTIPLIER if is_sprinting else 1.0)
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
	_update_model_facing(direction, delta)
	_update_animation()

func _update_model_facing(direction: Vector3, delta: float) -> void:
	if not character_model or direction == Vector3.ZERO:
		return
	var target_yaw := atan2(-direction.x, -direction.z) + MODEL_FRONT_CORRECTION
	character_model.rotation.y = lerp_angle(character_model.rotation.y, target_yaw, delta * MODEL_ROTATION_SPEED)

## The model's own animation names, as authored (library-qualified with the
## armature name, e.g. "HumanArmature|Man_Idle" - that's the literal string
## AnimationPlayer.play() needs, not something to strip).
const ANIM_IDLE := "HumanArmature|Man_Idle"
const ANIM_RUN := "HumanArmature|Man_Run"
const ANIM_JUMP := "HumanArmature|Man_Jump"

## Playback speed for the jump clip only, so its arc lands with the character
## instead of still winding up on touchdown. The clip is authored 1.0417s
## long but a jump is only airborne for 2*JUMP_VELOCITY/gravity =
## 2*4.5/9.8 = 0.918s (measured empirically at 0.933s - 56 physics frames -
## the small excess being the tick the landing is detected on), so the clip
## needs to run ~1.12x faster. Derived at spawn instead of hardcoded so it
## stays correct if JUMP_VELOCITY, gravity, or the clip itself changes.
var jump_anim_speed := 1.0

func _spawn_character_model() -> void:
	var packed: PackedScene = load(CHARACTER_MODEL)
	var instance := packed.instantiate()
	instance.name = "CharacterModel"
	instance.transform.origin.y = MODEL_FEET_OFFSET
	instance.rotation.y = MODEL_FRONT_CORRECTION
	instance.scale = Vector3.ONE * MODEL_SCALE
	add_child(instance)
	character_model = instance

	skeleton = instance.find_child("Skeleton3D", true, false)
	if not skeleton:
		push_warning("Player: no Skeleton3D found in character model")

	# The model ships with its own AnimationPlayer, already wired to this
	# same Skeleton3D by the original author - used directly, with no
	# retargeting step of any kind.
	animation_player = instance.find_child("AnimationPlayer", true, false)
	if not animation_player:
		push_warning("Player: no AnimationPlayer found in character model")
		return

	var jump_clip: Animation = animation_player.get_animation(ANIM_JUMP)
	if jump_clip:
		# Read gravity from the project setting rather than get_gravity():
		# this runs in a deferred call before the body's first physics step,
		# and get_gravity() still returns 0 there (measured), which would
		# divide out to a speed of 0 and freeze the jump clip entirely.
		var gravity: float = absf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)))
		var air_time: float = 2.0 * JUMP_VELOCITY / gravity
		jump_anim_speed = jump_clip.length / air_time

	animation_player.play(ANIM_IDLE)

	_create_hand_attachment()

## One BoneAttachment3D on the hand bone, created once. Anything equipped is
## parented to it, so it follows the hand through every animation rather than
## being repositioned by hand each frame.
func _create_hand_attachment() -> void:
	if not skeleton or hand_attachment:
		return
	if skeleton.find_bone(HAND_BONE) < 0:
		push_warning("Player: no '%s' bone to attach held items to" % HAND_BONE)
		return
	hand_attachment = BoneAttachment3D.new()
	hand_attachment.name = "HandAttachment"
	hand_attachment.bone_name = HAND_BONE
	skeleton.add_child(hand_attachment)

## Shows `item` in the character's hand. Passing an empty dictionary, or an
## item with nothing holdable, clears whatever is held.
func equip_item(item: Dictionary) -> void:
	unequip_item()
	if item.is_empty() or not hand_attachment:
		return
	var kind: String = str(item.get("kind", ""))
	var model := HeldItemBuilder.build(kind)
	if not model:
		return

	held_item_id = str(item.get("id", ""))
	held_item_node = model
	hand_attachment.add_child(model)
	# Undo the skeleton's baked scale so the item is its real size in the world.
	var skel_scale: float = skeleton.global_transform.basis.get_scale().x
	model.scale = Vector3.ONE / maxf(skel_scale, 0.0001)
	model.position = HELD_ITEM_OFFSET / maxf(skel_scale, 0.0001)
	model.rotation = HELD_ITEM_ROTATION

	if kind == Inventory.KIND_FLASHLIGHT:
		flashlight = SpotLight3D.new()
		flashlight.name = "FlashlightBeam"
		flashlight.spot_range = FLASHLIGHT_RANGE
		flashlight.spot_angle = FLASHLIGHT_ANGLE
		flashlight.light_energy = FLASHLIGHT_ENERGY
		flashlight.light_color = Color(1.0, 0.96, 0.85)
		flashlight.shadow_enabled = false
		# Parented to the player, not the bone: its POSITION is snapped to the
		# hand each frame, but its AIM follows where the character is facing.
		# Hanging it off the bone instead would point it along whatever
		# arbitrary axis the rig gave that bone.
		add_child(flashlight)

func unequip_item() -> void:
	held_item_id = ""
	if held_item_node:
		held_item_node.queue_free()
		held_item_node = null
	if flashlight:
		flashlight.queue_free()
		flashlight = null

func is_holding(item_id: String) -> bool:
	return held_item_id == item_id

## Keeps the flashlight beam at the hand and pointed where the character
## looks. Runs in _process (not _physics_process) so it tracks the rendered
## pose rather than lagging a physics tick behind it.
func _process(_delta: float) -> void:
	if not flashlight or not hand_attachment or not character_model:
		return
	flashlight.global_position = hand_attachment.global_position
	var forward: Vector3 = -character_model.global_transform.basis.z
	# The model is built facing +Z and turned by MODEL_FRONT_CORRECTION, so
	# its own -Z is the direction it visually faces.
	if forward.is_zero_approx():
		return
	var aim: Vector3 = flashlight.global_position + forward * 6.0 + Vector3(0, -1.2, 0)
	flashlight.look_at(aim, Vector3.UP)

func _update_animation() -> void:
	if not animation_player:
		return
	var next_animation: String
	if not is_on_floor():
		next_animation = ANIM_JUMP
	elif Vector2(velocity.x, velocity.z).length() > 0.1:
		next_animation = ANIM_RUN
	else:
		next_animation = ANIM_IDLE
	if animation_player.current_animation != next_animation:
		var play_speed: float = jump_anim_speed if next_animation == ANIM_JUMP else 1.0
		animation_player.play(next_animation, 0.1, play_speed)

	# Sprint speeds up the run clip via speed_scale, which multiplies whatever
	# play() set. It is only applied while actually running on the ground, so
	# the jump clip keeps the exact rate task 2 calibrated for it.
	var target_scale: float = SPRINT_ANIM_SPEED if (next_animation == ANIM_RUN and is_sprinting) else 1.0
	if not is_equal_approx(animation_player.speed_scale, target_scale):
		animation_player.speed_scale = target_scale
