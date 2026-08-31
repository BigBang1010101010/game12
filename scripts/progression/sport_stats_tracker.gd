extends Node

## Autoload holding the player's actual sporting numbers, and deriving what
## those numbers are worth.
##
## The point of this file is that an athlete's recognition stops being a value
## someone chose. A rower does not "have state-level recognition" because a
## designer said so: they pulled a 6:28 2k, and the benchmark table says a 6:28
## is state level. Everything downstream - the activity ladder, whether a coach
## would recruit them, the admission bonus - hangs off that number.
##
## It names no sport and no statistic: both come from the registries.

signal stat_registrada(deporte_id: StringName, categoria_id: StringName, valor: float, mejoro: bool)
signal reconocimiento_cambiado(deporte_id: StringName, antes: StringName, despues: StringName)

const FUENTE := &"estadistica"

## deporte_id -> {categoria_id: valor}
var _valores: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# --- The hook minigames will call -------------------------------------------

## THE entry point for a sports minigame. None exist yet; this is the hook they
## will call, and everything behind it already works, which is why the
## calibration lab can drive it today.
##
## A result only counts when it BEATS the player's own record for that
## statistic - a bad game does not erase a good season, and a personal best is
## what a coach is shown. Returns a dictionary the caller can display:
##   {exito, mejoro, valor, anterior, reconocimiento_antes, reconocimiento_despues}
func registrar_resultado_minijuego(deporte_id: StringName, categoria_id: StringName, valor: float) -> Dictionary:
	var categoria: SportStatCategory = SportStatRegistry.obtener(categoria_id)
	if not categoria:
		push_error("SportStatsTracker: estadistica desconocida '%s'" % categoria_id)
		return {"exito": false, "motivo": "categoria_desconocida"}
	if categoria.deporte_id != deporte_id:
		push_error("SportStatsTracker: '%s' no es una estadistica de '%s' sino de '%s'" % [
			categoria_id, deporte_id, categoria.deporte_id])
		return {"exito": false, "motivo": "deporte_incorrecto"}

	var anterior: float = obtener_valor(deporte_id, categoria_id)
	var tenia: bool = _valores.get(deporte_id, {}).has(categoria_id)
	# A counting statistic adds to the season; a rate keeps the best figure.
	var acumulado: float = anterior + valor if categoria.acumulativa else valor
	var mejoro: bool = (valor > 0.0 if categoria.acumulativa
		else (not tenia or (valor > anterior if categoria.es_mejor_mayor else valor < anterior)))
	if not mejoro:
		return {"exito": true, "mejoro": false, "valor": anterior, "anterior": anterior,
			"reconocimiento_antes": reconocimiento_derivado(deporte_id),
			"reconocimiento_despues": reconocimiento_derivado(deporte_id)}

	var antes: StringName = reconocimiento_derivado(deporte_id)
	_fijar(deporte_id, categoria_id, acumulado, anterior if tenia else 0.0, FUENTE)
	var despues: StringName = reconocimiento_derivado(deporte_id)
	stat_registrada.emit(deporte_id, categoria_id, acumulado, true)
	if antes != despues:
		reconocimiento_cambiado.emit(deporte_id, antes, despues)
	return {"exito": true, "mejoro": true, "valor": acumulado, "anterior": anterior,
		"reconocimiento_antes": antes, "reconocimiento_despues": despues}

## Sets a value outright, beating or not. Used by the calibration lab and by
## anything restoring state; gameplay goes through the method above.
func fijar_valor(deporte_id: StringName, categoria_id: StringName, valor: float) -> void:
	var categoria: SportStatCategory = SportStatRegistry.obtener(categoria_id)
	if not categoria or categoria.deporte_id != deporte_id:
		push_error("SportStatsTracker.fijar_valor: '%s' no pertenece a '%s'" % [categoria_id, deporte_id])
		return
	var antes: StringName = reconocimiento_derivado(deporte_id)
	_fijar(deporte_id, categoria_id, valor, obtener_valor(deporte_id, categoria_id), &"calibracion")
	var despues: StringName = reconocimiento_derivado(deporte_id)
	stat_registrada.emit(deporte_id, categoria_id, valor, true)
	if antes != despues:
		reconocimiento_cambiado.emit(deporte_id, antes, despues)

