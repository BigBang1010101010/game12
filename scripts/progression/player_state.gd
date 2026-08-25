extends Node

## Autoload holding the player's attribute values AND the audit ledger behind
## them. The ledger is the point: the game promises to justify every result
## with real statistics, which means being able to answer "where did my 73
## points of leadership come from?" down to the individual event.
##
## Attribute keys are built from AttributeRegistry at startup - nothing here
## names an attribute, so adding one is adding a .tres.

signal valor_cambiado(atributo_id: StringName, valor: float)

## Ledger entries older than this many in-game days are consolidated into
## per-(atributo, fuente_tipo, fuente_id) aggregates. The totals survive
## exactly; only the individual events are dropped. Raising it keeps more
## detail at the cost of memory; lowering it consolidates sooner.
const DIAS_ANTES_DE_CONSOLIDAR := 30.0

## Consolidation is checked at most this often (in appends) so a long play
## session does not walk the whole ledger on every single modification.
const APPENDS_ENTRE_REVISIONES := 200

## Detailed, per-event entries. Each is a Dictionary; see aplicar_modificador.
var ledger: Array[Dictionary] = []
## Consolidated aggregates for older history, keyed by
## "atributo|fuente_tipo|fuente_id".
var ledger_consolidado: Dictionary = {}

var _valores: Dictionary = {}
var _appends_desde_revision := 0
var _ultimo_dia_decaimiento := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	inicializar_desde_registro()
	EventBus.solicitar_modificador.connect(_on_solicitar_modificador)
	# Decay runs off the existing day/night cycle rather than its own timer,
	# so "a day of not practising" means the same day everything else uses.
	if DayNightCycle.has_signal("day_passed"):
		DayNightCycle.day_passed.connect(_on_dia_pasado)

## Builds the value table from whatever attributes exist. Called at startup and
## again after loading a save, so attributes added since that save appear with
## their valor_inicial instead of missing.
func inicializar_desde_registro() -> void:
	for definicion_res in AttributeRegistry.get_all_definitions():
		var definicion: AttributeDefinition = definicion_res
		if not _valores.has(definicion.id):
			_valores[definicion.id] = definicion.valor_inicial

func obtener_valor(atributo_id: StringName) -> float:
	return _valores.get(atributo_id, 0.0)

func obtener_todos_los_valores() -> Dictionary:
	return _valores.duplicate()

## Sets a value directly, bypassing curves. For the calibration lab and for
## loading saves only - gameplay goes through aplicar_modificador so it lands
## in the ledger.
func fijar_valor(atributo_id: StringName, valor: float) -> void:
	var definicion: AttributeDefinition = AttributeRegistry.get_definition(atributo_id)
	var maximo: float = definicion.valor_maximo if definicion else 100.0
	_valores[atributo_id] = clampf(valor, 0.0, maximo)
	valor_cambiado.emit(atributo_id, _valores[atributo_id])

func _on_solicitar_modificador(atributo_id: StringName, delta: float, fuente_tipo: StringName, fuente_id: StringName, contexto: Dictionary) -> void:
	aplicar_modificador(atributo_id, delta, fuente_tipo, fuente_id, contexto)

## THE entry point for changing an attribute during play.
##   fuente_tipo: category of origin, e.g. &"minijuego", &"hobby", &"ensayo",
##                &"hito", &"evento", &"decaimiento". Free-form: a new kind of
##                source is a new string, not a new enum case.
##   fuente_id:   which specific thing caused it.
##   contexto:    optional metadata (score, minutes spent, ...) kept verbatim
##                in the ledger so the breakdown can be as specific as the
##                caller was.
func aplicar_modificador(atributo_id: StringName, delta: float, fuente_tipo: StringName, fuente_id: StringName, contexto: Dictionary = {}) -> float:
	if not AttributeRegistry.tiene(atributo_id):
		push_error("PlayerState: atributo desconocido '%s' (fuente %s/%s)" % [atributo_id, fuente_tipo, fuente_id])
		return 0.0
	if is_zero_approx(delta):
		return 0.0

	var valor_actual: float = obtener_valor(atributo_id)
	var evaluacion: Dictionary = ModifierEngine.evaluar(atributo_id, delta, valor_actual)
	if evaluacion.is_empty():
		return 0.0

	_valores[atributo_id] = evaluacion["valor_despues"]
	_registrar(atributo_id, fuente_tipo, fuente_id, contexto, evaluacion)

	valor_cambiado.emit(atributo_id, _valores[atributo_id])
	EventBus.atributo_modificado.emit(atributo_id, evaluacion["delta_aplicado"], fuente_tipo, fuente_id)
	return evaluacion["delta_aplicado"]

