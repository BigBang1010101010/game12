extends StaticBody3D
class_name Bed

## A bed the player sleeps in. Sleeping is gated on being next to one of
## these: SleepController asks the "bed" group whether anybody has the player
## in range, so adding more beds later needs no changes anywhere else.
##
## Built from primitives rather than an imported model - a mattress slab, a
## headboard and four legs - which keeps it in the same blockout style as the
## house it stands in.

const MATTRESS_SIZE := Vector3(1.2, 0.28, 2.1)
const MATTRESS_HEIGHT := 0.5
const HEADBOARD_SIZE := Vector3(1.2, 0.7, 0.12)
const LEG_SIZE := Vector3(0.12, 0.5, 0.12)

const FRAME_COLOR := Color(0.36, 0.24, 0.16)
const MATTRESS_COLOR := Color(0.88, 0.86, 0.80)
const PILLOW_COLOR := Color(0.95, 0.94, 0.92)
const BLANKET_COLOR := Color(0.35, 0.45, 0.62)

@onready var interaction_area: Interactable = $Area3D

func _ready() -> void:
	add_to_group("bed")
	_build()
	if interaction_area:
		interaction_area.interacted.connect(_on_interacted)

func _on_interacted() -> void:
	SleepController.try_sleep()

## True when the player is standing close enough to use this bed.
func is_player_near() -> bool:
	return interaction_area != null and interaction_area.is_player_in_range()

func _build() -> void:
	# Mattress.
	_add_box("Mattress", MATTRESS_SIZE, Vector3(0, MATTRESS_HEIGHT, 0), MATTRESS_COLOR)
	# Blanket over the lower two thirds, slightly proud of the mattress.
	_add_box("Blanket", Vector3(MATTRESS_SIZE.x + 0.04, 0.08, MATTRESS_SIZE.z * 0.62),
		Vector3(0, MATTRESS_HEIGHT + MATTRESS_SIZE.y * 0.5 + 0.02, MATTRESS_SIZE.z * 0.17), BLANKET_COLOR)
	# Pillow at the head end (-Z).
	_add_box("Pillow", Vector3(0.7, 0.12, 0.34),
		Vector3(0, MATTRESS_HEIGHT + MATTRESS_SIZE.y * 0.5 + 0.05, -MATTRESS_SIZE.z * 0.36), PILLOW_COLOR)
	# Headboard.
	_add_box("Headboard", HEADBOARD_SIZE,
		Vector3(0, MATTRESS_HEIGHT + HEADBOARD_SIZE.y * 0.3, -MATTRESS_SIZE.z * 0.5 - HEADBOARD_SIZE.z * 0.5),
		FRAME_COLOR)
	# Legs at the four corners.
	var lx: float = MATTRESS_SIZE.x * 0.5 - LEG_SIZE.x
	var lz: float = MATTRESS_SIZE.z * 0.5 - LEG_SIZE.z
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box("Leg", LEG_SIZE, Vector3(sx * lx, LEG_SIZE.y * 0.5, sz * lz), FRAME_COLOR, false)

	# One collision box covering the bed, so the player can't walk through it.
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(MATTRESS_SIZE.x, MATTRESS_HEIGHT + MATTRESS_SIZE.y, MATTRESS_SIZE.z)
	collision.shape = shape
	collision.position = Vector3(0, (MATTRESS_HEIGHT + MATTRESS_SIZE.y) * 0.5, 0)
	add_child(collision)

func _add_box(name_hint: String, size: Vector3, pos: Vector3, color: Color, _visible := true) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name_hint
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.metallic_specular = 0.1
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = pos
	add_child(mesh_instance)