func _fijar(deporte_id: StringName, categoria_id: StringName, valor: float, anterior: float, fuente: StringName) -> void:
	if not _valores.has(deporte_id):
		_valores[deporte_id] = {}
	_valores[deporte_id][categoria_id] = valor
	# Into the same ledger as everything else: a recognition that changed a
	# ladder has to be traceable back to the performance that caused it.
	PlayerState.registrar_cambio(
		StringName("stat_" + String(categoria_id)), valor - anterior, anterior, valor,
		fuente, deporte_id, {"categoria": categoria_id})

# --- Reading ----------------------------------------------------------------

func tiene_stats(deporte_id: StringName) -> bool:
	return not (_valores.get(deporte_id, {}) as Dictionary).is_empty()

func obtener_valor(deporte_id: StringName, categoria_id: StringName) -> float:
	return float((_valores.get(deporte_id, {}) as Dictionary).get(categoria_id, 0.0))

func obtener_stats(deporte_id: StringName) -> Dictionary:
	return (_valores.get(deporte_id, {}) as Dictionary).duplicate()

## Recognition one statistic earns on its own.
func reconocimiento_de_categoria(deporte_id: StringName, categoria_id: StringName) -> StringName:
	var benchmark: StatBenchmark = StatBenchmarkRegistry.para_categoria(categoria_id)
	var categoria: SportStatCategory = SportStatRegistry.obtener(categoria_id)
	if not benchmark or not categoria:
		return &"ninguno"
	if not (_valores.get(deporte_id, {}) as Dictionary).has(categoria_id):
		return &"ninguno"
	return benchmark.reconocimiento_para(obtener_valor(deporte_id, categoria_id), categoria.es_mejor_mayor)

## Recognition for the sport as a whole: the BEST any single statistic earns.
##
## Best rather than average on purpose - nobody is recruited for being evenly
## mediocre, and a pitcher with a 0.80 ERA is not held back by a weak batting
## average.
func reconocimiento_derivado(deporte_id: StringName) -> StringName:
	var mejor := 0
	for categoria_id in _valores.get(deporte_id, {}):
		var indice: int = ActivityScales.indice_reconocimiento(
			reconocimiento_de_categoria(deporte_id, categoria_id))
		mejor = maxi(mejor, indice)
	return ActivityScales.nombre_reconocimiento(mejor)

## Everything a UI needs about one sport:
## [{categoria, nombre, valor, texto, unidad, reconocimiento, siguiente}]
func desglose(deporte_id: StringName) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	for categoria_res in SportStatRegistry.obtener_por_deporte(deporte_id):
		var categoria: SportStatCategory = categoria_res
		var valor: float = obtener_valor(deporte_id, categoria.id)
		var benchmark: StatBenchmark = StatBenchmarkRegistry.para_categoria(categoria.id)
		var siguiente: Dictionary = {}
		if benchmark and (_valores.get(deporte_id, {}) as Dictionary).has(categoria.id):
			siguiente = benchmark.siguiente_banda(valor, categoria.es_mejor_mayor)
		salida.append({
			"categoria": categoria.id,
			"nombre": categoria.nombre_display,
			"unidad": categoria.unidad,
			"valor": valor,
			"registrada": (_valores.get(deporte_id, {}) as Dictionary).has(categoria.id),
			"texto": categoria.formatear(valor),
			"reconocimiento": reconocimiento_de_categoria(deporte_id, categoria.id),
			"siguiente": siguiente,
		})
	return salida

# --- Persistence ------------------------------------------------------------

func obtener_estado() -> Dictionary:
	return _valores.duplicate(true)

func cargar_estado(datos: Dictionary) -> void:
	_valores.clear()
	for deporte in datos:
		for categoria in datos[deporte]:
			var cat: SportStatCategory = SportStatRegistry.obtener(StringName(categoria))
			if not cat or cat.deporte_id != StringName(deporte):
				push_warning("SportStatsTracker: el guardado trae '%s/%s', que ya no existe" % [deporte, categoria])
				continue
			if not _valores.has(StringName(deporte)):
				_valores[StringName(deporte)] = {}
			_valores[StringName(deporte)][StringName(categoria)] = float(datos[deporte][categoria])

func reiniciar() -> void:
	_valores.clear()
