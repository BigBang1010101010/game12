extends Node

## Autoload holding what the player carries. Kept separate from the UI so
## items can be added, removed or queried by any system without touching the
## menu, and so the menu can be rebuilt without touching the item data.
##
## An item is a Dictionary so new fields can be added without breaking
## existing ones:
##   id:    unique string key
##   name:  label shown in the menu
##   kind:  what using it does; the UI dispatches on this
##   data:  free-form per-item state (the notebook keeps its text here)

signal items_changed

const KIND_NOTEBOOK := "notebook"

var items: Array[Dictionary] = []

func _ready() -> void:
	# Starting inventory. Only the notebook for now; more items are added by
	# calling add_item, not by extending this line.
	add_item({
		"id": "notebook",
		"name": "Libreta",
		"kind": KIND_NOTEBOOK,
		# Notes live here for the session. Not written to disk yet.
		"data": {"text": ""},
	})

func add_item(item: Dictionary) -> void:
	items.append(item)
	items_changed.emit()

func remove_item(id: String) -> void:
	for i in range(items.size()):
		if items[i].get("id", "") == id:
			items.remove_at(i)
			items_changed.emit()
			return

func has_item(id: String) -> bool:
	return get_item(id) != {}

func get_item(id: String) -> Dictionary:
	for item in items:
		if item.get("id", "") == id:
			return item
	return {}

## Convenience for the one item that currently stores anything.
func get_notebook_text() -> String:
	var notebook := get_item("notebook")
	return notebook.get("data", {}).get("text", "") if notebook else ""

func set_notebook_text(text: String) -> void:
	var notebook := get_item("notebook")
	if notebook:
		notebook["data"]["text"] = text
