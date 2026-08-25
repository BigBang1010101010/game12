extends Node

## Autoload deciding WHICH of the player's activities actually reach the
## application.
##
## The real Common App has ten slots. Everything else the player did still
## happened - it is in the ledger, it moved their attributes - but it is never
## read by an admissions office, and the game models that honestly rather than
## quietly counting everything.
##
## Ranking is tier x continuity x impact, all three read from data. Nothing
## here knows what any activity is.

signal seleccion_cambiada(seleccion: Array)

var _seleccion_manual: Array[StringName] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func slots() -> int:
	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	return config.slots_common_app if config else 10

## How strongly one activity would read on an application.
##
##   (5 - tier)  a tier 1 activity is worth four times a tier 4 one
##   x continuity  four years of the same thing beats four different things
##   x (1 + impacto/referencia)  measurable impact is what separates two
##     otherwise identical presidencies
##
## An activity whose first rung has not been credited yet scores 0: joining
## something is not an achievement.
func puntuar(actividad_id: StringName, estado: Dictionary) -> float:
	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	var tier: int = ActivityTracker.tier_actual(actividad_id, estado)
	if tier > 4:
		return 0.0
	var continuidad: float = ActivityTracker.multiplicador_continuidad(float(estado.get("anios_invertidos", 0.0)))
	var referencia: float = config.impacto_referencia if config else 500.0
	var impacto: float = 1.0 + float(estado.get("impacto", 0.0)) / maxf(referencia, 0.0001)
	return float(5 - tier) * continuidad * impacto

## Turns raw activity states into ranked application entries. Shared by the
## live player and by any hypothetical profile, so the calibration lab ranks
## with exactly the game's own logic.
##
## Each entry: {actividad_id, nombre, tier, anios, impacto, continuidad,
##              puntaje, reconocimiento, rol, es_deporte, reclutable}
func detalle_desde_estados(estados: Dictionary, indice_academico: float = -1.0) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	for actividad_id in estados:
		var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
		if not actividad:
			continue
		var estado: Dictionary = estados[actividad_id]
		salida.append({
			"actividad_id": actividad.id,
			"nombre": actividad.nombre_display,
			"tier": ActivityTracker.tier_actual(actividad.id, estado),
			"anios": float(estado.get("anios_invertidos", 0.0)),
			"impacto": float(estado.get("impacto", 0.0)),
			"continuidad": ActivityTracker.multiplicador_continuidad(float(estado.get("anios_invertidos", 0.0))),
			"puntaje": puntuar(actividad.id, estado),
			# Carried so the admission calculator can re-check the recruitment
			# gates against ITS own Academic Index instead of trusting one
			# computed here.
			# Effective, not stored: for a sport with statistics this is what
			# the numbers earned, which is what the admission calculator has to
			# re-check its recruitment gates against.
			"reconocimiento": ActivityTracker.reconocimiento_efectivo(actividad.id, estado),
			"rol": estado.get("rol", &"miembro"),
			"es_deporte": actividad.es_deporte,
			"reclutable": ActivityTracker.es_reclutable(actividad.id, indice_academico, estado),
		})
	salida.sort_custom(func(a, b): return a["puntaje"] > b["puntaje"])
	return salida

## The full ranking for the live player, best first.
func ranking(indice_academico: float = -1.0) -> Array[Dictionary]:
	return detalle_desde_estados(ActivityTracker.obtener_todos_los_estados(), indice_academico)

## The best N, chosen automatically.
func seleccion_automatica(indice_academico: float = -1.0) -> Array[Dictionary]:
	return seleccionar(ranking(indice_academico))

## Cuts any ranked list down to the available slots.
func seleccionar(detalles: Array[Dictionary]) -> Array[Dictionary]:
	var limite: int = mini(slots(), detalles.size())
	return detalles.slice(0, limite)

## Lets the player override the automatic choice. Ids that are not active are
## dropped with a warning rather than silently accepted.
func fijar_seleccion_manual(ids: Array) -> void:
	_seleccion_manual.clear()
	for id in ids:
		if ActivityTracker.esta_activa(id):
			_seleccion_manual.append(id)
		else:
			push_warning("ApplicationBuilder: '%s' no es una actividad activa" % id)
	if _seleccion_manual.size() > slots():
		_seleccion_manual = _seleccion_manual.slice(0, slots())
	seleccion_cambiada.emit(_seleccion_manual.duplicate())

func limpiar_seleccion_manual() -> void:
	_seleccion_manual.clear()
	seleccion_cambiada.emit([])

func hay_seleccion_manual() -> bool:
	return not _seleccion_manual.is_empty()

## What the application actually carries: the manual choice if there is one,
## otherwise the automatic top N.
func obtener_seleccion(indice_academico: float = -1.0) -> Array[Dictionary]:
	if _seleccion_manual.is_empty():
		return seleccion_automatica(indice_academico)
	var estados: Dictionary = {}
	for id in _seleccion_manual:
		estados[id] = ActivityTracker.obtener_estado(id)
	return detalle_desde_estados(estados, indice_academico)

## Activities that were left off the application, for the UI that has to
## explain why something the player cared about is not being counted.
func fuera_de_slots(indice_academico: float = -1.0) -> Array[Dictionary]:
	var completo: Array[Dictionary] = ranking(indice_academico)
	var dentro: Array[Dictionary] = seleccionar(completo)
	return completo.slice(dentro.size(), completo.size())
