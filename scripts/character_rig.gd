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

static func build_animation_player(skeleton: Skeleton3D) -> AnimationPlayer:
	var bone_names := {}
	for i in skeleton.get_bone_count():
		bone_names[skeleton.get_bone_name(i)] = true

	var library := AnimationLibrary.new()
	for anim_name in ANIM_PATHS:
		var anim := _load_and_retarget(ANIM_PATHS[anim_name], bone_names)
		if anim:
			library.add_animation(anim_name, anim)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", library)
	return player

static func _load_and_retarget(path: String, bone_names: Dictionary) -> Animation:
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
		for ki in source_anim.track_get_key_count(ti):
			var t: float = source_anim.track_get_key_time(ti, ki)
			var v = source_anim.track_get_key_value(ti, ki)
			match ttype:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(new_track, t, v)
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(new_track, t, v)
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
