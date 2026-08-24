extends Node
class_name ResourceRegistry

## Base class for every content registry in the game.
##
## THE POINT OF THIS CLASS: no registry ever lists its content. Each subclass
## says only which directory to scan and which Resource class it expects; the
## scan discovers whatever is there. Adding a university, career, attribute,
## essay or synergy is dropping a .tres into the right folder - no script is
## edited, ever.
##
## Subclasses set `directorio` and `clase_esperada` and may override
## `_id_de(recurso)` if their id property is named differently.

## Directory scanned at startup, e.g. "res://data/attributes".
var directorio: String = ""
## Name of the script class every entry must be, e.g. "AttributeDefinition".
var clase_esperada: String = ""

var _por_id: Dictionary = {}
var _orden: Array[StringName] = []
var _errores: PackedStringArray = PackedStringArray()

func _ready() -> void:
	recargar()

## Rescans the directory from scratch. Safe to call again at runtime, which is
## what makes hot-reloading content during calibration possible.
func recargar() -> void:
	_por_id.clear()
	_orden.clear()
	_errores.clear()

	if directorio.is_empty():
		_fallar("%s: 'directorio' no fue configurado" % get_script().resource_path)
		return

	var dir := DirAccess.open(directorio)
	if not dir:
		_fallar("%s: no se pudo abrir el directorio '%s' (error %d)" % [
			name, directorio, DirAccess.get_open_error()])
		return

	# Sorted so load order is deterministic; two runs must produce the same
	# ordering or anything downstream (UI lists, tests) becomes flaky.
	var archivos := dir.get_files()
	archivos.sort()
	for archivo in archivos:
		# The editor writes .remap files next to resources in exported builds;
		# strip that suffix so exported games find the same set as the editor.
		var nombre := archivo
		if nombre.ends_with(".remap"):
			nombre = nombre.trim_suffix(".remap")
		if not (nombre.ends_with(".tres") or nombre.ends_with(".res")):
			continue
		_cargar_archivo(directorio.path_join(nombre))

	if _por_id.is_empty():
		push_warning("%s: no se cargo ningun recurso desde '%s'" % [name, directorio])

func _cargar_archivo(ruta: String) -> void:
	var recurso: Resource = load(ruta)
	if not recurso:
		_fallar("%s: '%s' no se pudo cargar (archivo malformado o script faltante)" % [name, ruta])
		return
	if not clase_esperada.is_empty() and not _es_de_clase(recurso, clase_esperada):
		_fallar("%s: '%s' no es un %s" % [name, ruta, clase_esperada])
		return

	var problemas: PackedStringArray = recurso.validar() if recurso.has_method("validar") else PackedStringArray()
	if not problemas.is_empty():
		_fallar("%s: '%s' es invalido -> %s" % [name, ruta, ", ".join(problemas)])
		return

	var id: StringName = _id_de(recurso)
	if id == &"":
		_fallar("%s: '%s' no tiene id" % [name, ruta])
		return
	if _por_id.has(id):
		_fallar("%s: id duplicado '%s' entre '%s' y '%s'" % [
			name, id, _por_id[id].resource_path, ruta])
		return

	_por_id[id] = recurso
	_orden.append(id)

func _es_de_clase(recurso: Resource, clase: String) -> bool:
	var script: Script = recurso.get_script()
	while script:
		if script.get_global_name() == StringName(clase):
			return true
		script = script.get_base_script()
	return false

## Override in a subclass whose id property is not called "id".
func _id_de(recurso: Resource) -> StringName:
	return recurso.id if "id" in recurso else &""

func _fallar(mensaje: String) -> void:
	_errores.append(mensaje)
	push_error(mensaje)

# --- Query API, identical for every registry ---------------------------------

func tiene(id: StringName) -> bool:
	return _por_id.has(id)

func obtener(id: StringName) -> Resource:
	return _por_id.get(id, null)

func obtener_todos() -> Array[Resource]:
	var salida: Array[Resource] = []
	for id in _orden:
		salida.append(_por_id[id])
	return salida

func obtener_ids() -> Array[StringName]:
	return _orden.duplicate()

func contar() -> int:
	return _orden.size()

## Errors collected during the last scan. The test suite asserts this is
## empty; nothing is swallowed.
func obtener_errores() -> PackedStringArray:
	return _errores.duplicate()
