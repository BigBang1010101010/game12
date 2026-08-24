extends CanvasLayer

## Autoload inventory menu, opened and closed with "I".
##
## Built in code (like InteractionUI) so it works in any scene without wiring
## a scene file. The item list is rendered from Inventory.items, so adding an
## item there makes it appear here with no changes to this script; only
## _use_item needs a new branch when a genuinely new KIND is introduced.
##
## Opening pauses the SceneTree, which stops the player and physics. The
## day/night cycle keeps running because that autoload sets its process_mode
## to ALWAYS.

const PANEL_SIZE := Vector2(560, 380)

var root: Control
var item_list: ItemList
var notebook_panel: Control
var notebook_edit: TextEdit
var hint_label: Label

var is_open := false

func _ready() -> void:
	layer = 20
	# The menu itself must keep processing input while the tree is paused,
	# otherwise it could never be closed again.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_refresh_items()
	Inventory.items_changed.connect(_refresh_items)
	root.visible = false

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = PANEL_SIZE
	panel.pivot_offset = PANEL_SIZE * 0.5
	panel.position = -PANEL_SIZE * 0.5
	root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Inventario"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)

	item_list = ItemList.new()
	# The default ItemList/TextEdit styleboxes are transparent, which lets the
	# 3D scene show through behind the notes and makes them hard to read.
	item_list.add_theme_stylebox_override("panel", _opaque_box())
	item_list.custom_minimum_size = Vector2(180, 0)
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.item_selected.connect(_on_item_selected)
	item_list.item_activated.connect(_on_item_selected)
	body.add_child(item_list)

	notebook_panel = VBoxContainer.new()
	notebook_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notebook_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(notebook_panel)

	var notebook_title := Label.new()
	notebook_title.text = "Notas"
	notebook_panel.add_child(notebook_title)

	notebook_edit = TextEdit.new()
	notebook_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	notebook_edit.placeholder_text = "Escribe tus notas aqui..."
	notebook_edit.add_theme_stylebox_override("normal", _opaque_box())
	notebook_edit.add_theme_stylebox_override("focus", _opaque_box())
	notebook_edit.text_changed.connect(_on_notebook_text_changed)
	notebook_panel.add_child(notebook_edit)
	notebook_panel.visible = false

	hint_label = Label.new()
	hint_label.text = "I para cerrar - selecciona un objeto para usarlo"
	hint_label.modulate = Color(1, 1, 1, 0.65)
	column.add_child(hint_label)

## Solid background so the 3D scene behind the menu does not bleed through
## the item list and the notes field.
func _opaque_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.11, 0.13)
	box.border_color = Color(0.30, 0.32, 0.36)
	box.set_border_width_all(1)
	box.set_content_margin_all(6)
	return box

func _refresh_items() -> void:
	if not item_list:
		return
	item_list.clear()
	for item in Inventory.items:
		item_list.add_item(str(item.get("name", item.get("id", "?"))))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	if is_open:
		return
	is_open = true
	root.visible = true
	_refresh_items()
	# Pause stops the player and the rest of the world; the day/night autoload
	# is PROCESS_MODE_ALWAYS so its clock keeps advancing.
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not is_open:
		return
	is_open = false
	root.visible = false
	notebook_panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_item_selected(index: int) -> void:
	if index < 0 or index >= Inventory.items.size():
		return
	_use_item(Inventory.items[index])

## Dispatch point for using an item. New item kinds get a branch here; the
## rest of the menu needs no changes.
func _use_item(item: Dictionary) -> void:
	match str(item.get("kind", "")):
		Inventory.KIND_NOTEBOOK:
			notebook_panel.visible = true
			notebook_edit.text = Inventory.get_notebook_text()
			notebook_edit.grab_focus()
		_:
			notebook_panel.visible = false

func _on_notebook_text_changed() -> void:
	Inventory.set_notebook_text(notebook_edit.text)
