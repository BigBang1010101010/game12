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
## T-pose for the whole clip, not just a brief moment. run.glb is the one
## clip with real arm-swing data (51-91 degrees of genuine motion), so its
## own mid-cycle pose is borrowed as a static substitute for idle/jump's
## arm bones specifically - everything else in idle/jump (spine, hips,
## head, legs) keeps using that clip's own (real, if subtle) keyframes.
const ARM_CHAIN_BONES := ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm"]

static func build_animation_player(skeleton: Skeleton3D) -> AnimationPlayer:
	var bone_names := {}
	for i in skeleton.get_bone_count():
		bone_names[skeleton.get_bone_name(i)] = true

	var arm_pose_override := _compute_run_arm_reference(bone_names, skeleton)

	var library := AnimationLibrary.new()
	for anim_name in ANIM_PATHS:
		var override := arm_pose_override if anim_name != "run" else {}
		var anim := _load_and_retarget(ANIM_PATHS[anim_name], bone_names, skeleton, override)
		if anim:
			library.add_animation(anim_name, anim)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", library)
	return player

## Retargets run.glb's arm-chain bones only, at its own mid-cycle timestamp
## (roughly the midpoint between a forward and backward swing extreme, a
## reasonable stand-in for a neutral arm position), through the same
## delta-from-frame-0 formula _load_and_retarget uses. Returns bone_name ->
## final retargeted Quaternion.
static func _compute_run_arm_reference(bone_names: Dictionary, skeleton: Skeleton3D) -> Dictionary:
	var packed: PackedScene = load(ANIM_PATHS["run"])
	var instance := packed.instantiate()
	var source_player := _find_animation_player(instance)
	var source_anim := _find_real_animation(source_player)
	var result := {}
	if not source_anim:
		instance.queue_free()
		return result

	var mid_time := source_anim.length * 0.5
	for ti in range(source_anim.get_track_count()):
		if source_anim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var track_path := str(source_anim.track_get_path(ti))
		var bone_name := track_path.get_slice(":", 0).get_file()
		if not ARM_CHAIN_BONES.has(bone_name) or not bone_names.has(bone_name):
			continue

		var source_node := instance.find_child(bone_name, true, false)
		if not source_node:
			continue
		var source_rest_rot: Quaternion = source_node.transform.basis.get_rotation_quaternion()
		var bidx := skeleton.find_bone(bone_name)
		if bidx < 0:
			continue
		var target_rest_rot: Quaternion = skeleton.get_bone_rest(bidx).basis.get_rotation_quaternion()

		# Nearest keyframe to the clip's midpoint.
		var best_ki := 0
		var best_dt := INF
		for ki in range(source_anim.track_get_key_count(ti)):
			var t: float = source_anim.track_get_key_time(ti, ki)
			var dt: float = absf(t - mid_time)
			if dt < best_dt:
				best_dt = dt
				best_ki = ki
		var v: Quaternion = source_anim.track_get_key_value(ti, best_ki)
		var delta: Quaternion = source_rest_rot.inverse() * v
		result[bone_name] = target_rest_rot * delta

	instance.queue_free()
	return result

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

		var held_pose: Variant = arm_pose_override.get(bone_name) if ttype == Animation.TYPE_ROTATION_3D else null

		for ki in source_anim.track_get_key_count(ti):
			var t: float = source_anim.track_get_key_time(ti, ki)
			var v = source_anim.track_get_key_value(ti, ki)
			match ttype:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(new_track, t, v)
				Animation.TYPE_ROTATION_3D:
					var retargeted: Quaternion
					if held_pose != null:
						retargeted = held_pose
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
