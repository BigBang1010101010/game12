extends Node

## Bridges a place in the 3D world to an activity, using the proximity
## interaction that already exists.
##
## Attach it next to an Interactable (as a sibling or a child of the same
## object) and set `actividad_id` in the inspector: pressing E in range then
## credits that activity with hours, exactly as if the player had spent them.
## The activity it feeds is a scene property, never a name written in code, so
## a new spot in the map is a node with a different id in the inspector.
##
## The catalogue's proximity activity today is &"eventos_politicos_mapa" - the
## speeches and rallies the player can walk into - but nothing here knows that.

## Which activity this spot feeds. Must exist in data/activities/.
@export var actividad_id: StringName = &""

## Hours credited per interaction. Small by design: a spot is an event you
## attended, not an afternoon of work.
@export var horas_por_visita: float = 2.0

## When true the spot pays once and then stops, for one-off events.
@export var una_sola_vez: bool = false

## Prompt shown while in range. Left empty, the activity's own display name is
## used, so the world text follows the data.
@export var texto_prompt: String = ""

var _ya_visitado := false
var _interactable: Interactable = null

func _ready() -> void:
	_interactable = _buscar_interactable()
	if not _interactable:
		push_warning("ActivitySpot en '%s': no encontro un Interactable hermano o hijo" % get_path())
		return
	if not ActivityRegistry.tiene(actividad_id):
		push_error("ActivitySpot en '%s': la actividad '%s' no existe" % [get_path(), actividad_id])
		return
	var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
	_interactable.prompt_text = texto_prompt if not texto_prompt.is_empty() else (
		"Presiona E: %s" % actividad.nombre_display)
	_interactable.interacted.connect(_on_interacted)

func _on_interacted() -> void:
	if una_sola_vez and _ya_visitado:
		return
	_ya_visitado = true
	# Straight into the tracker, so a visit is auditable in the ledger like any
	# other hour: same source type, same levels, same continuity multiplier.
	ActivityTracker.invertir_tiempo(actividad_id, horas_por_visita, {"origen": "mapa"})

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
