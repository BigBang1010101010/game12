extends ResourceRegistry

## Autoload registry of every EssayNarrative in data/essays/.
## Same directory scan as every other registry: adding content is adding a
## .tres, never editing this file.

func _init() -> void:
	directorio = "res://data/essays"
	clase_esperada = "EssayNarrative"

## Narratives whose unlock conditions are all satisfied right now.
## The condition TYPES are the one thing this knows; the conditions themselves
## live in each essay's data, so new essays need no code.
func obtener_desbloqueadas(tiempo_por_actividad: Dictionary = {}, hitos: Array = []) -> Array[Resource]:
	var salida: Array[Resource] = []
	for ensayo in obtener_todos():
		if esta_desbloqueada(ensayo as EssayNarrative, tiempo_por_actividad, hitos):
			salida.append(ensayo)
	return salida

func esta_desbloqueada(ensayo: EssayNarrative, tiempo_por_actividad: Dictionary = {}, hitos: Array = []) -> bool:
	for requisito in ensayo.requisitos_desbloqueo:
		if not _cumple(requisito, tiempo_por_actividad, hitos):
			return false
	return true

## Explains WHY a narrative is locked, for the UI.
func requisitos_faltantes(ensayo: EssayNarrative, tiempo_por_actividad: Dictionary = {}, hitos: Array = []) -> Array[Dictionary]:
	var faltantes: Array[Dictionary] = []
	for requisito in ensayo.requisitos_desbloqueo:
		if not _cumple(requisito, tiempo_por_actividad, hitos):
			faltantes.append(requisito)
	return faltantes

func _cumple(requisito: Dictionary, tiempo_por_actividad: Dictionary, hitos: Array) -> bool:
	match String(requisito.get("tipo", "")):
		"atributo_minimo":
			return PlayerState.obtener_valor(requisito.get("atributo", &"")) >= float(requisito.get("valor", 0.0))
		"tiempo_minimo":
			return float(tiempo_por_actividad.get(requisito.get("actividad", &""), 0.0)) >= float(requisito.get("cantidad", 0.0))
		"hito":
			return hitos.has(requisito.get("hito", &""))
		_:
			push_error("EssayRegistry: tipo de requisito desconocido '%s'" % requisito.get("tipo", ""))
			return false
