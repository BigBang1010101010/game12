extends Node

## Autoload turning the week into a finite resource.
##
## A week holds a fixed number of hours (config), every active activity claims
## its own costo_horas_semana, and going over is not free: overcommitment
## charges the attributes the config names, week after week, straight into the
## audit ledger. That is the burnout model, and it is what stops "sign up for
## everything" from being the dominant strategy.
##
## It names no activity and no attribute: the costs come from each activity's
## data and the price of burnout comes from the config resource.

signal presupuesto_cambiado(comprometidas: float, totales: float)
signal sobrecompromiso_cobrado(exceso: float, penalizaciones: Dictionary)

const FUENTE := &"sobrecompromiso"
const ORIGEN := &"presupuesto_tiempo"
const DIAS_POR_SEMANA := 7.0

var _dias_acumulados := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Burnout is charged per week of the same calendar everything else uses,
	# not on a timer of its own.
	DayNightCycle.day_passed.connect(_on_dia_pasado)
	ActivityTracker.actividad_iniciada.connect(func(_id): _avisar())

func horas_totales() -> float:
	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	return float(config.horas_semana_totales) if config else 0.0

## Hours a week the player has already promised away.
func horas_comprometidas() -> float:
	return horas_de(ActivityTracker.actividades_activas())

## Same sum for any hypothetical set of activities, for the calibration lab.
func horas_de(actividades: Array) -> float:
	var total := 0.0
	for actividad_id in actividades:
		var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
		if actividad:
			total += float(actividad.costo_horas_semana)
	return total

func horas_disponibles() -> float:
	return horas_totales() - horas_comprometidas()

## Hours over the budget, 0.0 when inside it.
func horas_excedidas(actividades: Array = []) -> float:
	var comprometidas: float = horas_de(actividades) if not actividades.is_empty() else horas_comprometidas()
	return maxf(comprometidas - horas_totales(), 0.0)

func esta_sobrecomprometido() -> bool:
	return horas_excedidas() > 0.0

## What one week over budget costs, WITHOUT applying it: atributo_id -> points.
## The UI warns with this before the player commits.
func penalizacion_semanal(actividades: Array = []) -> Dictionary:
	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	var exceso: float = horas_excedidas(actividades)
	var salida: Dictionary = {}
	if not config or exceso <= 0.0:
		return salida
	for atributo_id in config.penalizacion_sobrecompromiso:
		salida[atributo_id] = -float(config.penalizacion_sobrecompromiso[atributo_id]) * exceso
	return salida

## Charges one week of overcommitment. Called by the calendar; safe to call
## directly from tests.
func aplicar_semana() -> Dictionary:
	var penalizaciones: Dictionary = penalizacion_semanal()
	if penalizaciones.is_empty():
		return penalizaciones
	var exceso: float = horas_excedidas()
	for atributo_id in penalizaciones:
		PlayerState.aplicar_modificador(atributo_id, penalizaciones[atributo_id], FUENTE, ORIGEN, {
			"horas_excedidas": exceso,
			"horas_comprometidas": horas_comprometidas(),
			"horas_totales": horas_totales(),
		})
	sobrecompromiso_cobrado.emit(exceso, penalizaciones)
	return penalizaciones

func _on_dia_pasado() -> void:
	_dias_acumulados += 1.0
	while _dias_acumulados >= DIAS_POR_SEMANA:
		_dias_acumulados -= DIAS_POR_SEMANA
		aplicar_semana()

func _avisar() -> void:
	presupuesto_cambiado.emit(horas_comprometidas(), horas_totales())
