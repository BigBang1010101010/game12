extends ResourceRegistry

## Autoload registry of every GiftData in data/gifts/.

func _init() -> void:
	directorio = "res://data/gifts"
	clase_esperada = "GiftData"

## Gifts from cheapest tier to most meaningful, so a shop can lay out its
## shelves without naming a single one.
func obtener_por_nivel() -> Array[Resource]:
	var salida: Array[Resource] = obtener_todos()
	salida.sort_custom(func(a, b): return (a as GiftData).nivel < (b as GiftData).nivel)
	return salida
