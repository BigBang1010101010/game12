extends RefCounted
class_name CharacterRig

## Builds an AnimationPlayer with "idle", "jump" and "run" animations retargeted
## onto the given Skeleton3D's bones. The clips in assets/characters/animations/
## are exported as a flat transform-node hierarchy (no Skeleton3D of their own,
## since the source animation-only FBX files carry no skin data), so each track's
## target node is remapped by bone name onto skeleton's real bone tracks.

const ANIM_PATHS := {
	"idle": "res://assets/characters/animations/idle.glb",
	"jump": "res://assets/characters/animations/jump.glb",
	"run": "res://assets/characters/animations/run.glb",
}

## idle.glb and jump.glb (measured) keep every arm-chain bone within ~1-8
## degrees of that clip's own frame 0 for their *entire* length - these
## clips just never move the arms, presumably because the source rig's
## idle/jump animator only keyed the torso/hips/head and left the arms at
## whatever pose they were placed in. Since frame 0 of every retargeted
## clip lands on the target skeleton's rest pose by construction (see
## _load_and_retarget's comment), "barely moves from frame 0" here means
## "barely moves from T-pose" - the character's arms visibly stay near
## T-pose for the whole clip, not just a brief moment.
##
## A first attempt at a fix borrowed a fixed pose from run.glb's own
## mid-cycle keyframe (the one clip with real arm-swing data) as a static
## substitute for idle/jump's arms. That was wrong in a way the earlier
## purely-numeric verification missed: a rendered screenshot showed both
## arms bent sharply with hands raised near the head - visually broken,
## just differently from T-pose, because "some arbitrary moment in a
## running swing" isn't a resting pose. (Angle-from-rest was substantial,
## which is all that check measured, so it passed anyway.)
##
## This instead derives a real resting pose geometrically, with no
## borrowed animation data: rotate each upper arm (and forearm, kept
## in line with it) so it points straight down in WORLD space, based on
## the bone's own rest-pose direction vector. Confirmed by rendering an
## actual screenshot of the result (arms hanging naturally at the sides,
## not the borrowed-pose's raised arms) before this was relied on.
const ARM_CHAIN_SIDES := ["Left", "Right"]

static func build_animation_player(skeleton: Skeleton3D) -> AnimationPlayer:
	var bone_names := {}
	for i in skeleton.get_bone_count():
		bone_names[skeleton.get_bone_name(i)] = true

	var static_arms_down := _compute_arms_down_reference(skeleton)
	var run_arm_animated := _compute_run_arm_animated_reference(skeleton)

	var library := AnimationLibrary.new()
	for anim_name in ANIM_PATHS:
		var override := run_arm_animated if anim_name == "run" else static_arms_down
		var anim := _load_and_retarget(ANIM_PATHS[anim_name], bone_names, skeleton, override)
		if anim:
			library.add_animation(anim_name, anim)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", library)
	return player

## Returns bone_name -> LOCAL (parent-relative) rotation Quaternion, for
## LeftArm/RightArm/LeftForeArm/RightForeArm, that makes each upper arm
## (and its forearm, kept straight in line) point straight down in world
## space. get_bone_global_rest()/global_pose() are relative to the
## SKELETON node's own local space, not world space - and this skeleton's
## "Root" ancestor carries an axis-swap rotation from the FBX conversion
## (not just its 100x scale: its basis maps local Y to world -Z and local
## Z to world Y), so "world down" is converted into skeleton-local space
## via skeleton.global_transform before comparing against any rest-pose
## direction vectors, which are already in that same local space.
static func _compute_arms_down_reference(skeleton: Skeleton3D) -> Dictionary:
	var world_to_skel: Basis = skeleton.global_transform.basis.inverse()
	var target_dir: Vector3 = (world_to_skel * Vector3(0, -1, 0)).normalized()

	var result := {}
	for side in ARM_CHAIN_SIDES:
		var arm_idx := skeleton.find_bone(side + "Arm")
		var forearm_idx := skeleton.find_bone(side + "ForeArm")
		var hand_idx := skeleton.find_bone(side + "Hand")
		if arm_idx < 0 or forearm_idx < 0 or hand_idx < 0:
			continue

		var arm_rest: Transform3D = skeleton.get_bone_global_rest(arm_idx)
		var forearm_rest: Transform3D = skeleton.get_bone_global_rest(forearm_idx)
		var hand_rest: Transform3D = skeleton.get_bone_global_rest(hand_idx)
		var arm_dir: Vector3 = (forearm_rest.origin - arm_rest.origin).normalized()
		var forearm_dir: Vector3 = (hand_rest.origin - forearm_rest.origin).normalized()

		var pose := _point_arm_at(skeleton, arm_idx, arm_rest, arm_dir, forearm_rest, forearm_dir, target_dir, target_dir)
		result[side + "Arm"] = pose[0]
		result[side + "ForeArm"] = pose[1]

	return result

