extends CanvasLayer

## Autoload that opens the gift shop counter when a shop announces itself.
##
## The world node emits tienda_abierta and this listens; the shop knows nothing
## about the UI, and any future non-physical shop - an online order, a call
## home - opens the same counter by emitting the same signal.

const GUION := preload("res://scripts/ui/gift_shop_ui.gd")

var _instancia: Control = null

func _ready() -> void:
	layer = 44
	process_mode = Node.PROCESS_MODE_ALWAYS

func esta_abierta() -> bool:
	return is_instance_valid(_instancia)

func abrir(_regalos: Array = []) -> void:
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