## Ledger entry for a tracked quantity that is NOT an attribute - a
## relationship with a parent today, a reputation tomorrow.
##
## The ledger's promise is "justify every number with the events behind it",
## and that promise is not only about attributes. The entry has the same shape
## as an attribute's, so consolidation, filtering and the breakdown queries all
## keep working without knowing the difference; what it does NOT do is run the
## modifier engine, because curves, synergies and caps belong to attributes and
## the caller here has already decided its own arithmetic.
func registrar_cambio(clave: StringName, delta_aplicado: float, valor_antes: float, valor_despues: float, fuente_tipo: StringName, fuente_id: StringName, contexto: Dictionary = {}) -> void:
	if is_zero_approx(delta_aplicado):
		return
	ledger.append({
		"dia": dia_actual(),
		"atributo": clave,
		"fuente_tipo": fuente_tipo,
		"fuente_id": fuente_id,
		"contexto": contexto.duplicate(true),
		"delta_crudo": delta_aplicado,
		"delta_aplicado": delta_aplicado,
		"mult_rendimiento": 1.0,
		"mult_sinergia": 1.0,
		"sinergias": [],
		"valor_antes": valor_antes,
		"valor_despues": valor_despues,
	})
	_appends_desde_revision += 1
	if _appends_desde_revision >= APPENDS_ENTRE_REVISIONES:
		_appends_desde_revision = 0
		consolidar_ledger()

func _registrar(atributo_id: StringName, fuente_tipo: StringName, fuente_id: StringName, contexto: Dictionary, evaluacion: Dictionary) -> void:
	ledger.append({
		"dia": dia_actual(),
		"atributo": atributo_id,
		"fuente_tipo": fuente_tipo,
		"fuente_id": fuente_id,
		"contexto": contexto.duplicate(true),
		"delta_crudo": evaluacion["delta_crudo"],
		"delta_aplicado": evaluacion["delta_aplicado"],
		"mult_rendimiento": evaluacion["mult_rendimiento"],
		"mult_sinergia": evaluacion["mult_sinergia"],
		"sinergias": evaluacion["sinergias"],
		"valor_antes": evaluacion["valor_antes"],
		"valor_despues": evaluacion["valor_despues"],
	})
	_appends_desde_revision += 1
	if _appends_desde_revision >= APPENDS_ENTRE_REVISIONES:
		_appends_desde_revision = 0
		consolidar_ledger()

## In-game day number, taken from the shared clock so ledger timestamps line up
## with everything else that measures time.
func dia_actual() -> float:
	return DayNightCycle.total_elapsed_seconds / DayNightCycle.CYCLE_DURATION_SECONDS

# --- Consolidation -----------------------------------------------------------

## Collapses entries older than DIAS_ANTES_DE_CONSOLIDAR into aggregates so the
## ledger cannot grow without bound over a 40-hour save. Totals are preserved
## exactly; what is lost is the individual event detail of old history.
func consolidar_ledger() -> void:
	var corte: float = dia_actual() - DIAS_ANTES_DE_CONSOLIDAR
	if corte <= 0.0:
		return
	var recientes: Array[Dictionary] = []
	for entrada in ledger:
		if entrada["dia"] >= corte:
			recientes.append(entrada)
			continue
		var clave: String = "%s|%s|%s" % [entrada["atributo"], entrada["fuente_tipo"], entrada["fuente_id"]]
		var agregado: Dictionary = ledger_consolidado.get(clave, {
			"atributo": entrada["atributo"],
			"fuente_tipo": entrada["fuente_tipo"],
			"fuente_id": entrada["fuente_id"],
			"total": 0.0,
			"eventos": 0,
			"primer_dia": entrada["dia"],
			"ultimo_dia": entrada["dia"],
		})
		agregado["total"] += entrada["delta_aplicado"]
		agregado["eventos"] += 1
		agregado["primer_dia"] = minf(agregado["primer_dia"], entrada["dia"])
		agregado["ultimo_dia"] = maxf(agregado["ultimo_dia"], entrada["dia"])
		ledger_consolidado[clave] = agregado
	ledger = recientes