## "run" is the one clip with real arm-swing data (measured directly from
## its own raw keyframes: 51-91 degrees of genuine motion, vs. idle/jump's
## 1-8 degrees), so unlike idle/jump it can't just hold a fixed pose - but
## naively retargeting it with the plain delta-quaternion formula (see
## _load_and_retarget) looked visibly wrong once actually rendered: elbows
## bending up toward the head instead of a natural running arm swing, even
## though the numeric rotation *magnitude* matched the source. The
## quaternion delta only corrects for source and target disagreeing on
## what "zero rotation" is - it does NOT correct for source and target
## disagreeing on which axis a bone's local rotation happens around, and
## that mismatch is invisible at idle/jump's few-degree motions but very
## visible at run's 50-90 degree swings.
##
## Fix: resample the SOURCE's own posed arm/forearm/hand positions across
## the whole cycle - letting Godot's normal scene-tree FK do the work via
## the source clip's own embedded AnimationPlayer - and at each sample
## point, use the same world-direction-matching technique as
## _compute_arms_down_reference to compute what LOCAL target rotation
## makes the target bone point the same real-world direction the source's
## bone is *actually* pointing at that moment. This is immune to the
## axis-convention mismatch because it never compares raw quaternions
## between the two rigs - only 3D positions, in a shared world frame.
static func _compute_run_arm_animated_reference(skeleton: Skeleton3D) -> Dictionary:
	var packed: PackedScene = load(ANIM_PATHS["run"])
	var instance := packed.instantiate()
	Engine.get_main_loop().root.add_child(instance)
	var source_player := _find_animation_player(instance)
	var source_anim := _find_real_animation(source_player)
	var result := {}
	if not source_anim:
		instance.queue_free()
		return result

	var rest_dirs := {}
	for side in ARM_CHAIN_SIDES:
		var arm_idx := skeleton.find_bone(side + "Arm")
		var forearm_idx := skeleton.find_bone(side + "ForeArm")
		var hand_idx := skeleton.find_bone(side + "Hand")
		if arm_idx < 0 or forearm_idx < 0 or hand_idx < 0:
			continue
		var arm_rest: Transform3D = skeleton.get_bone_global_rest(arm_idx)
		var forearm_rest: Transform3D = skeleton.get_bone_global_rest(forearm_idx)
		var hand_rest: Transform3D = skeleton.get_bone_global_rest(hand_idx)
		rest_dirs[side] = {
			"arm_idx": arm_idx, "arm_rest": arm_rest, "arm_dir": (forearm_rest.origin - arm_rest.origin).normalized(),
			"forearm_rest": forearm_rest, "forearm_dir": (hand_rest.origin - forearm_rest.origin).normalized(),
		}

	# _point_arm_at expects both the "from" and "to" directions in the same
	# space; arm_dir/forearm_dir above are skeleton-local (from
	# get_bone_global_rest), so the source's world-space directions need
	# the same world->skeleton-local conversion _compute_arms_down_reference
	# uses.
	var world_to_skel: Basis = skeleton.global_transform.basis.inverse()

	var samples := 24
	for side in ARM_CHAIN_SIDES:
		result[side + "Arm"] = {"times": PackedFloat32Array(), "quats": []}
		result[side + "ForeArm"] = {"times": PackedFloat32Array(), "quats": []}

	for si in range(samples + 1):
		var t: float = source_anim.length * float(si) / float(samples)
		source_player.seek(t, true)

		for side in ARM_CHAIN_SIDES:
			var arm_node := instance.find_child(side + "Arm", true, false)
			var forearm_node := instance.find_child(side + "ForeArm", true, false)
			var hand_node := instance.find_child(side + "Hand", true, false)
			if not arm_node or not forearm_node or not hand_node:
				continue
			var arm_world_dir: Vector3 = (forearm_node.global_transform.origin - arm_node.global_transform.origin).normalized()
			var forearm_world_dir: Vector3 = (hand_node.global_transform.origin - forearm_node.global_transform.origin).normalized()
			var arm_target: Vector3 = (world_to_skel * arm_world_dir).normalized()
			var forearm_target: Vector3 = (world_to_skel * forearm_world_dir).normalized()

			var rd: Dictionary = rest_dirs[side]
			var pose := _point_arm_at(
				skeleton, rd["arm_idx"], rd["arm_rest"], rd["arm_dir"], rd["forearm_rest"], rd["forearm_dir"],
				arm_target, forearm_target
			)
			result[side + "Arm"]["times"].append(t)
			result[side + "Arm"]["quats"].append(pose[0])
			result[side + "ForeArm"]["times"].append(t)
			result[side + "ForeArm"]["quats"].append(pose[1])

	instance.queue_free()
	return result

