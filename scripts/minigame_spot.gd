extends Node
class_name MinigameSpot

## A place in the world that opens a sports minigame.
##
## Same shape as ActivitySpot and GiftShop: it sits next to an Interactable and
## carries only two scene properties - which minigame and which sport. It knows
## nothing about how the game is played or what it records.

## The minigame script to run. Must extend SportMinigame.
@export var minijuego: Script = null
## The sport whose statistics the session will feed.
@export var deporte_id: StringName = &""
@export var texto_prompt: String = ""

var _interactable: Interactable = null

func _ready() -> void:
	_interactable = _buscar_interactable()
	if not _interactable:
		push_warning("MinigameSpot en '%s': no encontro un Interactable" % get_path())
		return
	if not ActivityRegistry.tiene(deporte_id):
		push_error("MinigameSpot en '%s': el deporte '%s' no existe" % [get_path(), deporte_id])
		return
	var actividad: ActivityData = ActivityRegistry.obtener(deporte_id)
	_interactable.prompt_text = texto_prompt if not texto_prompt.is_empty() else (
		"Presiona E para jugar: %s" % actividad.nombre_display)
	_interactable.interacted.connect(_on_interacted)

func _on_interacted() -> void:
	if not minijuego:
		push_error("MinigameSpot en '%s': sin minijuego asignado" % get_path())
		return
	SportMinigame.lanzar(minijuego, deporte_id)

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
