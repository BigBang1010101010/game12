extends ResourceRegistry

## Autoload registry of every AttributeDefinition in data/attributes/.
## Adding an attribute is adding a .tres there - this file never changes.

func _init() -> void:
	directorio = "res://data/attributes"
	clase_esperada = "AttributeDefinition"

func get_definition(id: StringName) -> AttributeDefinition:
	return obtener(id) as AttributeDefinition

func get_all_ids() -> Array[StringName]:
	return obtener_ids()

func get_all_definitions() -> Array[Resource]:
	return obtener_todos()

func get_by_category(categoria: StringName) -> Array[Resource]:
	var salida: Array[Resource] = []
	for definicion in obtener_todos():
		if (definicion as AttributeDefinition).categoria == categoria:
			salida.append(definicion)
	return salida

## Every category present in the data, discovered rather than declared.
func get_all_categories() -> Array[StringName]:
	var vistas: Array[StringName] = []
	for definicion in obtener_todos():
		var categoria: StringName = (definicion as AttributeDefinition).categoria
		if not vistas.has(categoria):
			vistas.append(categoria)
	return vistas
