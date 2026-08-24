extends RefCounted
class_name HeldItemBuilder

## Builds the little 3D models that appear in the character's hand when an
## inventory item is equipped. Kept apart from both the inventory data and the
## player so adding a new holdable item is one branch here, not edits spread
## across three scripts.

## Returns a Node3D for `kind`, or null if that kind is not holdable.
static func build(kind: String) -> Node3D:
	match kind:
		Inventory.KIND_FLASHLIGHT:
			return _build_flashlight()
		Inventory.KIND_NOTEBOOK:
			return _build_notebook()
	return null

static func _build_flashlight() -> Node3D:
	var root := Node3D.new()
	root.name = "Flashlight"

	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.032
	body_mesh.bottom_radius = 0.036
	body_mesh.height = 0.17
	body_mesh.material = _material(Color(0.18, 0.19, 0.22), 0.45)
	body.mesh = body_mesh
	# Cylinders stand along Y by default; lay it along -Z so it points the way
	# the light shines.
	body.rotation_degrees.x = 90.0
	root.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.055
	head_mesh.bottom_radius = 0.034
	head_mesh.height = 0.07
	head_mesh.material = _material(Color(0.75, 0.72, 0.55), 0.35)
	head.mesh = head_mesh
	head.rotation_degrees.x = 90.0
	head.position.z = -0.115
	root.add_child(head)

	return root

static func _build_notebook() -> Node3D:
	var root := Node3D.new()
	root.name = "Notebook"

	var cover := MeshInstance3D.new()
	var cover_mesh := BoxMesh.new()
	cover_mesh.size = Vector3(0.16, 0.02, 0.21)
	cover_mesh.material = _material(Color(0.55, 0.18, 0.16), 0.8)
	cover.mesh = cover_mesh
	root.add_child(cover)

	var pages := MeshInstance3D.new()
	var pages_mesh := BoxMesh.new()
	pages_mesh.size = Vector3(0.148, 0.016, 0.198)
	pages_mesh.material = _material(Color(0.94, 0.93, 0.88), 0.9)
	pages.mesh = pages_mesh
	pages.position.y = 0.012
	root.add_child(pages)

	return root

static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic_specular = 0.2
	return material
