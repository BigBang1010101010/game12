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
const VERSION_ESQUEMA := 5
const RUTA_POR_DEFECTO := "user://progresion.save"

## version_origen -> Callable(datos) -> datos, taking a save from that version
## to the next one. Migrations are applied in sequence, so a version 1 file
## loaded by a future version 4 build runs 1->2, 2->3, 3->4 in order and no
## single migration ever has to know the whole history.
##
var _MIGRACIONES: Dictionary = {
	# 1 -> 2: activities arrived. A version 1 save simply has none, which is
	# exactly what an empty table means, so the migration states that rather
	# than leaving the key missing for _aplicar to guess at.
	1: func(datos: Dictionary) -> Dictionary:
		datos["actividades"] = {}
		datos["seleccion_common_app"] = []
		datos["version_esquema"] = 2
		return datos,
	# 2 -> 3: birthplace and the family relationship arrived. A version 2 save
	# has neither, and an empty family table means "start everyone at their
	# declared level", which is exactly right for a run that predates the
	# system.
	2: func(datos: Dictionary) -> Dictionary:
		datos["familia"] = {}
		datos["version_esquema"] = 3
		return datos,
	# 3 -> 4: money arrived. A save from before it has no balances, and the
	# right reading of that is not "zero": it is "this run never had a wallet",
	# so the wallet re-seeds itself from the birthplace on load instead.
	3: func(datos: Dictionary) -> Dictionary:
		datos["dinero"] = {}
		datos["credito"] = {}
		datos["version_esquema"] = 4
		return datos,
	# 4 -> 5: sport statistics arrived. A save from before them has none, which
	# is exactly what an empty table means: that run's athletes keep whatever
	# recognition they were given by hand until the first number is posted.
	4: func(datos: Dictionary) -> Dictionary:
		datos["estadisticas_deportivas"] = {}
		datos["version_esquema"] = 5
		return datos,
}

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
		"actividades": ActivityTracker.obtener_todos_los_estados(),
		"familia": FamilyRelationship.obtener_estado(),
		"dinero": Wallet.obtener_estado(),
		"estadisticas_deportivas": SportStatsTracker.obtener_estado(),
		"credito": FamilyCredit.obtener_estado(),
		"seleccion_common_app": _ids_seleccionados(),
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

	# Activities: same discipline as attributes. One that no longer exists is
	# dropped with a warning instead of poisoning the state, and the manual
	# Common App choice is restored only for activities that survived.
	# Statistics BEFORE activities: a sport's ladder reads the recognition its
	# numbers derive, so the numbers have to be in place first.
	SportStatsTracker.reiniciar()
	SportStatsTracker.cargar_estado(datos.get("estadisticas_deportivas", {}))
	ActivityTracker.reiniciar()
	ActivityTracker.cargar_estado(datos.get("actividades", {}))
	# The birthplace lives in `elecciones`, which was just restored above, so
	# this only has to re-read it. Family relationships come back with the same
	# discipline as everything else: a parent who no longer exists is dropped.
	PlayerOrigin.reiniciar()
	PlayerOrigin.cargar_desde_guardado()
	FamilyRelationship.cargar_estado(datos.get("familia", {}))

	# Money: a save that predates the wallet re-seeds from the birthplace, so
	# an old run does not silently start broke.
	var dinero: Dictionary = datos.get("dinero", {})
	if dinero.is_empty():
		Wallet.reiniciar_desde_origen()
	else:
		Wallet.cargar_estado(dinero)
	FamilyCredit.cargar_estado(datos.get("credito", {}))
	ConsultingService.reiniciar()

	var seleccion: Array = datos.get("seleccion_common_app", [])
	if seleccion.is_empty():
		ApplicationBuilder.limpiar_seleccion_manual()
	else:
		var vigentes: Array = []
		for id in seleccion:
			if ActivityTracker.esta_activa(StringName(id)):
				vigentes.append(StringName(id))
		ApplicationBuilder.fijar_seleccion_manual(vigentes)

## JSON turns StringNames into plain strings and ints into floats; restore the
## types the rest of the code expects so a loaded ledger behaves exactly like a
## live one.
## Ids of the manual Common App choice, empty when it is automatic.
func _ids_seleccionados() -> Array:
	if not ApplicationBuilder.hay_seleccion_manual():
		return []
	var ids: Array = []
	for entrada in ApplicationBuilder.obtener_seleccion():
		ids.append(String(entrada["actividad_id"]))
	return ids

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
