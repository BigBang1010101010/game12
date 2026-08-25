extends Node
class_name GiftShop

## A place in the world where gifts can be bought, built on the proximity
## interaction that already exists.
##
## Attach next to an Interactable (sibling or child) exactly like
## ActivitySpot. The shop itself sells nothing on its own: it publishes
## whether the player is standing in one, and FamilyRelationship refuses a
## purchase when nobody is. That split keeps the world node free of family
## logic and the family system free of scene lookups.

## Every shop the player is currently inside. Static so any system can ask
## without holding a reference to the map.
static var _en_rango: Array[GiftShop] = []

## Emitted when the player interacts inside this shop, for whatever UI ends up
## presenting the shelves.
signal tienda_abierta(regalos: Array)

@export var texto_prompt: String = "Presiona E para ver la tienda de regalos"

var _interactable: Interactable = null

## True when the player is standing in any gift shop.
static func hay_tienda_cerca() -> bool:
	for tienda in _en_rango:
		if is_instance_valid(tienda):
			return true
	return false

## Used by tests and by any future non-physical shop (an online order, a call
## home) to open and close the same gate the world node opens.
static func registrar_disponibilidad(tienda: GiftShop, disponible: bool) -> void:
	if disponible:
		if not _en_rango.has(tienda):
			_en_rango.append(tienda)
	else:
		_en_rango.erase(tienda)

func _ready() -> void:
	_interactable = _buscar_interactable()
	if not _interactable:
		push_warning("GiftShop en '%s': no encontro un Interactable hermano o hijo" % get_path())
		return
	_interactable.prompt_text = texto_prompt
	_interactable.interacted.connect(_on_interacted)
	# The Interactable already tracks the player entering and leaving; this
	# mirrors that into the static list rather than duplicating the detection.
	_interactable.body_entered.connect(func(cuerpo: Node3D):
		if cuerpo.is_in_group("player"):
			registrar_disponibilidad(self, true))
	_interactable.body_exited.connect(func(cuerpo: Node3D):
		if cuerpo.is_in_group("player"):
			registrar_disponibilidad(self, false))

func _exit_tree() -> void:
	registrar_disponibilidad(self, false)

func _on_interacted() -> void:
	tienda_abierta.emit(GiftRegistry.obtener_por_nivel())

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
