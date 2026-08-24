extends ResourceRegistry

## Autoload registry of every ActivityData in data/activities/.
##
## Identical directory scan to every other registry - the whole point is that
## this file never grows when activities do. What it adds is a cross-reference
## pass: an activity that grants a nonexistent attribute, or claims affinity
## with a career that was never created, is a content bug that must be loud at
## startup rather than a silent zero years later.

func _init() -> void:
	directorio = "res://data/activities"
	clase_esperada = "ActivityData"

func recargar() -> void:
	super()
	_validar_referencias()

func _validar_referencias() -> void:
	for actividad_res in obtener_todos():
		var actividad: ActivityData = actividad_res
		for nivel in actividad.obtener_niveles():
			for atributo_id in nivel.modificadores_atributo:
				if not AttributeRegistry.tiene(atributo_id):
					_fallar("actividad '%s', nivel '%s': atributo inexistente '%s'" % [
						actividad.id, nivel.nombre, atributo_id])
		for carrera_id in actividad.carreras_afinidad:
			if not CareerRegistry.tiene(carrera_id):
				_fallar("actividad '%s': carrera inexistente '%s' en carreras_afinidad" % [
					actividad.id, carrera_id])

## Activities in one category, discovered from the data rather than declared.
func obtener_por_categoria(categoria: StringName) -> Array[Resource]:
	var salida: Array[Resource] = []
	for actividad_res in obtener_todos():
		if (actividad_res as ActivityData).categoria == categoria:
			salida.append(actividad_res)
	return salida

## Every category that actually exists, sorted, for UI grouping.
func obtener_categorias() -> Array[StringName]:
	var vistas: Array[StringName] = []
	for actividad_res in obtener_todos():
		var categoria: StringName = (actividad_res as ActivityData).categoria
		if not vistas.has(categoria):
			vistas.append(categoria)
	# StringName does NOT compare lexicographically in Godot 4 (it compares by
	# internal pointer), so sorting them directly gives a stable but arbitrary
	# order. Comparing as Strings is what actually reads alphabetically.
	vistas.sort_custom(func(a, b): return String(a) < String(b))
	return vistas

## Activities whose unlock conditions hold right now.
func obtener_disponibles(contexto: Dictionary = {}) -> Array[Resource]:
	var salida: Array[Resource] = []
	for actividad_res in obtener_todos():
		if RequirementChecker.cumple_todos((actividad_res as ActivityData).requisitos_desbloqueo, contexto):
			salida.append(actividad_res)
	return salida

func esta_disponible(actividad_id: StringName, contexto: Dictionary = {}) -> bool:
	var actividad: ActivityData = obtener(actividad_id)
	if not actividad:
		return false
	return RequirementChecker.cumple_todos(actividad.requisitos_desbloqueo, contexto)
