extends ResourceRegistry

## Autoload registry of every SportStatCategory in data/sport_stats/.

func _init() -> void:
	directorio = "res://data/sport_stats"
	clase_esperada = "SportStatCategory"

func recargar() -> void:
	super()
	# A statistic has to belong to a sport that exists AND is a sport. Both
	# halves matter: hanging batting average off a chess club would silently
	# produce recognition nobody could earn.
	for categoria_res in obtener_todos():
		var categoria: SportStatCategory = categoria_res
		var actividad: ActivityData = ActivityRegistry.obtener(categoria.deporte_id)
		if not actividad:
			_fallar("estadistica '%s': el deporte '%s' no existe" % [categoria.id, categoria.deporte_id])
		elif not actividad.es_deporte:
			_fallar("estadistica '%s': '%s' existe pero no es un deporte" % [categoria.id, categoria.deporte_id])

## Every statistic of one sport, in its declared order.
func obtener_por_deporte(deporte_id: StringName) -> Array[Resource]:
	var salida: Array[Resource] = []
	for categoria_res in obtener_todos():
		if (categoria_res as SportStatCategory).deporte_id == deporte_id:
			salida.append(categoria_res)
	salida.sort_custom(func(a, b): return (a as SportStatCategory).orden < (b as SportStatCategory).orden)
	return salida

## Sports that actually have statistics, discovered from the data.
func deportes_con_estadisticas() -> Array[StringName]:
	var vistos: Array[StringName] = []
	for categoria_res in obtener_todos():
		var deporte: StringName = (categoria_res as SportStatCategory).deporte_id
		if not vistos.has(deporte):
			vistos.append(deporte)
	vistos.sort_custom(func(a, b): return String(a) < String(b))
	return vistos
