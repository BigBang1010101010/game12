extends ResourceRegistry

## Autoload registry of every ConsultingTier in data/consulting/.

func _init() -> void:
	directorio = "res://data/consulting"
	clase_esperada = "ConsultingTier"

## Cheapest first, which is also least precise first.
func obtener_por_nivel() -> Array[Resource]:
	var salida: Array[Resource] = obtener_todos()
	salida.sort_custom(func(a, b): return (a as ConsultingTier).nivel < (b as ConsultingTier).nivel)
	return salida
