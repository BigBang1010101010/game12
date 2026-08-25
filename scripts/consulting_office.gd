extends Node
class_name ConsultingOffice

## The consulting firm as a place in the world.
##
## Same shape as the gift shop: a node beside an Interactable, no family or
## money logic of its own. Interacting opens the counter UI, which is built in
## code from the registry so this node never knows what a tier is.

const ESCENA_UI := preload("res://scripts/ui/consulting_ui.gd")

## The open counter, if any. Static so the UI can close itself and a second
## interaction cannot open two.
static var _abierta: CanvasLayer = null

@export var texto_prompt: String = "Presiona E para entrar a la asesoría"

var _interactable: Interactable = null

func _ready() -> void:
	_interactable = _buscar_interactable()
	if not _interactable:
		push_warning("ConsultingOffice en '%s': no encontro un Interactable" % get_path())
		return
	_interactable.prompt_text = texto_prompt
	_interactable.interacted.connect(_on_interacted)

func _on_interacted() -> void:
	if is_instance_valid(_abierta):
		cerrar()
		return
	abrir()

## Opens the counter. Pauses the world and frees the cursor, exactly like the
## other full-screen panels in the project.
static func abrir() -> void:
	if is_instance_valid(_abierta):
		return
	var capa := CanvasLayer.new()
	capa.layer = 40
	capa.process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := Control.new()
	panel.set_script(ESCENA_UI)
	capa.add_child(panel)
	(Engine.get_main_loop() as SceneTree).root.add_child(capa)
	_abierta = capa
	(Engine.get_main_loop() as SceneTree).paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	HUD.ocultar()
	# The "press E" prompt belongs to the world behind the panel.
	InteractionUI.hide_prompt()

static func cerrar() -> void:
	if not is_instance_valid(_abierta):
		return
	_abierta.queue_free()
	_abierta = null
	(Engine.get_main_loop() as SceneTree).paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	HUD.mostrar()

func _exit_tree() -> void:
	if is_instance_valid(_abierta):
		cerrar()

func _buscar_interactable() -> Interactable:
	for hijo in get_children():
		if hijo is Interactable:
			return hijo
	var padre := get_parent()
	if padre:
		for hermano in padre.get_children():
			if hermano is Interactable:
				return hermano
	return null