# --- Queries -----------------------------------------------------------------

## Filtered view over the detailed ledger. Any subset of keys may be given:
##   atributo, fuente_tipo, fuente_id, desde_dia, hasta_dia
## Consolidated history is not included here because it no longer has
## individual events; use obtener_desglose_atributo for totals that span both.
func consultar_ledger(filtros: Dictionary = {}) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	for entrada in ledger:
		if filtros.has("atributo") and entrada["atributo"] != filtros["atributo"]:
			continue
		if filtros.has("fuente_tipo") and entrada["fuente_tipo"] != filtros["fuente_tipo"]:
			continue
		if filtros.has("fuente_id") and entrada["fuente_id"] != filtros["fuente_id"]:
			continue
		if filtros.has("desde_dia") and entrada["dia"] < filtros["desde_dia"]:
			continue
		if filtros.has("hasta_dia") and entrada["dia"] > filtros["hasta_dia"]:
			continue
		salida.append(entrada)
	return salida

## The full "where did this number come from" breakdown for one attribute,
## spanning BOTH the detailed ledger and consolidated history. This is what the
## justification UI renders.
##
## Returns:
##   valor_actual
##   total_ganado / total_perdido
##   por_tipo:   fuente_tipo -> total
##   por_fuente: [{fuente_tipo, fuente_id, total, eventos}] sorted by |total|
func obtener_desglose_atributo(atributo_id: StringName) -> Dictionary:
	var por_fuente: Dictionary = {}
	var por_tipo: Dictionary = {}
	var ganado := 0.0
	var perdido := 0.0

	var acumular := func(fuente_tipo: StringName, fuente_id: StringName, total: float, eventos: int) -> void:
		var clave: String = "%s|%s" % [fuente_tipo, fuente_id]
		var registro: Dictionary = por_fuente.get(clave, {
			"fuente_tipo": fuente_tipo, "fuente_id": fuente_id, "total": 0.0, "eventos": 0,
		})
		registro["total"] += total
		registro["eventos"] += eventos
		por_fuente[clave] = registro
		por_tipo[fuente_tipo] = por_tipo.get(fuente_tipo, 0.0) + total

	for entrada in ledger:
		if entrada["atributo"] != atributo_id:
			continue
		var delta: float = entrada["delta_aplicado"]
		if delta >= 0.0:
			ganado += delta
		else:
			perdido += delta
		acumular.call(entrada["fuente_tipo"], entrada["fuente_id"], delta, 1)

	for clave in ledger_consolidado:
		var agregado: Dictionary = ledger_consolidado[clave]
		if agregado["atributo"] != atributo_id:
			continue
		if agregado["total"] >= 0.0:
			ganado += agregado["total"]
		else:
			perdido += agregado["total"]
		acumular.call(agregado["fuente_tipo"], agregado["fuente_id"], agregado["total"], agregado["eventos"])

	var lista: Array[Dictionary] = []
	for clave in por_fuente:
		lista.append(por_fuente[clave])
	lista.sort_custom(func(a, b): return absf(a["total"]) > absf(b["total"]))

	return {
		"atributo": atributo_id,
		"valor_actual": obtener_valor(atributo_id),
		"total_ganado": ganado,
		"total_perdido": perdido,
		"por_tipo": por_tipo,
		"por_fuente": lista,
	}

func _on_dia_pasado() -> void:
	var dia: float = dia_actual()
	var dias: float = maxf(dia - _ultimo_dia_decaimiento, 0.0)
	_ultimo_dia_decaimiento = dia
	ModifierEngine.aplicar_decaimiento_diario(dias)

## Wipes progression state. Used by the calibration lab and by loading a save.
func reiniciar() -> void:
	_valores.clear()
	ledger.clear()
	ledger_consolidado.clear()
	_appends_desde_revision = 0
	_ultimo_dia_decaimiento = dia_actual()
	inicializar_desde_registro()
