extends Node

## Save/load for progression state, built so that YEARS of added content never
## invalidate an existing save.
##
## Three guarantees:
##  - every file carries a schema version, and older versions are migrated
##    forward step by step rather than rejected;
##  - an attribute that did not exist when the save was written appears at its
##    valor_inicial instead of crashing;
##  - an attribute that no longer exists is dropped with a warning instead of
##    poisoning the state.

## Bump this whenever the saved SHAPE changes, and add a matching entry to
## _MIGRACIONES so old files keep loading.
const VERSION_ESQUEMA := 1
const RUTA_POR_DEFECTO := "user://progresion.save"

## version_origen -> Callable(datos) -> datos, taking a save from that version
## to the next one. Migrations are applied in sequence, so a version 1 file
## loaded by a future version 4 build runs 1->2, 2->3, 3->4 in order and no
## single migration ever has to know the whole history.
##
## Empty today because only version 1 exists; the machinery is here so adding
## the first real migration is adding one entry, not building the system then.
var _MIGRACIONES: Dictionary = {}

func guardar(ruta: String = RUTA_POR_DEFECTO) -> bool:
	var datos: Dictionary = {
		"version_esquema": VERSION_ESQUEMA,
		"version_formula": AdmissionCalculator.FORMULA_VERSION,
		"guardado_en_dia": PlayerState.dia_actual(),
		"atributos": PlayerState.obtener_todos_los_valores(),
		"ledger": PlayerState.ledger,
		"ledger_consolidado": PlayerState.ledger_consolidado,
		"reloj_total_segundos": DayNightCycle.total_elapsed_seconds,
		"elecciones": elecciones.duplicate(true),
		"hitos": hitos.duplicate(),
	}
	var archivo := FileAccess.open(ruta, FileAccess.WRITE)
	if not archivo:
		push_error("SaveSystem: no se pudo escribir '%s' (error %d)" % [ruta, FileAccess.get_open_error()])
		return false
	archivo.store_string(JSON.stringify(datos))
	archivo.close()
	return true

func cargar(ruta: String = RUTA_POR_DEFECTO) -> bool:
	if not FileAccess.file_exists(ruta):
		return false
	var archivo := FileAccess.open(ruta, FileAccess.READ)
	if not archivo:
		push_error("SaveSystem: no se pudo leer '%s' (error %d)" % [ruta, FileAccess.get_open_error()])
		return false
	var texto := archivo.get_as_text()
	archivo.close()

	var parseado: Variant = JSON.parse_string(texto)
	if typeof(parseado) != TYPE_DICTIONARY:
		push_error("SaveSystem: '%s' esta corrupto o no es un guardado valido" % ruta)
		return false
	var datos: Dictionary = parseado

	datos = migrar(datos)
	if datos.is_empty():
		return false

	_aplicar(datos)
	return true

## Runs the save forward through every migration between its version and ours.
func migrar(datos: Dictionary) -> Dictionary:
	var version: int = int(datos.get("version_esquema", 0))
	if version > VERSION_ESQUEMA:
		push_error("SaveSystem: el guardado es de la version %d y este build entiende hasta la %d. Se cancela la carga para no corromperlo." % [version, VERSION_ESQUEMA])
		return {}
	while version < VERSION_ESQUEMA:
		if not _MIGRACIONES.has(version):
			push_error("SaveSystem: falta la migracion de la version %d a la %d" % [version, version + 1])
			return {}
		datos = (_MIGRACIONES[version] as Callable).call(datos)
		version += 1
		datos["version_esquema"] = version
	return datos

func _aplicar(datos: Dictionary) -> void:
	DayNightCycle.total_elapsed_seconds = float(datos.get("reloj_total_segundos", 0.0))
	PlayerState.reiniciar()

	# Attributes: start everything at its declared initial value, then overlay
	# whatever the save knew about. Anything the save is missing therefore
	# lands on valor_inicial automatically, and anything it has that we no
	# longer define is reported and skipped.
	var guardados: Dictionary = datos.get("atributos", {})
	var desconocidos: Array[String] = []
	for clave in guardados:
		var id := StringName(clave)
		if not AttributeRegistry.tiene(id):
			desconocidos.append(String(clave))
			continue
		PlayerState.fijar_valor(id, float(guardados[clave]))
	if not desconocidos.is_empty():
		push_warning("SaveSystem: el guardado trae atributos que ya no existen y se ignoran: %s" % ", ".join(desconocidos))

	var nuevos: Array[String] = []
	for id in AttributeRegistry.get_all_ids():
		if not guardados.has(String(id)):
			nuevos.append(String(id))
	if not nuevos.is_empty():
		push_warning("SaveSystem: atributos agregados despues de este guardado, inicializados en su valor_inicial: %s" % ", ".join(nuevos))

	PlayerState.ledger = _normalizar_ledger(datos.get("ledger", []))
	PlayerState.ledger_consolidado = datos.get("ledger_consolidado", {})
	elecciones = datos.get("elecciones", {})
	hitos = datos.get("hitos", [])

## JSON turns StringNames into plain strings and ints into floats; restore the
## types the rest of the code expects so a loaded ledger behaves exactly like a
## live one.
func _normalizar_ledger(crudo: Variant) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	if typeof(crudo) != TYPE_ARRAY:
		return salida
	for entrada in crudo:
		if typeof(entrada) != TYPE_DICTIONARY:
			continue
		var copia: Dictionary = (entrada as Dictionary).duplicate(true)
		for clave in ["atributo", "fuente_tipo", "fuente_id"]:
			if copia.has(clave):
				copia[clave] = StringName(copia[clave])
		salida.append(copia)
	return salida

# --- Player choices and milestones ------------------------------------------
# Kept here rather than in PlayerState because they are save data, not derived
# state. Free-form dictionaries so a new kind of choice needs no schema change.

var elecciones: Dictionary = {}
var hitos: Array = []

func fijar_eleccion(clave: StringName, valor: Variant) -> void:
	elecciones[String(clave)] = valor

func obtener_eleccion(clave: StringName, por_defecto: Variant = null) -> Variant:
	return elecciones.get(String(clave), por_defecto)

func desbloquear_hito(hito_id: StringName) -> void:
	if hitos.has(String(hito_id)):
		return
	hitos.append(String(hito_id))
	EventBus.avisar_hito(hito_id)

func tiene_hito(hito_id: StringName) -> bool:
	return hitos.has(String(hito_id))
