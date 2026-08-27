extends CanvasLayer

## Autoload that opens the activities and time screen with T, in any scene.
## Same shape as the calibration lab's toggle, minus the debug framing: this
## one is a normal part of the game.

const GUION := preload("res://scripts/ui/activities_ui.gd")

var _instancia: Control = null

func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(evento: InputEvent) -> void:
	if evento.is_action_pressed("toggle_activities"):
		alternar()
		get_viewport().set_input_as_handled()

func esta_abierta() -> bool:
	return is_instance_valid(_instancia)

func alternar() -> void:
	if esta_abierta():
		cerrar()
	else:
		abrir()

func abrir() -> void:
	if esta_abierta():
		return
	_instancia = Control.new()
	_instancia.set_script(GUION)
	add_child(_instancia)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	HUD.ocultar()
	InteractionUI.hide_prompt()

func cerrar() -> void:
	if not esta_abierta():
		return
	_instancia.queue_free()
	_instancia = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	HUD.mostrar()
