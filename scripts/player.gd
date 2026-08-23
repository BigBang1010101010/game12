extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 4.5

const CHARACTER_MODEL := "res://assets/characters/character_model.glb"
## Feet-to-origin offset: the capsule collision (radius 0.4, height 1.8) is
## centered on the Player's origin, so its bottom sits 0.9 below it. The
## character model's root is at its feet, so it's offset down to match.
const MODEL_FEET_OFFSET := -0.9

var animation_player: AnimationPlayer
var skeleton: Skeleton3D

func _ready() -> void:
	call_deferred("_spawn_character_model")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	_update_animation()

func _spawn_character_model() -> void:
	var packed: PackedScene = load(CHARACTER_MODEL)
	var instance := packed.instantiate()
	instance.name = "CharacterModel"
	instance.transform.origin.y = MODEL_FEET_OFFSET
	# The source model's own front faces local +Z, the opposite of Godot's
	# -Z forward convention (confirmed via its skeleton rest pose: "LeftArm"
	# sits on +X, which only matches a +Z-facing rig). Rotate it 180 degrees
	# around Y so it faces -Z like the rest of the Player/movement code.
	instance.rotate_y(PI)
	add_child(instance)

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
