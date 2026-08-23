extends RigidBody3D

## Marks this RigidBody3D as pickable by the Shift-drag system in player.gd.
## FREEZE_MODE_KINEMATIC keeps it solid (other bodies still collide with it)
## while player.gd repositions it directly during a drag.

func _ready() -> void:
	add_to_group("draggable")
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
