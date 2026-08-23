extends StaticBody3D

## Example of how to use Interactable: this is the only object-specific
## piece - it just decides what "interacted" means for this particular box.

const COLOR_DEFAULT := Color(0.85, 0.45, 0.1)
const COLOR_TOGGLED := Color(0.9, 0.3, 0.9)

@onready var interactable: Interactable = $Area3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var _material: StandardMaterial3D
var _toggled := false

func _ready() -> void:
	interactable.interacted.connect(_on_interacted)
	_material = mesh_instance.get_surface_override_material(0)
	if not _material:
		_material = StandardMaterial3D.new()
		_material.albedo_color = COLOR_DEFAULT
		mesh_instance.set_surface_override_material(0, _material)

func _on_interacted() -> void:
	_toggled = not _toggled
	_material.albedo_color = COLOR_TOGGLED if _toggled else COLOR_DEFAULT
	InteractionUI.show_message("¡Interactuaste!")
