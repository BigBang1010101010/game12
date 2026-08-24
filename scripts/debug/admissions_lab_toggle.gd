extends CanvasLayer

## Autoload that opens the calibration lab with F1 in any scene. Kept separate
## from the lab itself so the tool can also be opened directly as a scene.

const ESCENA := "res://scenes/debug/admissions_lab.tscn"

var _instancia: Control = null

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.pressed and not evento.echo and evento.keycode == KEY_F1:
		alternar()
		get_viewport().set_input_as_handled()

func alternar() -> void:
	if _instancia:
		_instancia.queue_free()
		_instancia = null
		# The lab needs the cursor; hand control back to the game on close.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_tree().paused = false
		return
	var escena: PackedScene = load(ESCENA)
	if not escena:
		push_error("AdmissionsLab: no se pudo cargar %s" % ESCENA)
		return
	_instancia = escena.instantiate()
	add_child(_instancia)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
