extends ResourceRegistry

## Autoload registry of every LocationData in data/locations/.
## Same directory scan as every other registry: a fourth city is a file.

func _init() -> void:
	directorio = "res://data/locations"
	clase_esperada = "LocationData"

## Locations sorted from cheapest to most expensive, which is also easiest to
## hardest. The order comes from the data, so a city added between two others
## lands in the right place with nothing to update.
func obtener_por_dificultad() -> Array[Resource]:
	var salida: Array[Resource] = obtener_todos()
	salida.sort_custom(func(a, b):
		return (a as LocationData).indice_costo_vida < (b as LocationData).indice_costo_vida)
	return salida
