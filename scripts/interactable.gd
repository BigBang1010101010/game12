extends Area3D
class_name Interactable

## Generic proximity-interaction component. Attach to an Area3D (sized a
## bit bigger than the object's real collision, as a "detection range")
## and it handles showing/hiding the "press E" prompt and emitting
## `interacted` when the player presses the interact action while in range.
##
## To make an object do something when interacted with, connect to the
## `interacted` signal from a small companion script on the object - see
## scripts/demo_interactable_box.gd for an example. This script itself has
## no object-specific behavior, so it's reusable as-is on any object.

signal interacted

@export var prompt_text: String = "Presiona E para interactuar"

var _player_in_range: Node3D = null

## Whether the player is currently inside this object's range. Read by
## systems that gate an action on proximity without going through the E
## press (the bed does this for sleeping).
func is_player_in_range() -> bool:
	return _player_in_range != null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact"):
		interacted.emit()

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = body
	InteractionUI.show_prompt(prompt_text)

func _on_body_exited(body: Node3D) -> void:
	if body != _player_in_range:
		return
	_player_in_range = null
	InteractionUI.hide_prompt()
