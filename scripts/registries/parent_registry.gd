extends ResourceRegistry

## Autoload registry of every ParentData in data/parents/.

func _init() -> void:
	directorio = "res://data/parents"
	clase_esperada = "ParentData"

func recargar() -> void:
	super()
	# Two parents sharing a birthday would make "whose birthday is today"
	# ambiguous for every system that asks, so it is reported at load.
	var vistos: Dictionary = {}
	for padre_res in obtener_todos():
		var padre: ParentData = padre_res
		var dia: int = padre.dia_del_anio()
		if vistos.has(dia):
			_fallar("'%s' y '%s' cumplen anios el mismo dia (%s)" % [
				vistos[dia], padre.id, padre.fecha_cumpleanos])
			continue
		vistos[dia] = padre.id

## Whoever has a birthday on a given day of the year, empty when nobody does.
func quien_cumple(dia_del_anio: int) -> Array[Resource]:
	var salida: Array[Resource] = []
	for padre_res in obtener_todos():
		if (padre_res as ParentData).dia_del_anio() == dia_del_anio:
			salida.append(padre_res)
	return salida
