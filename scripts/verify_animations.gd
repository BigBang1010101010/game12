extends SceneTree

## Standalone headless check for the character animation pipeline. Run this
## before pushing ANY change that touches the Player, character_model.glb,
## character_rig.gd, or the animation clips - this class of bug (animations
## silently failing to resolve, leaving the model stuck near its raw import
## rest pose / T-pose) has happened twice already and is invisible from the
## Godot console (no errors are printed when it happens).
##
## Run it with:
##   godot --headless --script scripts/verify_animations.gd
## (run `godot --headless --editor --quit` once first on a fresh checkout,
## so the .glb assets are imported - a plain --headless run skips import.)
##
## Exit code is 0 if every check passes, 1 if anything fails - the failure
## reason is also printed. This checks the actual retargeted output (via
## real linear-blend-skinning bone math), not just "no console errors".

const MODEL_SCALE := 0.465 * 1.18 # keep in sync with player.gd's MODEL_SCALE
# A moving bone's AVERAGE angle-from-rest across the whole clip should clear
# this. Average (not peak) is what catches "stuck near rest the whole time"
# (idle/jump's original bug: avg ~5 degrees) without flagging a legitimately
# oscillating bone that briefly swings back near its own reference point
# once or twice per cycle (run's leg/arm swing does this naturally - a
# peak-then-never-dips-below check flags that too, which measurement showed
# is just normal cyclic motion, not the T-pose bug).
const AVG_ANGLE_THRESHOLD_DEG := 15.0
const CLIPS_AND_MOVED_BONES := {
	"idle": ["LeftArm", "RightArm"],
	"run": ["LeftArm", "RightArm", "LeftUpLeg"],
	"jump": ["LeftArm", "RightArm"],
}

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://assets/characters/character_model.glb")
	if not packed:
		_fail("could not load character_model.glb")
		_finish()
		return
	var instance := packed.instantiate()
	instance.scale = Vector3.ONE * MODEL_SCALE
	root.add_child(instance)
	await process_frame

	var skeleton := CharacterRig.find_skeleton(instance)
	if not skeleton:
		_fail("no Skeleton3D found in character_model.glb")
		_finish()
		return

	var animation_player := CharacterRig.build_animation_player(skeleton)
	skeleton.get_parent().add_child(animation_player)

	# Structural check: this exact bug (bone tracks silently failing to
	# resolve) has happened before because AnimationPlayer ended up as a
	# CHILD of Skeleton3D instead of a SIBLING - its default root_node is
	# "..", so bone tracks like "Skeleton3D:BoneName" only resolve when
	# Skeleton3D is really its sibling.
	if animation_player.get_parent() != skeleton.get_parent():
		_fail("AnimationPlayer is not a sibling of Skeleton3D (parent=%s, skeleton's parent=%s) - bone tracks will not resolve" % [
			animation_player.get_parent(), skeleton.get_parent()
		])

	for clip_name in CLIPS_AND_MOVED_BONES:
		var anim: Animation = animation_player.get_animation_library("").get_animation(clip_name)
		if not anim:
			_fail("animation '%s' missing from the built AnimationPlayer" % clip_name)
			continue
		await _check_clip(clip_name, anim, animation_player, skeleton)

	_finish()

func _check_clip(clip_name: String, anim: Animation, animation_player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var bones_to_check: Array = CLIPS_AND_MOVED_BONES[clip_name]
	var angle_sum := {}
	var angle_min := {}
	var angle_max := {}
	for b in bones_to_check:
		angle_sum[b] = 0.0
		angle_min[b] = INF
		angle_max[b] = 0.0

	animation_player.play(clip_name)
	var samples := 40
	for si in range(samples):
		var t: float = anim.length * float(si) / float(samples)
		animation_player.seek(t, true)
		await process_frame
		for b in bones_to_check:
			var bidx := skeleton.find_bone(b)
			if bidx < 0:
				continue
			var rest: Transform3D = skeleton.get_bone_global_rest(bidx)
			var pose: Transform3D = skeleton.get_bone_global_pose(bidx)
			var delta := pose * rest.affine_inverse()
			var angle_deg: float = rad_to_deg(delta.basis.get_rotation_quaternion().get_angle())
			angle_sum[b] += angle_deg
			angle_min[b] = min(angle_min[b], angle_deg)
			angle_max[b] = max(angle_max[b], angle_deg)

	for b in bones_to_check:
		var avg: float = angle_sum[b] / samples
		if avg < AVG_ANGLE_THRESHOLD_DEG:
			_fail("%s: bone '%s' averages only %.2f degrees of rotation from rest across the whole clip (range [%.2f, %.2f]) - looks stuck near rest/T-pose" % [
				clip_name, b, avg, angle_min[b], angle_max[b]
			])
		else:
			print("OK %s: bone '%s' averages %.2f degrees, range [%.2f, %.2f] - moving, not stuck near rest" % [
				clip_name, b, avg, angle_min[b], angle_max[b]
			])

func _fail(msg: String) -> void:
	_failures.append(msg)
	print("FAIL: %s" % msg)

func _finish() -> void:
	if _failures.is_empty():
		print("PASS: animation retargeting looks correct (%d clips checked)" % CLIPS_AND_MOVED_BONES.size())
		quit(0)
	else:
		print("FAILED: %d issue(s) found - see FAIL lines above" % _failures.size())
		quit(1)