## Shared math for both the static (arms-down) and animated (run) cases:
## given the upper arm's and forearm's own rest-pose direction vectors
## (skeleton-local space) and two TARGET directions to point them at
## (already in skeleton-local space, or world space - see below), returns
## [arm_local_rotation, forearm_local_rotation].
static func _point_arm_at(
	skeleton: Skeleton3D, arm_idx: int, arm_rest: Transform3D, arm_dir: Vector3,
	forearm_rest: Transform3D, forearm_dir: Vector3, arm_target_dir: Vector3, forearm_target_dir: Vector3
) -> Array:
	var arm_correction: Quaternion = Quaternion(arm_dir, arm_target_dir)
	var arm_new_global: Quaternion = arm_correction * arm_rest.basis.get_rotation_quaternion()

	var parent_idx := skeleton.get_bone_parent(arm_idx)
	var parent_rot: Quaternion = skeleton.get_bone_global_rest(parent_idx).basis.get_rotation_quaternion()
	var arm_local: Quaternion = parent_rot.inverse() * arm_new_global

	var forearm_correction: Quaternion = Quaternion(forearm_dir, forearm_target_dir)
	var forearm_new_global: Quaternion = forearm_correction * forearm_rest.basis.get_rotation_quaternion()
	var forearm_local: Quaternion = arm_new_global.inverse() * forearm_new_global

	return [arm_local, forearm_local]

## Rotation tracks store each bone's ABSOLUTE local rotation (relative to its
## parent bone), not a delta. Copying that value verbatim only works if the
## source and target skeletons define the same "zero rotation" (rest pose)
## for a same-named bone. They don't here - the source clip rig's rest pose
## differs from this model's, so raw copies escalate down each kinematic
## chain (confirmed by measurement: the retargeted "idle" clip put the
## Arm/ForeArm/Hand bones at 65-95 degrees off this model's rest, and finger
## bones past 150 degrees, flinging the hands out wide and up above the
## head). The fix is to re-express each keyframe as a delta from the
## SOURCE's own rest rotation, then reapply that same delta on top of the
## TARGET's rest rotation, so both sides agree on what "no rotation" means.
static func _load_and_retarget(path: String, bone_names: Dictionary, skeleton: Skeleton3D, arm_pose_override: Dictionary) -> Animation:
	var packed: PackedScene = load(path)
	if not packed:
		push_warning("CharacterRig: could not load %s" % path)
		return null
	var instance := packed.instantiate()
	var source_player := _find_animation_player(instance)
	var source_anim := _find_real_animation(source_player)
	if not source_anim:
		instance.queue_free()
		return null

	var out := Animation.new()
	out.length = source_anim.length
	out.loop_mode = Animation.LOOP_LINEAR

	for ti in source_anim.get_track_count():
		var track_path := str(source_anim.track_get_path(ti))
		var bone_name := track_path.get_slice(":", 0).get_file()
		if not bone_names.has(bone_name):
			continue
		var ttype := source_anim.track_get_type(ti)
		if ttype != Animation.TYPE_POSITION_3D and ttype != Animation.TYPE_ROTATION_3D and ttype != Animation.TYPE_SCALE_3D:
			continue
		var new_track := out.add_track(ttype)
		out.track_set_path(new_track, NodePath("Skeleton3D:" + bone_name))

		var source_rest_rot := Quaternion.IDENTITY
		var target_rest_rot := Quaternion.IDENTITY
		if ttype == Animation.TYPE_ROTATION_3D:
			var source_node := instance.find_child(bone_name, true, false)
			if source_node:
				source_rest_rot = source_node.transform.basis.get_rotation_quaternion()
			var bidx := skeleton.find_bone(bone_name)
			if bidx >= 0:
				target_rest_rot = skeleton.get_bone_rest(bidx).basis.get_rotation_quaternion()

		var override_value: Variant = arm_pose_override.get(bone_name) if ttype == Animation.TYPE_ROTATION_3D else null

		if override_value is Dictionary:
			# Animated override (run's arm chain): replace this track's
			# keys entirely with the pre-sampled world-direction-matched
			# ones, ignoring the source's own (axis-mismatched) keys.
			var times: PackedFloat32Array = override_value["times"]
			var quats: Array = override_value["quats"]
			for i in range(times.size()):
				out.rotation_track_insert_key(new_track, times[i], quats[i])
			continue

		for ki in source_anim.track_get_key_count(ti):
			var t: float = source_anim.track_get_key_time(ti, ki)
			var v = source_anim.track_get_key_value(ti, ki)
			match ttype:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(new_track, t, v)
				Animation.TYPE_ROTATION_3D:
					var retargeted: Quaternion
					if override_value != null:
						retargeted = override_value
					else:
						var delta: Quaternion = source_rest_rot.inverse() * v
						retargeted = target_rest_rot * delta
					out.rotation_track_insert_key(new_track, t, retargeted)
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(new_track, t, v)

	instance.queue_free()
	return out

static func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r:
			return r
	return null

static func _find_real_animation(player: AnimationPlayer) -> Animation:
	if not player:
		return null
	for lib_name in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if not anim_name.contains("Targeting"):
				return lib.get_animation(anim_name)
	return null

static func find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := find_skeleton(c)
		if r:
			return r
	return null
